*This project has been created as part of the 42 curriculum by chimex.*

# Inception

## Description

Inception is a system-administration project: build a small, production-shaped
web infrastructure from scratch with Docker, where every service runs in its own
container, from an image written by hand.

The mandatory stack is three containers behind a single TLS entry point:

```
                    ┌─────────────────────────────────────────────┐
   host :443 ───────▶  nginx        TLSv1.2 / TLSv1.3 only        │
                    │    │  static files from the shared volume    │
                    │    │  *.php ──▶ FastCGI                      │
                    │    ▼                                         │
                    │  wordpress    php-fpm 8.2, no web server     │
                    │    │                                         │
                    │    ▼                                         │
                    │  mariadb      10.11, never published         │
                    └──────────── docker network "inception" ──────┘
                             │                        │
                    volume: wordpress_files    volume: mariadb_data
                    /home/chimex/data/wordpress   /home/chimex/data/mariadb
```

Nothing is pulled ready-made: `nginx:inception`, `wordpress:inception` and
`mariadb:inception` are all built here from `debian:bookworm`, and the only
image downloaded from a registry is Debian itself.

The **bonus** part adds five more services — redis, FTP, Adminer, a static
showcase site and a home-made status dashboard — in a *separate* compose file,
so the mandatory infrastructure can always be run and evaluated on its own.

| | Service | Image | Role |
|---|---|---|---|
| **mandatory** | nginx | `nginx:inception` | TLS termination, the only published entry point (443) |
| | wordpress | `wordpress:inception` | WordPress 6.7 on php-fpm 8.2, FastCGI on :9000 |
| | mariadb | `mariadb:inception` | MariaDB 10.11, reachable only on the docker network |
| **bonus** | redis | `redis:inception` | WordPress object cache, 256 MB, LRU eviction |
| | ftp | `ftp:inception` | vsftpd, chrooted on the WordPress volume |
| | adminer | `adminer:inception` | Database administration UI |
| | static-site | `static-site:inception` | Showcase site in HTML/CSS/JS (no PHP) |
| | status | `status:inception` | Home-made health dashboard (the free-choice service) |

## Instructions

### Requirements

- a Linux host (the subject asks for a virtual machine) with `docker` and the
  `docker compose` v2 plugin
- `make`, `openssl` and `curl`
- the user must be able to run `docker` (member of the `docker` group)

### Run it

```bash
make            # mandatory stack only  → https://chimex.42.fr
make bonus      # mandatory + the five bonus services
make test       # the mandatory checks
make test-bonus # the bonus checks
make down       # stop everything, keep the data
make fclean     # remove containers, images, volumes and /home/chimex/data
make re         # fclean + make
make help       # every target
```

The first `make` also performs the one-time setup: it creates
`/home/chimex/data/{wordpress,mariadb}`, generates a random password for each
secret in `secrets/`, and adds `chimex.42.fr` (plus the bonus sub-domains) to
`/etc/hosts` — that last step is the only one that asks for `sudo`.

The certificate is self-signed, so a browser will show a warning once; that is
expected for a local `*.42.fr` domain.

Day-to-day usage is described in [USER_DOC.md](USER_DOC.md), the developer
workflow in [DEV_DOC.md](DEV_DOC.md), and the verification plan in
[TESTING_ROADMAP.md](TESTING_ROADMAP.md).

## Project description

### How Docker is used here, and where the sources come from

Every service has its own directory under `srcs/requirements/` containing a
`Dockerfile`, its configuration, and an entrypoint script when one is needed.
`docker-compose.yml` builds those Dockerfiles — it never references a
pre-built application image. The only base image is `debian:bookworm`
(Debian 12), the *penultimate* stable Debian, as the subject requires: Debian 13
"trixie" is the current stable release.

Application sources are fetched at build or first start, from their official
origin and at a pinned version:

| Source | Where it comes from | Version |
|---|---|---|
| nginx, php-fpm, MariaDB, redis, vsftpd | Debian bookworm packages | distribution |
| WP-CLI | GitHub release, `wp-cli/wp-cli` | 2.11.0 |
| WordPress core | `wp core download` | 6.7.1 |
| Adminer | GitHub release, `vrana/adminer` | 4.8.1 |
| Redis Object Cache plugin | wordpress.org, via WP-CLI | 2.8.0 |

