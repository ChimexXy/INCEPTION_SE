# Testing roadmap

How this project is verified: what is checked, in which order, why each check
exists, and what to do when one fails.

Two suites implement it:

```bash
make test         # mandatory  → tools/test_mandatory.sh   (M1 … M12)
make test-bonus   # bonus      → tools/test_bonus.sh       (B1 … B8)
```

Both print one line per check and end with a summary. A run is good when it says
`0 failed`. Checks that the *client machine* cannot perform (see M8) report
`SKIP`, never `PASS` — a skipped check is an unanswered question, not a success.

---

## Phase 0 — Before anything runs

Do this once on a new machine. It costs a minute and removes most of the
"nothing works" cases.

| # | Check | Command | Expected |
|---|---|---|---|
| 0.1 | Docker is usable without `sudo` | `docker ps` | a table, not a permission error |
| 0.2 | Compose v2 is installed | `docker compose version` | `v2.x` |
| 0.3 | Port 443 is free | `ss -lntp \| grep :443` | nothing, or only our nginx |
| 0.4 | The domain resolves | `getent hosts chimex.42.fr` | `127.0.0.1` |
| 0.5 | Both compose files parse | `docker compose -f srcs/docker-compose.yml config -q` | silence |

> On this machine a host `lighttpd` occupies port **80**. That is harmless: the
> project publishes 443 only, and never 80.

---

## Phase 1 — Mandatory: static checks (no container needed)

These read the repository. They can run before the first build, and they are the
checks a corrector performs by eye.

### M1 · Repository layout
Every file the subject names is where it says. `Makefile` at the root, `srcs/`
holding the compose file and `.env`, one `Dockerfile` per service, and the four
documents (`README.md`, `USER_DOC.md`, `DEV_DOC.md`, and this file).
**Also asserts the mandatory compose file declares exactly 3 services** — the
first line of defence for the mandatory/bonus separation.

### M2 · Image rules
- no `:latest` tag anywhere — it makes a build unreproducible;
- every `FROM` is `debian:` or `alpine:` — nothing pre-built is pulled;
- each image is named after its service (`nginx:inception`, …).

### M3 · Forbidden patterns
`tail -f`, `sleep infinity`, `while true`, a bare `bash`/`sh` as a container
command, `network_mode: host`, `links:` — and a `networks:` section must be
present.

> These greps strip full-line comments first. Without that, a comment saying
> *"no `tail -f` here"* fails its own check — which is exactly what happened the
> first time this suite was run.

### M4 · Credentials hygiene
No password literal in any Dockerfile, in the compose file or in `.env`;
`secrets/*.txt` is git-ignored and no secret file is tracked by git; the compose
file really declares a `secrets:` section. The subject makes a credential in the
repository an outright failure, so this phase is not optional.

---

## Phase 2 — Mandatory: runtime checks

Run after `make`.

### M5 · Containers are running
The three containers are `running`, and every one has `restart: always` — the
subject's "your containers have to restart in case of a crash".

### M6 · PID 1 is the real daemon
Reads `/proc/1/cmdline` in each container. It must be `nginx`, `php-fpm` and
`mariadbd` — not a shell, not a wrapper.

*Why it matters:* if PID 1 is a shell, `SIGTERM` never reaches the database and
`docker compose down` kills it after a timeout, which is how an InnoDB data
directory gets corrupted. This is the check behind the subject's whole "read
about PID 1" paragraph, and the one an evaluator is most likely to ask about.

### M7 · Network exposure
- nginx publishes 443 — and the test asserts wordpress and mariadb publish
  **nothing**;
- connecting to `127.0.0.1:3306` from the host must fail;
- the `inception` network exists and is a `bridge`.

### M8 · TLS
TLSv1.2 and TLSv1.3 must be accepted; TLSv1.0 and TLSv1.1 must be refused.

A handshake is judged on whether it produced a cipher — `Cipher is (NONE)` means
refused. Judging on the `Protocol:` line is wrong: OpenSSL prints a value there
even for a failed handshake, which made this check pass for the wrong reason
during development.

