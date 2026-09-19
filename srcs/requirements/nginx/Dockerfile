# =============================================================================
#  NGINX - the single entry point of the infrastructure (TLS, port 443 only)
# =============================================================================
FROM debian:bookworm

# nginx         : reverse proxy / FastCGI gateway
# openssl       : generates the self-signed certificate at first start
# gettext-base  : envsubst, to inject DOMAIN_NAME into the vhost templates
#
# Two things are removed straight away:
#   * sites-enabled/default, which would answer on port 80;
#   * /var/www/html/index.nginx-debian.html - that path is a shared named
#     volume and Docker copies image content into an empty volume on first
#     mount, so the placeholder page would land next to the WordPress files.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        nginx \
        openssl \
        gettext-base \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default \
 && rm -rf /var/www/html/*

# Container logs belong on stdout/stderr, not in a file inside the container.
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

# Templates (not final configs): the domain name comes from the environment.
COPY conf/nginx.conf.template       /etc/nginx/templates/default.conf.template
COPY conf/nginx_bonus.conf.template /etc/nginx/templates/bonus.conf.template

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /etc/nginx/ssl

# 443 only: HTTP is never served, so there is nothing to redirect from.
EXPOSE 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