### Main design choices

**One process per container, and it is PID 1.** Every entrypoint ends with
`exec`, so the real daemon replaces the shell: `nginx -g "daemon off;"`,
`php-fpm8.2 -F`, `mariadbd`, `redis-server`, `vsftpd`. Nothing is kept alive by
`tail -f`, `sleep infinity` or a `while true` loop. This matters for more than
style — PID 1 receives `SIGTERM` from Docker directly, so `docker compose down`
shuts MariaDB down cleanly instead of killing it after a 10-second timeout.

**Initialisation is idempotent and happens once.** The MariaDB entrypoint
initialises the data directory only when the volume is empty and creates the
database with `mariadbd --bootstrap`, which executes a batch of SQL and exits:
the server is never briefly reachable without a root password. The WordPress
entrypoint installs the site with WP-CLI only when `wp-config.php` is missing.
Restarting a container therefore changes nothing.

**Passwords never exist as environment variables.** They are Docker secrets,
mounted read-only at `/run/secrets/<name>`, and read by the entrypoints. The
`.env` file holds only non-sensitive configuration (domain, database name, user
names). `secrets/*.txt` is git-ignored and generated locally by `make secrets`.

**The mandatory part stands alone.** The bonus lives in
`docker-compose.bonus.yml` and `srcs/requirements/bonus/`. That overlay only
*adds*: five services, plus two environment variables that switch on behaviour
which stays dormant otherwise (`ENABLE_BONUS=1` makes nginx publish the bonus
sub-domains; `REDIS_HOST` makes the WordPress entrypoint install and enable the
object cache). `make` alone still produces exactly the infrastructure the
subject describes.

**443 stays the only door.** The bonus web services are reached through nginx on
sub-domains (`static.`, `adminer.`, `status.`) rather than by publishing extra
ports. FTP is the single exception, because the FTP protocol cannot be proxied
by an HTTP reverse proxy — the subject explicitly allows extra ports for bonus
services.

### Virtual machines vs Docker

A virtual machine emulates hardware and boots a whole guest kernel; a container
is a set of processes on the *host* kernel, isolated by namespaces (pid, net,
mount, uts, ipc) and limited by cgroups. The practical differences:

| | Virtual machine | Docker container |
|---|---|---|
| Kernel | its own | shared with the host |
| Boot time | tens of seconds | milliseconds |
| Cost per instance | hundreds of MB of RAM | a few MB |
| Isolation | strong (hardware boundary) | weaker (a kernel exploit escapes) |
| Portable image | a multi-GB disk image | layers, built from a text file |

Running eight of these services as eight VMs would need several GB of RAM and
eight OS installations to patch. As containers they share one kernel and one
Debian base layer. The trade-off is real, though: containers are a *weaker*
boundary, which is why this project still runs inside a VM — the school's rule
is a security decision, not a formality.

### Secrets vs environment variables

Environment variables are convenient and *visible*: `docker inspect` prints
them, `/proc/<pid>/environ` exposes them to anything running in the container,
they are inherited by every child process, and they routinely end up in crash
dumps and logs. Anything written in a `Dockerfile` is worse still — it is baked
into a layer and travels with the image forever.

Docker secrets are files mounted read-only in a `tmpfs` at `/run/secrets/`.
They never touch a layer, never appear in `docker inspect`, are not inherited by
child processes, and vanish with the container.

The rule used here: **configuration** (`DOMAIN_NAME`, `MYSQL_DATABASE`,
`MYSQL_USER`) goes in `.env`; **credentials** (four passwords, plus the FTP one
for the bonus) are secrets. `.env` is committed because it contains no
credential; `secrets/*.txt` is git-ignored and generated on the machine.

### Docker network vs host network

`network_mode: host` removes network namespacing: the container binds directly
on the host's interfaces. Every listening port is then exposed on the host, and
containers can no longer be addressed by name — which is precisely why the
subject forbids it.

