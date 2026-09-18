# =============================================================================
#  Inception - Makefile
# -----------------------------------------------------------------------------
#   make          build + start the stack (nginx, wordpress, mariadb)
#   make down     stop and remove the containers (data is kept)
#   make clean    down + remove the images built by this project
#   make fclean   clean + delete the volumes and the host data folder
#   make re       fclean + make
# =============================================================================

SRCS        := srcs
ENV_FILE    := $(SRCS)/.env
SECRETS_DIR := secrets
COMPOSE     := docker compose -f $(SRCS)/docker-compose.yml

# Single source of truth: values are read from the .env file
DOMAIN_NAME := $(shell sed -n 's/^DOMAIN_NAME=//p' $(ENV_FILE))
DATA_PATH   := $(shell sed -n 's/^DATA_PATH=//p'   $(ENV_FILE))

SECRET_FILES := $(SECRETS_DIR)/db_root_password.txt \
                $(SECRETS_DIR)/db_password.txt \
                $(SECRETS_DIR)/wp_admin_password.txt \
                $(SECRETS_DIR)/wp_user_password.txt

.PHONY: all setup dirs secrets hosts down clean fclean re

# --- build and start ---------------------------------------------------------
all: setup
	@$(COMPOSE) up -d --build

# --- one-time preparation ----------------------------------------------------
setup: dirs secrets hosts

# Host folders that back the two named volumes (/home/<login>/data)
dirs:
	@mkdir -p $(DATA_PATH)/wordpress $(DATA_PATH)/mariadb

# Each missing secret is generated once with a random 24-char password
secrets: $(SECRET_FILES)

$(SECRETS_DIR)/%.txt:
	@mkdir -p $(SECRETS_DIR)
	@openssl rand -base64 24 | tr -d '\n/+=' | cut -c1-24 > $@
	@chmod 600 $@

# <login>.42.fr must resolve to the local machine
hosts:
	@grep -qE "^[^#]*[[:space:]]$(DOMAIN_NAME)([[:space:]]|$$)" /etc/hosts \
		|| echo "127.0.0.1 $(DOMAIN_NAME)" | sudo tee -a /etc/hosts > /dev/null

# --- stop / clean ------------------------------------------------------------
down:
	@$(COMPOSE) down

clean: down
	@docker image rm -f nginx:inception wordpress:inception mariadb:inception \
		2>/dev/null || true

fclean: clean
	@docker volume rm -f inception_wordpress_files inception_mariadb_data \
		2>/dev/null || true
	@docker run --rm -v $(DATA_PATH):/data debian:bookworm \
		rm -rf /data/wordpress /data/mariadb 2>/dev/null || true

re: fclean all