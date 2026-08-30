# Developer documentation

How to set this project up from nothing, how it is built, and how to work on it.
End-user topics are in [USER_DOC.md](USER_DOC.md); the verification plan is in
[TESTING_ROADMAP.md](TESTING_ROADMAP.md).

---

## 1. Setting up from scratch

### Prerequisites

| Tool | Why | Check |
|---|---|---|
| Docker Engine ≥ 20.10 | builds and runs the containers | `docker --version` |
| Docker Compose v2 | the `docker compose` sub-command | `docker compose version` |
| GNU make | the entry point of the project | `make --version` |
| openssl | generates the secret values | `openssl version` |
| curl | used by the test suites | `curl --version` |

The user must be able to talk to the Docker daemon without `sudo`:

```bash
sudo usermod -aG docker "$USER"   # then log out and back in
docker ps                         # must work
```

### Repository layout

```
.
├── Makefile                     the only entry point
├── README.md  USER_DOC.md  DEV_DOC.md  TESTING_ROADMAP.md
├── secrets/                     one password per file, git-ignored
│   ├── db_root_password.txt
│   ├── db_password.txt
│   ├── wp_admin_password.txt
│   ├── wp_user_password.txt
│   └── ftp_password.txt         (bonus)
├── subject/en.subject.pdf
├── tools/                       test suites
│   ├── lib.sh
│   ├── test_mandatory.sh
│   └── test_bonus.sh
└── srcs/
    ├── .env                     non-secret configuration
    ├── docker-compose.yml       MANDATORY stack (3 services)
    ├── docker-compose.bonus.yml BONUS overlay (5 more services)
    └── requirements/
        ├── nginx/       Dockerfile  conf/*.template  tools/entrypoint.sh
        ├── wordpress/   Dockerfile  conf/www.conf    tools/entrypoint.sh
        ├── mariadb/     Dockerfile  conf/99-inception.cnf  tools/entrypoint.sh
        └── bonus/
            ├── redis/        Dockerfile  conf/redis.conf
            ├── ftp/          Dockerfile  conf/vsftpd.conf  tools/entrypoint.sh
            ├── adminer/      Dockerfile
            ├── static-site/  Dockerfile  conf/static.conf  site/{index.html,style.css,app.js}
            └── status/       Dockerfile  app/server.py
```

### Configuration files

**`srcs/.env`** — committed, and contains no credential. Compose loads it
automatically because it sits next to the compose file.

| Variable | Used by | Meaning |
|---|---|---|
| `LOGIN`, `DOMAIN_NAME`, `DATA_PATH` | Makefile, nginx, compose | identity, vhost name, where the volumes live |
| `MYSQL_HOST`, `MYSQL_DATABASE`, `MYSQL_USER` | mariadb, wordpress | database coordinates |
| `WP_URL`, `WP_TITLE`, `WP_ADMIN_USER`, `WP_ADMIN_EMAIL`, `WP_USER`, `WP_USER_EMAIL` | wordpress | what WP-CLI installs |
| `REDIS_HOST`, `REDIS_PORT` | wordpress, redis | **bonus only** — injected by the overlay |
| `FTP_USER`, `FTP_PASV_MIN`, `FTP_PASV_MAX` | ftp | **bonus only** |

To move the project to another login, change `LOGIN`, `DOMAIN_NAME`,
`DATA_PATH`, `WP_URL` and the e-mail addresses, then `make re`.

**`secrets/*.txt`** — git-ignored, one password per file, no trailing newline
issues (each is a single line). `make secrets` creates any that is missing with
`openssl rand -base64 24`; existing files are never overwritten. To supply your
own value, just write the file before the first `make`.

Compose declares them as secrets, so each is mounted read-only at
`/run/secrets/<name>` inside the containers that need it — and nowhere else.

---

## 2. Building and launching

```bash
make              # setup + build + start the MANDATORY stack
make bonus        # setup + build + start mandatory + bonus
make build        # build the mandatory images without starting them
make build-bonus  # build every image
```

`make` first runs `setup`, which is three idempotent steps:

| Target | Effect |
|---|---|
| `dirs` | `mkdir -p /home/chimex/data/{wordpress,mariadb}` — the bind-backed volumes need these paths to exist |
| `secrets` | generates any missing `secrets/*.txt` |
| `hosts` | adds `chimex.42.fr` and the bonus sub-domains to `/etc/hosts` (asks for `sudo`) |

Underneath, the Makefile is a thin wrapper:

```bash
# mandatory
docker compose -f srcs/docker-compose.yml up -d --build

# mandatory + bonus
docker compose -f srcs/docker-compose.yml -f srcs/docker-compose.bonus.yml up -d --build
```

### How the overlay works

`docker-compose.bonus.yml` is never used alone. Compose merges the two files in
order, and the overlay only *adds*:

- five new services, each with its own Dockerfile under `requirements/bonus/`;
- `ENABLE_BONUS=1` on nginx → its entrypoint renders `bonus.conf.template` into
  `conf.d/`, publishing the `static.`, `adminer.` and `status.` vhosts;
- `REDIS_HOST` / `REDIS_PORT` on wordpress → its entrypoint installs and enables
  the Redis Object Cache plugin.

Both switches are read with `${VAR:-default}` in the entrypoints, so on a
mandatory-only run they are simply absent and the code path never executes.
`docker compose -f srcs/docker-compose.yml config --services` must always print
exactly three services — the first check of the bonus test suite.

### What happens on first start

