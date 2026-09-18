NAME := inception

SRCS := srcs
ENV_FILE := $(SRCS)/.env
SECRETS_DIR := secrets

DATA_PATH := $(shell sed -n 's/^DATA_PATH=//p' $(ENV_FILE))
DOMAIN_NAME := $(shell sed -n 's/^DOMAIN_NAME=//p' $(ENV_FILE))

COMPOSE := docker compose -f $(SRCS)/docker-compose.yml
COMPOSE_BONUS := docker compose -f $(SRCS)/docker-compose.yml -f $(SRCS)/docker-compose.bonus.yml

SECRET_FILES := $(SECRETS_DIR)/db_root_password.txt \
                $(SECRETS_DIR)/db_password.txt \
                $(SECRETS_DIR)/wp_admin_password.txt \
                $(SECRETS_DIR)/wp_user_password.txt \
                $(SECRETS_DIR)/ftp_password.txt

.PHONY: all bonus setup dirs secrets hosts down clean fclean re

all: setup
	@$(COMPOSE) up -d --build

bonus: setup
	@$(COMPOSE_BONUS) up -d --build

setup: dirs secrets hosts

dirs:
	@mkdir -p $(DATA_PATH)/wordpress $(DATA_PATH)/mariadb

secrets: $(SECRET_FILES)

$(SECRETS_DIR)/%.txt:
	@mkdir -p $(SECRETS_DIR)
	@openssl rand -base64 24 | tr -d '\n/+=' | cut -c1-24 > $@
	@chmod 600 $@

hosts:
	@for host in $(DOMAIN_NAME) static.$(DOMAIN_NAME) adminer.$(DOMAIN_NAME) status.$(DOMAIN_NAME); do \
		if ! grep -qE "^[^#]*[[:space:]]$$host([[:space:]]|$$)" /etc/hosts; then \
			echo "127.0.0.1 $$host" | sudo tee -a /etc/hosts > /dev/null; \
		fi; \
	done

down:
	@$(COMPOSE_BONUS) down --remove-orphans

clean: down
	@docker image rm -f \
		nginx:inception \
		wordpress:inception \
		mariadb:inception \
		redis:inception \
		ftp:inception \
		adminer:inception \
		static-site:inception \
		status:inception 2>/dev/null || true

fclean: clean
	@docker volume rm -f inception_wordpress_files inception_mariadb_data 2>/dev/null || true
	@docker run --rm -v $(DATA_PATH):/data debian:bookworm \
		rm -rf /data/wordpress /data/mariadb 2>/dev/null || true

re: fclean all