Modern OpenSSL 3 will not even *offer* TLS 1.0/1.1 (`no protocols available`).
That is a client limitation, so the suite reports `SKIP` and instead asserts the
server configuration directly: `ssl_protocols TLSv1.2 TLSv1.3;` is present in
the rendered vhost inside the container, and nothing older is configured. To
test it for real from outside, use a client that can still offer them:

```bash
docker run --rm -it --network inception alpine/openssl \
    s_client -connect nginx:443 -tls1_1     # must fail to handshake
```

The certificate's CN must be the project domain.

### M9 · The website answers
`https://chimex.42.fr/` returns 200 and carries the site title; `wp-login.php`
returns 200; the page contains `wp-content`, which proves PHP was **executed**
and not served as text; and `wp-config.php` is not downloadable.

### M10 · WordPress users
Exactly two users; one is an administrator; the administrator login contains
neither `admin` nor `administrator` in any case.

### M11 · Volumes
Both volumes exist, use the `local` driver, and resolve to
`/home/chimex/data/{wordpress,mariadb}`. `wp-config.php` and the `wordpress`
database directory are visible on the host. No service declares a bind mount.

### M12 · Database
WordPress passes `wp db check`; the `wordpress` database exists; and `root`
cannot log in over TCP — it is reachable through the unix socket only.

---

## Phase 3 — Persistence (run by hand)

The suites do not do this: it restarts containers, so it belongs in a deliberate
run before a defense.

```bash
# 1. leave a trace
docker exec wordpress wp --allow-root --path=/var/www/html \
    post create --post_title='persistence probe' --post_status=publish

# 2. destroy the containers, keep the volumes
make down && make

# 3. it must still be there
docker exec wordpress wp --allow-root --path=/var/www/html \
    post list --field=post_title | grep 'persistence probe'
```

### Crash recovery

The subject requires containers to come back after a crash. Simulating one
correctly is less obvious than it looks:

```bash
# WRONG - `docker kill` is a *user* action. Docker (verified on 29.6.1) does not
# apply the restart policy to it, so the container simply stays exited.
docker kill mariadb

# WRONG - PID 1 is immune to signals it has no handler for when they come from
# inside its own PID namespace. This does nothing at all.
docker exec mariadb sh -c 'kill -9 1'

# RIGHT - kill the process from the host's PID namespace, which is what an
# actual crash looks like to the daemon.
sudo kill -9 "$(docker inspect -f '{{.State.Pid}}' mariadb)"
docker inspect -f '{{.State.Status}} restarts={{.RestartCount}}' mariadb
```

After the third form the container comes back on its own and `RestartCount`
increases. `make test` cannot do this — it needs `sudo` — so M5 asserts the
policy is `always` and this rehearsal proves it works.

---

## Phase 4 — Bonus

Run after `make bonus`.

| # | Section | What it proves |
|---|---|---|
| **B1** | Separation | the mandatory compose file still declares exactly 3 services; the overlay brings it to 8; each bonus service has its own Dockerfile under `requirements/bonus/`; no bonus service leaks into the mandatory file |
| **B2** | Containers | the five bonus containers run, restart on crash, and PID 1 is `redis-server`, `vsftpd`, `php`, `nginx`, `python3` |
| **B3** | Redis | `PING` → `PONG`; WordPress reports `Status: Connected` and a valid drop-in; `DBSIZE` > 0 after a page load; `maxmemory-policy` is `allkeys-lru` and `maxmemory` is not 0 — "properly manage the cache" means bounded and evicting; redis owns no volume |
| **B4** | FTP | login lists the website; a file uploaded over FTP appears in the volume **and is served by nginx immediately**; the account is chrooted on `/var/www/html` |
| **B5** | Adminer | reachable through nginx on its sub-domain, and publishes no port of its own |
| **B6** | Static site | reachable; contains no `.php` file; the image has no PHP runtime at all — the subject excludes PHP for this one |
| **B7** | Status | the dashboard renders; `/health` reports `"healthy": true`; all seven services are probed and none is down |
| **B8** | Entry points | nginx still publishes only 443; FTP is the only service with extra published ports; redis, adminer, static-site and status publish nothing |

