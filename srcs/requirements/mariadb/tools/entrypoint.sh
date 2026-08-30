#!/bin/sh
# =============================================================================
#  MariaDB entrypoint
# -----------------------------------------------------------------------------
#  Runs once on a cold volume: creates the system tables, the WordPress
#  database and its user, then hands PID 1 over to mariadbd via `exec`.
#  No daemonising, no `tail -f`, no sleep loop.
# =============================================================================
set -eu

DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
DB_PASSWORD="$(cat /run/secrets/db_password)"

# /run is a fresh tmpfs on every start: the socket directory must be recreated.
mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [ ! -d /var/lib/mysql/mysql ]; then
    echo "[mariadb] empty data directory -> first-time initialisation"

    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null

    # `--bootstrap` executes a batch of SQL and exits. It never opens a socket
    # or a TCP port, so the database is never briefly reachable without a root
    # password, and there is no temporary daemon to start and stop.
    #
    # IMPORTANT: in bootstrap mode MariaDB parses ONE STATEMENT PER LINE.
    # A statement split over two lines is a syntax error, so every statement
    # below is kept on a single line.
    mariadbd --user=mysql --bootstrap <<EOSQL
USE mysql;
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
DELETE FROM mysql.global_priv WHERE User = '';
DROP DATABASE IF EXISTS test;
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL

    # `--bootstrap` can exit 0 even when a statement failed, so the result is
    # verified explicitly: a broken database must fail loudly, now, rather than
    # show up later as an unexplained "connection refused" in WordPress.
    if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
        echo "[mariadb] FATAL: database '${MYSQL_DATABASE}' was not created" >&2
        exit 1
    fi

    echo "[mariadb] initialisation done: database '${MYSQL_DATABASE}', user '${MYSQL_USER}'"
else
    echo "[mariadb] existing data directory found -> skipping initialisation"
fi

echo "[mariadb] starting daemon as PID 1"
exec "$@"
