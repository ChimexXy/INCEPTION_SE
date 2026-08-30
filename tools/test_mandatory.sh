#!/usr/bin/env bash
# =============================================================================
#  Inception - MANDATORY test suite
#  Every check maps to a rule of the subject. See TESTING_ROADMAP.md.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SRCS="$ROOT/srcs"
CORE="nginx wordpress mariadb"

printf "${B}=====================================================${N}\n"
printf "  Inception - MANDATORY checks (%s)\n" "$DOMAIN"
printf "${B}=====================================================${N}\n"

# -----------------------------------------------------------------------------
section "M1  Repository layout"
ok  "Makefile at the repository root"            test -f "$ROOT/Makefile"
ok  "srcs/docker-compose.yml exists"             test -f "$SRCS/docker-compose.yml"
ok  "srcs/.env exists"                           test -f "$SRCS/.env"
ok  "README.md exists"                           test -f "$ROOT/README.md"
ok  "USER_DOC.md exists"                         test -f "$ROOT/USER_DOC.md"
ok  "DEV_DOC.md exists"                          test -f "$ROOT/DEV_DOC.md"
for s in $CORE; do
    ok "one Dockerfile for '$s'"                 test -f "$SRCS/requirements/$s/Dockerfile"
done
eq  "mandatory compose declares 3 services" "3" \
    "$($COMPOSE config --services 2>/dev/null | wc -l | tr -d ' ')"

# -----------------------------------------------------------------------------
section "M2  Image rules"
no  "no ':latest' tag anywhere"                  grep -rn ":latest" "$SRCS" --include=Dockerfile --include=*.yml
ok  "every base image is debian or alpine"       bash -c \
    'grep -rhn "^FROM" '"$SRCS"'/requirements/*/Dockerfile | grep -qv -E "debian:|alpine:" && exit 1 || exit 0'
for s in $CORE; do
    eq "image name matches service '$s'" "$s:inception" \
       "$($COMPOSE config --format json 2>/dev/null | tr ',' '\n' | grep -o "\"$s:inception\"" | head -1 | tr -d '"')"
done

# -----------------------------------------------------------------------------
section "M3  Forbidden patterns"
# Only what Docker actually executes is searched: full-line comments are
# stripped first, otherwise a comment that merely *names* a forbidden pattern
# ("no tail -f here") would fail its own check.
CODE="$(find "$SRCS" -type f \( -name Dockerfile -o -name '*.sh' -o -name '*.yml' \
        -o -name '*.conf' -o -name '*.cnf' -o -name '*.template' \) -print0 \
        | xargs -0 grep -hv -E '^[[:space:]]*#')"
code_has() { printf '%s\n' "$CODE" | grep -qE "$1"; }

no  "no 'tail -f' keep-alive"                    code_has 'tail +-f'
no  "no 'sleep infinity'"                        code_has 'sleep +infinity'
no  "no 'while true' loop"                       code_has 'while +true'
no  "no bare 'bash'/'sh' as a container command" code_has '^(CMD|ENTRYPOINT) +\[?"?(/bin/)?(ba)?sh"?\]?$'
no  "no 'network_mode: host'"                    code_has 'network_mode: *.?host'
no  "no 'links:'"                                code_has '^[[:space:]]*links:'
ok  "a 'networks:' section is declared"          grep -q "^networks:"      "$SRCS/docker-compose.yml"