The user-defined bridge network `inception` gives each container its own network
namespace and an embedded DNS server, so `wordpress` reaches the database by
connecting to the name `mariadb`. Only what is explicitly published in `ports:`
is reachable from outside — here, 443 on nginx (and 21 + the passive range on
the bonus FTP container). MariaDB listens on `0.0.0.0:3306`, and that port is
still unreachable from the host, because it exists only inside the network
namespace. `links:` is the deprecated ancestor of this mechanism and is
forbidden too.

### Docker volumes vs bind mounts

A bind mount attaches an arbitrary host path into a container. It depends on the
host's directory layout, ownership and SELinux/AppArmor labels, and Docker
neither creates nor manages it — a typo in the path silently gives you an empty
directory.

A named volume is a first-class Docker object: created on demand, listed by
`docker volume ls`, removed by `docker volume rm`, and — the property this
project depends on — **populated from the image the first time it is mounted**.

The subject asks for named volumes whose data nevertheless lives in
`/home/chimex/data`. Both requirements are satisfied by giving the *volume* a
bind-type local driver:

```yaml
volumes:
  wordpress_files:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/chimex/data/wordpress
```

`inception_wordpress_files` is a real named volume — services refer to it by
name, not by path, and no service declares a host path — while its contents are
inspectable on the host.

That "populated from the image" behaviour caused the one genuinely instructive
bug in this project: the Debian `mariadb-server` package runs `mysql_install_db`
at *install* time, so the image already contained a `/var/lib/mysql`. Docker
copied it into the fresh volume, the entrypoint's "is the data directory empty?"
test was never true, and the database was never created. The fix is one line in
the Dockerfile — `rm -rf /var/lib/mysql/*` — so that a new volume really starts
cold.

## Resources

Documentation and references used:

- [Docker documentation](https://docs.docker.com/) — Dockerfile reference, build
  best practices, `docker compose` file reference, secrets, volumes, networking
- [Dockerfile best practices](https://docs.docker.com/build/building/best-practices/)
  and the [PID 1 / signal handling](https://docs.docker.com/engine/containers/multi-service_container/)
  notes — why an entrypoint must `exec`
- [MariaDB knowledge base](https://mariadb.com/kb/en/) — `mariadb-install-db`,
  `--bootstrap` mode, the `mysql.global_priv` table
- [nginx documentation](https://nginx.org/en/docs/) — `ngx_http_ssl_module`
  (`ssl_protocols`), `ngx_http_fastcgi_module`, server name matching
- [php-fpm configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
  — pool directives, running in the foreground with `-F`
- [WP-CLI handbook](https://make.wordpress.org/cli/handbook/) — `core install`,
  `config set`, `user create`, `redis enable`
- [vsftpd.conf(5)](https://security.appspot.com/vsftpd/vsftpd_conf.html) —
  chroot and passive-mode configuration
- [Redis configuration](https://redis.io/docs/latest/operate/oss_and_stack/management/config/)
  — `maxmemory`, `maxmemory-policy`
- [Debian releases](https://www.debian.org/releases/) — to determine which
  release is the *penultimate* stable one
- RFC 8446 (TLS 1.3) and RFC 5246 (TLS 1.2), for what `ssl_protocols` selects

### Use of AI

An AI assistant (Claude) was used on this project for the following, and only
the following:

- **Scaffolding and boilerplate** — first drafts of the Dockerfiles, the compose
  files and the entrypoint scripts, which were then read line by line, corrected
  and reorganised.
- **Debugging assistance** — narrowing down three failures that were reproduced
  and understood before being fixed: `mariadbd --bootstrap` parsing one
  statement per line (a multi-line `CREATE DATABASE` failed silently); the
  Debian `mariadb-server` package shipping a pre-populated `/var/lib/mysql` that
  Docker copied into the "empty" volume; and `vsftpd` refusing to open
  `/dev/stdout` as its log file.
- **Documentation drafting** — first drafts of this README, `USER_DOC.md`,
  `DEV_DOC.md` and `TESTING_ROADMAP.md`.
- **Test-suite drafting** — the checks in `tools/`, each mapped back to a
  specific rule of the subject.

AI was *not* used as a substitute for understanding. Every configuration
directive, every entrypoint line and every design trade-off documented above can
be explained and justified on request — which is the actual point of the
defense.