```
mariadb    volume empty? → mariadb-install-db → mariadbd --bootstrap (create db + user)
           → exec mariadbd                                       [healthcheck: mariadb-admin ping]
wordpress  wait for mariadb (bounded, 60 s) → wp core download → wp config create
           → wp core install → wp user create → [bonus: wp plugin install redis-cache]
           → exec php-fpm8.2 -F
nginx      envsubst the vhost templates → generate a self-signed cert if missing
           → nginx -t → exec nginx -g "daemon off;"
```

Every step is guarded, so a restart re-runs none of it.

---

## 3. Day-to-day commands

### Containers

```bash
make ps                                         # status of every container
make logs                                       # follow all logs
docker logs -f wordpress                        # one container
docker exec -it wordpress bash                  # a shell inside a container
docker compose -f srcs/docker-compose.yml restart nginx
docker compose -f srcs/docker-compose.yml up -d --build --force-recreate nginx
```

### Rebuilding after a change

| You changed | Do this |
|---|---|
| a `conf/` file or an entrypoint | `docker compose ... up -d --build <service>` |
| a `Dockerfile` | same — the layer cache handles the rest |
| `srcs/.env` | `docker compose ... up -d --force-recreate` (env is read at container creation) |
| a compose file | `docker compose ... up -d` |
| something in the WordPress install logic | `make fclean && make` — the install only runs on an empty volume |

### WordPress (WP-CLI is installed in the image)

```bash
wp() { docker exec wordpress /usr/local/bin/wp --allow-root --path=/var/www/html "$@"; }

wp user list
wp plugin list
wp option get siteurl
wp db check
wp redis status          # bonus
```

### Database

```bash
docker exec -it mariadb sh -c \
  'mariadb -u root -p"$(cat /run/secrets/db_root_password)" wordpress'

# dump / restore
docker exec mariadb sh -c \
  'mariadb-dump -u root -p"$(cat /run/secrets/db_root_password)" wordpress' > backup.sql
docker exec -i mariadb sh -c \
  'mariadb -u root -p"$(cat /run/secrets/db_root_password)" wordpress' < backup.sql
```

`root` is deliberately reachable only through the unix socket, never over TCP —
which is why these commands run *inside* the container.

### Volumes

```bash
docker volume ls --filter name=inception
docker volume inspect inception_wordpress_files
ls -la /home/chimex/data/wordpress
```

### Cleaning

| Command | Containers | Images | Volumes | Host data |
|---|---|---|---|---|
| `make down` | removed | kept | kept | kept |
| `make clean` | removed | removed | kept | kept |
| `make fclean` | removed | removed | removed | **deleted** |
| `make re` | `fclean`, then a full rebuild | | | |

`fclean` deletes the volume contents from inside a throwaway root container
(`docker run --rm -v /home/chimex/data:/data debian:bookworm rm -rf ...`),
because those files belong to the `mysql` and `www-data` users. That keeps the
Makefile free of `sudo`.

---

## 4. Where the data lives, and how it persists

Two named volumes, both backed by a directory under `/home/chimex/data`:

| Volume | Mounted at | On the host | Holds |
|---|---|---|---|
| `inception_wordpress_files` | `/var/www/html` in nginx, wordpress and ftp | `/home/chimex/data/wordpress` | WordPress core, `wp-config.php`, themes, plugins, uploads |
| `inception_mariadb_data` | `/var/lib/mysql` in mariadb | `/home/chimex/data/mariadb` | the databases, InnoDB tablespaces, logs |

They are declared like this:

```yaml
volumes:
  wordpress_files:
    driver: local
    driver_opts: { type: none, o: bind, device: /home/chimex/data/wordpress }
```

This is a **named volume** — services refer to it by name and no service
declares a host path — whose storage happens to be a known directory, which is
what the subject asks for. `docker volume ls` lists it; `docker volume rm`
removes it.

Redis has no volume at all: it is a cache, persistence is disabled
(`save ""`, `appendonly no`), and losing it costs one slow page load.

### What survives what

| Action | WordPress files | Database |
|---|---|---|
| `docker restart <container>` | kept | kept |
| `make down` then `make` | kept | kept |
| `docker compose down -v` | **deleted** | **deleted** |
| `make fclean` | **deleted** | **deleted** |
| deleting `/home/chimex/data/*` | **deleted** | **deleted** |

Because the entrypoints are idempotent, a stack brought back up on existing
volumes reuses them untouched: MariaDB finds its data directory and skips
initialisation, WordPress finds `wp-config.php` and skips the install.

### Two Docker behaviours worth knowing

1. **A fresh volume is seeded from the image.** The first time an empty volume
   is mounted, Docker copies whatever the image has at that path into it. The
   Debian `mariadb-server` package ships a pre-built `/var/lib/mysql`, and the
   `nginx` package ships `/var/www/html/index.nginx-debian.html`. Both are
   deleted in their Dockerfiles, otherwise a "new" volume would arrive
   pre-populated — which silently defeats every "is this the first run?" test.

2. **`mariadbd --bootstrap` parses one statement per line.** A statement wrapped
   across two lines is a syntax error, and the batch stops there while still
   exiting 0. The init SQL is therefore written one statement per line, and the
   entrypoint verifies afterwards that the database directory exists rather than
   trusting the exit code.

---

## 5. Conventions to keep

- Every entrypoint ends in `exec "$@"`; the daemon is PID 1.
- Every image is built `FROM debian:bookworm`; no `latest` tag anywhere.
- Passwords are read from `/run/secrets/`, never passed as environment variables
  and never written in a Dockerfile.
- The mandatory compose file stays at exactly three services.
- A new bonus service means: a directory under `srcs/requirements/bonus/`, a
  service block in `docker-compose.bonus.yml`, a vhost in
  `nginx/conf/bonus.conf.template` if it is a web UI, an entry in the `CHECKS`
  list of `status/app/server.py`, and a section in `tools/test_bonus.sh`.
