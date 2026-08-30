#!/usr/bin/env bash
# =============================================================================
#  Inception - BONUS test suite
#  Assumes `make bonus` is up. See TESTING_ROADMAP.md.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SRCS="$ROOT/srcs"
BONUS_SERVICES="redis ftp adminer static-site status"

printf "${B}=====================================================${N}\n"
printf "  Inception - BONUS checks (%s)\n" "$DOMAIN"
printf "${B}=====================================================${N}\n"

# -----------------------------------------------------------------------------
section "B1  Mandatory / bonus separation"
eq  "the mandatory compose file still declares 3 services" "3" \
    "$($COMPOSE config --services 2>/dev/null | wc -l | tr -d ' ')"
eq  "the bonus overlay brings the total to 8" "8" \
    "$($COMPOSE_BONUS config --services 2>/dev/null | wc -l | tr -d ' ')"
for s in $BONUS_SERVICES; do
    ok "'$s' has its own Dockerfile under requirements/bonus/" \
       test -f "$SRCS/requirements/bonus/$s/Dockerfile"
done
no  "no bonus service leaks into the mandatory compose file" \
    bash -c "grep -qE '^  (redis|ftp|adminer|static-site|status):' '$SRCS/docker-compose.yml'"
ok  "the bonus overlay is a separate file" test -f "$SRCS/docker-compose.bonus.yml"

# -----------------------------------------------------------------------------
section "B2  Bonus containers"
for s in $BONUS_SERVICES; do
    eq "'$s' is running" "running" "$(docker inspect -f '{{.State.Status}}' "$s" 2>/dev/null)"
done
for s in $BONUS_SERVICES; do
    eq "'$s' restarts on crash" "always" \
       "$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$s" 2>/dev/null)"
done
section "B2b PID 1 of each bonus container"
pid1() { docker exec "$1" cat /proc/1/cmdline 2>/dev/null | tr '\0' ' '; }
has "PID 1 of 'redis' is redis-server"   "redis-server" "$(pid1 redis)"
has "PID 1 of 'ftp' is vsftpd"           "vsftpd"       "$(pid1 ftp)"
has "PID 1 of 'adminer' is php"          "php"          "$(pid1 adminer)"
has "PID 1 of 'static-site' is nginx"    "nginx"        "$(pid1 static-site)"
has "PID 1 of 'status' is python3"       "python3"      "$(pid1 status)"

# -----------------------------------------------------------------------------
section "B3  Redis object cache"
has "redis answers PING"        "PONG"  "$(docker exec redis redis-cli PING 2>/dev/null)"
has "WordPress is connected to redis" "Status: Connected" \
    "$(docker exec wordpress wp --allow-root --path=/var/www/html redis status 2>/dev/null)"
has "the object-cache drop-in is valid" "Drop-in: Valid" \
    "$(docker exec wordpress wp --allow-root --path=/var/www/html redis status 2>/dev/null)"
# Hit the site so the cache is certainly warm, then count the keys.
https_code "$DOMAIN" / >/dev/null
KEYS="$(docker exec redis redis-cli DBSIZE 2>/dev/null | tr -dc '0-9')"
ok  "the cache actually holds keys (DBSIZE=$KEYS)" test "${KEYS:-0}" -gt 0
has "an eviction policy is set"  "allkeys-lru" \
    "$(docker exec redis redis-cli CONFIG GET maxmemory-policy 2>/dev/null)"
no  "the cache is not bounded by nothing" \
    bash -c "docker exec redis redis-cli CONFIG GET maxmemory 2>/dev/null | grep -qx 0"
eq  "redis has no volume of its own (a cache is disposable)" "0" \
    "$(docker inspect -f '{{len .Mounts}}' redis 2>/dev/null)"

# -----------------------------------------------------------------------------
section "B4  FTP server on the WordPress volume"
FTP_PW="$(cat "$ROOT/secrets/ftp_password.txt" 2>/dev/null)"
FTP_USER="$(env_get FTP_USER)"
LIST="$(curl -s -m 10 --ftp-pasv "ftp://127.0.0.1:21/" -u "$FTP_USER:$FTP_PW" 2>/dev/null)"
has "FTP login succeeds and lists the website" "wp-config.php" "$LIST"

