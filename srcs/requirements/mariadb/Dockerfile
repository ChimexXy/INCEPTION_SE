# =============================================================================
#  MariaDB - the WordPress database
# -----------------------------------------------------------------------------
#  Penultimate stable Debian: Debian 13 "trixie" is the current stable release,
#  so Debian 12 "bookworm" is the penultimate one. The `latest` tag is
#  forbidden by the subject, and a codename tag is reproducible anyway.
# =============================================================================
FROM debian:bookworm

# mariadb-server : the database daemon itself
# mariadb-client : mariadb-admin/mariadb, used by the container healthcheck
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        mariadb-server \
        mariadb-client \
 && rm -rf /var/lib/apt/lists/*

# The Debian package runs mysql_install_db at install time, so the image ships
# a ready-made /var/lib/mysql. Docker copies image content into a fresh volume
# on first mount, which would make the datadir look "already initialised" and
# silently skip our own setup. Emptying it here guarantees that a new volume
# really starts cold - and it makes the image ~120 MB smaller.
RUN rm -rf /var/lib/mysql/* && chown mysql:mysql /var/lib/mysql

# Our settings are loaded LAST (99-) so they override Debian's 50-server.cnf,
# which would otherwise pin bind-address to 127.0.0.1 and make the database
# unreachable from the WordPress container.
COPY conf/99-inception.cnf /etc/mysql/mariadb.conf.d/99-inception.cnf

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3306

# The entrypoint initialises the data directory once, then `exec`s the daemon,
# so mariadbd becomes PID 1 and receives SIGTERM directly from Docker.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["mariadbd", "--user=mysql"]
