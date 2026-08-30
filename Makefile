# =============================================================================
#  Inception - Makefile
# -----------------------------------------------------------------------------
#   make            build + start the MANDATORY stack (nginx, wordpress, mariadb)
#   make bonus      build + start mandatory + BONUS (redis, ftp, adminer, ...)
#   make test       run the mandatory test suite   (see TESTING_ROADMAP.md)
#   make test-bonus run the bonus test suite
#   make down       stop and remove the containers (data is kept)
#   make clean      down + remove the images built by this project
#   make fclean     clean + delete the volumes and /home/$(LOGIN)/data
#   make re         fclean + make
# =============================================================================

NAME        := inception
SRCS        := srcs
ENV_FILE    := $(SRCS)/.env
SECRETS_DIR := secrets

# Read LOGIN / DATA_PATH straight from the .env so there is a single source of truth.
LOGIN       := $(shell sed -n 's/^LOGIN=//p'       $(ENV_FILE))
DOMAIN_NAME := $(shell sed -n 's/^DOMAIN_NAME=//p' $(ENV_FILE))
DATA_PATH   := $(shell sed -n 's/^DATA_PATH=//p'   $(ENV_FILE))

COMPOSE       := docker compose -f $(SRCS)/docker-compose.yml
COMPOSE_BONUS := docker compose -f $(SRCS)/docker-compose.yml -f $(SRCS)/docker-compose.bonus.yml

SECRET_FILES := $(SECRETS_DIR)/db_root_password.txt \
                $(SECRETS_DIR)/db_password.txt \
                $(SECRETS_DIR)/wp_admin_password.txt \
                $(SECRETS_DIR)/wp_user_password.txt \
                $(SECRETS_DIR)/ftp_password.txt

GREEN := \033[0;32m
BLUE  := \033[0;34m
YEL   := \033[0;33m
NC    := \033[0m

.PHONY: all bonus setup secrets dirs hosts up down stop start clean fclean re re-bonus \
        build build-bonus logs ps test test-bonus status help

# --- mandatory ---------------------------------------------------------------
all: setup
	@printf "$(BLUE)==> building and starting the MANDATORY stack$(NC)\n"
	@$(COMPOSE) up -d --build
	@printf "$(GREEN)==> up. https://$(DOMAIN_NAME)$(NC)\n"

# --- bonus -------------------------------------------------------------------
bonus: setup
	@printf "$(BLUE)==> building and starting MANDATORY + BONUS$(NC)\n"
	@$(COMPOSE_BONUS) up -d --build
	@printf "$(GREEN)==> up. https://$(DOMAIN_NAME)$(NC)\n"
	@printf "$(GREEN)    https://static.$(DOMAIN_NAME)  https://adminer.$(DOMAIN_NAME)  https://status.$(DOMAIN_NAME)$(NC)\n"

build:
	@$(COMPOSE) build

build-bonus:
	@$(COMPOSE_BONUS) build

# --- one-time preparation ----------------------------------------------------
setup: dirs secrets hosts

dirs:
	@mkdir -p $(DATA_PATH)/wordpress $(DATA_PATH)/mariadb
	@printf "$(GREEN)[ok]$(NC) data directories ready under $(DATA_PATH)\n"

secrets: $(SECRET_FILES)
	@printf "$(GREEN)[ok]$(NC) secrets present in $(SECRETS_DIR)/\n"

# Each missing secret is generated once with a 24-byte random password.
$(SECRETS_DIR)/%.txt:
	@mkdir -p $(SECRETS_DIR)
	@openssl rand -base64 24 | tr -d '\n/+=' | cut -c1-24 > $@
	@chmod 600 $@
	@printf "$(YEL)[gen]$(NC) $@\n"

# The subject requires $(DOMAIN_NAME) to resolve to the local machine.
# The bonus sub-domains are added too - they are harmless without the bonus stack.
HOSTNAMES := $(DOMAIN_NAME) static.$(DOMAIN_NAME) adminer.$(DOMAIN_NAME) status.$(DOMAIN_NAME)

hosts:
	@for h in $(HOSTNAMES); do \
		if grep -qE "^[^#]*[[:space:]]$$h([[:space:]]|$$)" /etc/hosts; then \
			printf "$(GREEN)[ok]$(NC) $$h already in /etc/hosts\n"; \
		elif sudo -n true 2>/dev/null || [ -t 0 ]; then \
			printf "$(YEL)[..]$(NC) adding $$h to /etc/hosts (sudo)\n"; \
			echo "127.0.0.1 $$h" | sudo tee -a /etc/hosts > /dev/null; \
		else \
			printf "$(YEL)[!!]$(NC) $$h is missing from /etc/hosts and sudo is not available here.\n"; \
			printf "     Add it by hand:  echo '127.0.0.1 $$h' | sudo tee -a /etc/hosts\n"; \
		fi; \
	done

# --- lifecycle ---------------------------------------------------------------
up:
	@$(COMPOSE) up -d

down:
	@printf "$(BLUE)==> stopping$(NC)\n"
	@$(COMPOSE_BONUS) down --remove-orphans

stop:
	@$(COMPOSE_BONUS) stop

start:
	@$(COMPOSE_BONUS) start

# --- inspection --------------------------------------------------------------
ps status:
	@$(COMPOSE_BONUS) ps

logs:
	@$(COMPOSE_BONUS) logs -f --tail=100

# --- tests -------------------------------------------------------------------
test:
	@bash tools/test_mandatory.sh

test-bonus:
	@bash tools/test_bonus.sh

# --- cleaning ----------------------------------------------------------------
clean: down
	@printf "$(BLUE)==> removing project images$(NC)\n"
	@docker image rm -f nginx:inception wordpress:inception mariadb:inception \
		redis:inception ftp:inception adminer:inception \
		static-site:inception status:inception 2>/dev/null || true

fclean: clean
	@printf "$(BLUE)==> removing volumes and host data$(NC)\n"
	@docker volume rm -f inception_wordpress_files inception_mariadb_data 2>/dev/null || true
	@# The volume contents are owned by the container users (mysql, www-data),
	@# so they are deleted from inside a throwaway root container: no sudo needed.
	@docker run --rm -v $(DATA_PATH):/data debian:bookworm \
		rm -rf /data/wordpress /data/mariadb 2>/dev/null || true
	@printf "$(GREEN)==> everything removed$(NC)\n"

re: fclean all

re-bonus: fclean bonus

help:
	@printf "$(BLUE)Inception targets$(NC)\n"
	@printf "  make            mandatory stack (nginx + wordpress + mariadb)\n"
	@printf "  make bonus      mandatory + redis, ftp, adminer, static-site, status\n"
	@printf "  make test       run the mandatory checks\n"
	@printf "  make test-bonus run the bonus checks\n"
	@printf "  make down       stop everything (data kept)\n"
	@printf "  make fclean     wipe containers, images, volumes and host data\n"
	@printf "  make re         fclean + make\n"