PROBE="inception-ftp-probe-$$.txt"
STAMP="ftp-probe-$(date +%s)"
echo "$STAMP" > "/tmp/$PROBE"
if curl -s -m 10 --ftp-pasv -T "/tmp/$PROBE" "ftp://127.0.0.1:21/" -u "$FTP_USER:$FTP_PW" >/dev/null 2>&1; then
    ok  "an uploaded file lands in the WordPress volume" \
        docker exec wordpress test -f "/var/www/html/$PROBE"
    has "and nginx serves it straight away" "$STAMP" "$(https_body "$DOMAIN" "/$PROBE")"
    docker exec wordpress rm -f "/var/www/html/$PROBE" >/dev/null 2>&1
else
    skip "an uploaded file lands in the WordPress volume" "FTP upload failed"
    skip "and nginx serves it straight away" "FTP upload failed"
fi
rm -f "/tmp/$PROBE"
eq  "the FTP user is chrooted on /var/www/html" "/var/www/html" \
    "$(docker exec ftp sh -c "getent passwd $FTP_USER | cut -d: -f6" 2>/dev/null)"

# -----------------------------------------------------------------------------
section "B5  Adminer"
eq  "https://adminer.$DOMAIN/ returns 200" "200" "$(https_code "adminer.$DOMAIN" /)"
has "it is the Adminer login page" "Adminer" "$(https_body "adminer.$DOMAIN" /)"
eq  "adminer publishes no port of its own" "" \
    "$(docker inspect -f '{{range $p,$c := .NetworkSettings.Ports}}{{if $c}}{{$p}} {{end}}{{end}}' adminer 2>/dev/null)"

# -----------------------------------------------------------------------------
section "B6  Static site (no PHP)"
eq  "https://static.$DOMAIN/ returns 200" "200" "$(https_code "static.$DOMAIN" /)"
has "it serves the showcase page" "Inception" "$(https_body "static.$DOMAIN" /)"
no  "the static site contains no PHP file" \
    bash -c "ls '$SRCS/requirements/bonus/static-site/site' | grep -q '\.php$'"
no  "the static site image has no PHP runtime" \
    docker exec static-site sh -c "command -v php"

# -----------------------------------------------------------------------------
section "B7  Status dashboard (service of my choice)"
eq  "https://status.$DOMAIN/ returns 200" "200" "$(https_code "status.$DOMAIN" /)"
has "the dashboard renders the service table" "Inception &middot; status" "$(https_body "status.$DOMAIN" /)"
HEALTH="$(https_body "status.$DOMAIN" /health)"
has "the JSON endpoint reports healthy" '"healthy": true' "$HEALTH"
for s in nginx wordpress mariadb redis ftp adminer static-site; do
    has "  $s is probed and up" "\"service\": \"$s\"" "$HEALTH"
done
DOWN="$(printf '%s' "$HEALTH" | grep -c '"ok": false')"
eq  "no service is reported down" "0" "$DOWN"

# -----------------------------------------------------------------------------
section "B8  Entry points"
eq  "nginx is still the only HTTPS entry point" "443" \
    "$(docker inspect -f '{{range $p,$c := .NetworkSettings.Ports}}{{if $c}}{{$p}}{{end}}{{end}}' nginx | grep -o '^443')"
ok  "only FTP publishes extra ports (allowed for the bonus)" \
    bash -c "docker inspect -f '{{range \$p,\$c := .NetworkSettings.Ports}}{{if \$c}}{{\$p}} {{end}}{{end}}' ftp | grep -q '21/tcp'"
for s in redis adminer static-site status; do
    eq "'$s' publishes nothing to the host" "" \
       "$(docker inspect -f '{{range $p,$c := .NetworkSettings.Ports}}{{if $c}}{{$p}} {{end}}{{end}}' "$s" 2>/dev/null)"
done

summary