B1 is the check that matters most for grading: **the bonus is only assessed if
the mandatory part is perfect**, so the mandatory stack must remain runnable and
correct on its own.

---

## Phase 5 — Defense rehearsal

Checks a machine cannot make. Be ready to *show*, not just assert.

| Question | Where the answer is |
|---|---|
| Why Debian bookworm and not trixie? | trixie is the current stable, bookworm is the penultimate one — the subject asks for the penultimate |
| What is PID 1 here, and why does it matter? | M6, and the `exec "$@"` at the end of every entrypoint |
| Show me a container without an infinite loop | `docker exec mariadb cat /proc/1/cmdline` |
| Where are the passwords? | `secrets/`, git-ignored, mounted at `/run/secrets/`; `docker inspect wordpress` shows none |
| Prove the volume is a named volume | `docker volume inspect inception_wordpress_files`; no service declares a host path |
| Why is `bind-address` 0.0.0.0 if the DB must not be exposed? | it binds inside the container's own network namespace; the port is never published — M7 proves it from the host |
| Show TLS 1.1 being refused | the `docker run alpine/openssl` command in M8 |
| Why a sub-domain for Adminer instead of a port? | to keep 443 the only entry point; FTP needs a port because it cannot be proxied |
| Justify the free-choice service | `docker ps` says *running*; the status dashboard says *answering*. See the header of `requirements/bonus/status/Dockerfile` |

Expect a small live modification (the subject warns about it). Rehearse:
change `WP_TITLE` in `.env` → `make down && make` → the new title appears; add a
`location` to the nginx vhost → rebuild nginx only; add a sixth check to
`status/app/server.py`.

---

## Troubleshooting map

| Failing check | Most likely cause | First command |
|---|---|---|
| M5 — a container is not running | it crashes at start | `docker logs <name>` |
| M6 — PID 1 is a shell | the entrypoint does not end in `exec` | read `tools/entrypoint.sh` |
| M8 — TLS 1.2 refused | nginx did not reload the rendered vhost | `docker exec nginx nginx -t` |
| M9 — 502 Bad Gateway | php-fpm is not listening on 9000 | `docker logs wordpress` |
| M9 — 403 Forbidden | the volume is empty — the WordPress install never ran | `docker logs wordpress`, then `make fclean && make` |
| M10 — 0 users | the database was created but the install failed | `docker logs mariadb \| grep FATAL` |
| M11 — the volume points elsewhere | `DATA_PATH` changed without a `fclean` | `make fclean && make` |
| M12 — `wp db check` fails | wrong password in `wp-config.php` after a secret changed | `make fclean && make` |
| B3 — `DBSIZE` is 0 | the object cache drop-in is missing | `docker exec wordpress wp --allow-root --path=/var/www/html redis enable` |
| B4 — upload refused | the FTP user cannot write the volume | it must share `www-data`'s uid — see the ftp entrypoint |
| B7 — a service is down | that service is genuinely failing | open `/health` and read the `detail` field |

### Three failures found while building this, kept as regression notes

1. **The database was never created.** `mariadbd --bootstrap` parses **one
   statement per line**; a `CREATE DATABASE` wrapped over two lines was a syntax
   error, the batch stopped, and bootstrap still exited 0. The init SQL is now
   one statement per line, and the entrypoint verifies the database directory
   exists instead of trusting the exit code.

2. **The initialisation never ran at all.** The Debian `mariadb-server` package
   runs `mysql_install_db` at *install* time, so the image shipped a populated
   `/var/lib/mysql`; Docker copies image content into a fresh volume, so the
   "is the data directory empty?" guard was never true. The Dockerfile now
   empties it. The `nginx` package had the same problem with
   `/var/www/html/index.nginx-debian.html`.

3. **The status dashboard returned 502.** Its HTML template used
   `%`-formatting while its CSS contains `width:100%`. `/health` worked, `/`
   crashed — which is why the suite checks both.
