# =============================================================================
#  BONUS - Adminer, a single-file database administration UI
# =============================================================================
FROM debian:bookworm

# php8.2-cli hosts the app, php8.2-mysql lets Adminer talk to MariaDB.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        php8.2-cli \
        php8.2-mysql \
        curl \
        ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Adminer is one PHP file: fetched from its official release, pinned, never
# pulled as a ready-made Docker image.
ARG ADMINER_VERSION=4.8.1
RUN mkdir -p /var/www/adminer \
 && curl -fsSL -o /var/www/adminer/index.php \
      "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php" \
 && chown -R www-data:www-data /var/www/adminer

WORKDIR /var/www/adminer
EXPOSE 8080
USER www-data

# PHP's built-in server: a single foreground process, PID 1, no daemon and no
# second web server to configure. It is only ever reached through nginx, on the
# internal network, by one administrator at a time.
CMD ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/adminer"]
