# =============================================================================
#  Tiny assertion helpers shared by the mandatory and bonus test suites.
# =============================================================================
set -u

PASS=0; FAIL=0; SKIP=0
G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; B='\033[0;34m'; D='\033[0;90m'; N='\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/srcs/.env"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE"; }

DOMAIN="$(env_get DOMAIN_NAME)"
LOGIN="$(env_get LOGIN)"
DATA_PATH="$(env_get DATA_PATH)"
COMPOSE="docker compose -f $ROOT/srcs/docker-compose.yml"
COMPOSE_BONUS="$COMPOSE -f $ROOT/srcs/docker-compose.bonus.yml"

section() { printf "\n${B}--- %s ${N}\n" "$1"; }

# ok <label> <command...>   : the command must succeed
ok() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ${G}PASS${N}  %s\n" "$label"; PASS=$((PASS+1))
    else
        printf "  ${R}FAIL${N}  %s\n" "$label"; FAIL=$((FAIL+1))
    fi
}

# no <label> <command...>   : the command must FAIL (used for "must be refused")
no() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ${R}FAIL${N}  %s\n" "$label"; FAIL=$((FAIL+1))
    else
        printf "  ${G}PASS${N}  %s\n" "$label"; PASS=$((PASS+1))
    fi
}

# eq <label> <expected> <actual>
eq() {
    if [ "$2" = "$3" ]; then
        printf "  ${G}PASS${N}  %s ${D}(%s)${N}\n" "$1" "$3"; PASS=$((PASS+1))
    else
        printf "  ${R}FAIL${N}  %s ${D}(expected '%s', got '%s')${N}\n" "$1" "$2" "$3"; FAIL=$((FAIL+1))
    fi
}

# has <label> <needle> <haystack>
has() {
    case "$3" in
        *"$2"*) printf "  ${G}PASS${N}  %s\n" "$1"; PASS=$((PASS+1)) ;;
        *)      printf "  ${R}FAIL${N}  %s ${D}(no '%s' in output)${N}\n" "$1" "$2"; FAIL=$((FAIL+1)) ;;
    esac
}

skip() { printf "  ${Y}SKIP${N}  %s ${D}(%s)${N}\n" "$1" "${2:-}"; SKIP=$((SKIP+1)); }

# HTTPS through nginx; --resolve so the suite works even before /etc/hosts is edited.
https_code() { curl -sk -o /dev/null -w '%{http_code}' --resolve "$1:443:127.0.0.1" "https://$1$2"; }
https_body() { curl -sk           --resolve "$1:443:127.0.0.1" "https://$1$2"; }

summary() {
    printf "\n${B}=====================================================${N}\n"
    if [ "$FAIL" -eq 0 ]; then
        printf "  ${G}%d passed${N}, %d skipped, ${G}0 failed${N}\n" "$PASS" "$SKIP"
        printf "${B}=====================================================${N}\n"
        return 0
    fi
    printf "  ${G}%d passed${N}, %d skipped, ${R}%d failed${N}\n" "$PASS" "$SKIP" "$FAIL"
    printf "${B}=====================================================${N}\n"
    return 1
}