# -----------------------------------------------------------------------------
section "M4  Credentials hygiene"
no  "no password literal in any Dockerfile"      grep -rniE "password\s*=\s*[\"'][^\"'\$]" "$SRCS"/requirements/*/Dockerfile
no  "no password value in docker-compose.yml"    grep -rniE "(PASSWORD|PASSWD)=[^\$\s]" "$SRCS/docker-compose.yml"
no  "no password value in .env"                  grep -qiE "^[A-Z_]*PASS(WORD)?=" "$SRCS/.env"
ok  "secrets/*.txt are git-ignored"              bash -c "grep -q 'secrets/\*.txt' '$ROOT/.gitignore'"
ok  "no secret file is tracked by git"           bash -c \
    "cd '$ROOT' && ! git ls-files --error-unmatch secrets/db_password.txt >/dev/null 2>&1"
ok  "docker-compose declares docker secrets"     grep -q "^secrets:" "$SRCS/docker-compose.yml"

# -----------------------------------------------------------------------------
section "M5  Containers are running"
for s in $CORE; do
    eq "'$s' is running" "running" "$(docker inspect -f '{{.State.Status}}' "$s" 2>/dev/null)"
done
for s in $CORE; do
    eq "'$s' restarts on crash" "always" \
       "$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$s" 2>/dev/null)"
done

# -----------------------------------------------------------------------------
section "M6  PID 1 is the real daemon (no hacky keep-alive)"
check_pid1() {
    local c="$1" want="$2"
    local cmd; cmd="$(docker exec "$c" cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ')"
    has "PID 1 of '$c' is $want" "$want" "$cmd"
}
check_pid1 nginx     "nginx"
check_pid1 wordpress "php-fpm"
check_pid1 mariadb   "mariadbd"

# -----------------------------------------------------------------------------
section "M7  Network exposure - 443 and nothing else"
eq  "nginx publishes 443"          "443"  "$(docker inspect -f '{{range $p,$c := .NetworkSettings.Ports}}{{if $c}}{{$p}}{{end}}{{end}}' nginx | grep -o '^443')"
eq  "wordpress publishes nothing"  ""     "$(docker inspect -f '{{range $p,$c := .NetworkSettings.Ports}}{{if $c}}{{$p}} {{end}}{{end}}' wordpress)"
eq  "mariadb publishes nothing"    ""     "$(docker inspect -f '{{range $p,$c := .NetworkSettings.Ports}}{{if $c}}{{$p}} {{end}}{{end}}' mariadb)"
no  "MariaDB is unreachable from the host"  bash -c "timeout 3 bash -c '</dev/tcp/127.0.0.1/3306'"
eq  "'inception' network is a bridge" "bridge" "$(docker network inspect inception --format '{{.Driver}}' 2>/dev/null)"

# -----------------------------------------------------------------------------
section "M8  TLS - only TLSv1.2 and TLSv1.3"
# A handshake either produced a cipher or it did not. Judging on the "Protocol:"
# line is wrong: openssl prints a default there even when the handshake failed.
# Modern OpenSSL 3 also refuses to *offer* TLS 1.0/1.1 at all, which is a client
# limitation, not a server answer - that case is reported as a skip, never as a
# pass, and the server configuration is asserted directly instead.
tls_state() {
    local out
    out="$(echo | timeout 5 openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" "-$1" 2>&1)"
    if grep -q "no protocols available" <<< "$out"; then echo "client-cannot-offer"
    elif grep -q "Cipher is (NONE)"     <<< "$out"; then echo "refused"
    elif grep -q "Cipher is "           <<< "$out"; then echo "accepted"
    else echo "refused"; fi
}
for v in tls1:TLSv1.0 tls1_1:TLSv1.1; do
    flag="${v%%:*}"; label="${v##*:}"
    state="$(tls_state "$flag")"
    if [ "$state" = "client-cannot-offer" ]; then
        skip "$label is refused" "local openssl will not offer $label"
    else
        eq "$label is refused" "refused" "$state"
    fi
done
eq  "TLSv1.2 is accepted" "accepted" "$(tls_state tls1_2)"
eq  "TLSv1.3 is accepted" "accepted" "$(tls_state tls1_3)"
# Deterministic evidence, independent of the client's own capabilities.
has "nginx is configured for TLSv1.2/1.3 only" "ssl_protocols       TLSv1.2 TLSv1.3;" \
    "$(docker exec nginx cat /etc/nginx/conf.d/default.conf 2>/dev/null)"
no  "no protocol older than TLSv1.2 is configured" \
    bash -c "docker exec nginx cat /etc/nginx/conf.d/default.conf 2>/dev/null | grep -E 'ssl_protocols.*(SSLv|TLSv1[^.]|TLSv1\.0|TLSv1\.1)'"
has "certificate CN is $DOMAIN" "CN=$DOMAIN" \
    "$(echo | timeout 5 openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" 2>/dev/null | grep -m1 'subject=')"

# -----------------------------------------------------------------------------
section "M9  The website answers"
eq  "https://$DOMAIN/ returns 200"            "200" "$(https_code "$DOMAIN" /)"
eq  "https://$DOMAIN/wp-login.php returns 200" "200" "$(https_code "$DOMAIN" /wp-login.php)"
has "the home page is the WordPress site"  "<title>$(env_get WP_TITLE)</title>" "$(https_body "$DOMAIN" /)"
has "PHP is executed, not served as text"  "wp-content" "$(https_body "$DOMAIN" /)"
no  "wp-config.php is not downloadable"    bash -c "[ \"\$(curl -sk -o /dev/null -w '%{http_code}' --resolve '$DOMAIN:443:127.0.0.1' https://$DOMAIN/wp-config.php)\" = 200 ]"

# -----------------------------------------------------------------------------
section "M10 WordPress users"
WPUSERS="$(docker exec wordpress wp --allow-root --path=/var/www/html user list --field=user_login 2>/dev/null)"
eq  "exactly two users exist" "2" "$(echo "$WPUSERS" | grep -c .)"
ADMIN="$(docker exec wordpress wp --allow-root --path=/var/www/html user list --role=administrator --field=user_login 2>/dev/null)"
has "an administrator exists" "$(env_get WP_ADMIN_USER)" "$ADMIN"
no  "the admin login contains no 'admin'"         bash -c "echo '$ADMIN' | grep -qi admin"
no  "the admin login contains no 'administrator'" bash -c "echo '$ADMIN' | grep -qi administrator"

# -----------------------------------------------------------------------------
section "M11 Named volumes under $DATA_PATH"
for v in wordpress_files mariadb_data; do
    ok "volume 'inception_$v' exists" docker volume inspect "inception_$v"
    eq "  ... is a named volume (local driver)" "local" \
       "$(docker volume inspect "inception_$v" --format '{{.Driver}}' 2>/dev/null)"
done
eq  "wordpress volume points into $DATA_PATH" "$DATA_PATH/wordpress" \
    "$(docker volume inspect inception_wordpress_files --format '{{.Options.device}}' 2>/dev/null)"
eq  "mariadb volume points into $DATA_PATH"   "$DATA_PATH/mariadb" \
    "$(docker volume inspect inception_mariadb_data   --format '{{.Options.device}}' 2>/dev/null)"
ok  "WordPress files are visible on the host"  test -f "$DATA_PATH/wordpress/wp-config.php"
ok  "the database lives on the host"           test -d "$DATA_PATH/mariadb/$(env_get MYSQL_DATABASE)"
no  "no bind mount is declared on a service"   grep -nE "^\s+- +[./~]" "$SRCS/docker-compose.yml"

# -----------------------------------------------------------------------------
section "M12 Database"
ok  "WordPress can reach the database" docker exec wordpress wp --allow-root --path=/var/www/html db check
has "the wordpress database exists" "$(env_get MYSQL_DATABASE)" \
    "$(docker exec mariadb sh -c 'mariadb -u root -p"$(cat /run/secrets/db_root_password)" -e "SHOW DATABASES;"' 2>/dev/null)"
no  "root cannot log in over TCP" \
    docker exec mariadb sh -c 'mariadb -h 127.0.0.1 -u root -p"$(cat /run/secrets/db_root_password)" -e "SELECT 1"'

summary
