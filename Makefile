NAME := inception

SRCS := srcs
ENV_FILE := $(SRCS)/.env
DATA_PATH := $(shell sed -n 's/^DATA_PATH=//p' $(ENV_FILE))

COMPOSE := docker compose -f $(SRCS)/docker-compose.yml
COMPOSE_BONUS := docker compose -f $(SRCS)/docker-compose.yml -f $(SRCS)/docker-compose.bonus.yml

.PHONY: all bonus clean fclean re

all:
	@mkdir -p $(DATA_PATH)/wordpress $(DATA_PATH)/mariadb
	@$(COMPOSE) up -d --build

bonus:
	@mkdir -p $(DATA_PATH)/wordpress $(DATA_PATH)/mariadb
	@$(COMPOSE_BONUS) up -d --build

clean:
	@$(COMPOSE_BONUS) down --remove-orphans

fclean: clean
	@docker image rm -f \
		nginx:inception \
		wordpress:inception \
		mariadb:inception \
		redis:inception \
		ftp:inception \
		adminer:inception \
		static-site:inception \
		status:inception 2>/dev/null || true
	@docker volume rm -f inception_wordpress_files inception_mariadb_data 2>/dev/null || true
	@docker run --rm -v $(DATA_PATH):/data debian:bookworm \
		rm -rf /data/wordpress /data/mariadb 2>/dev/null || true

re: fclean all