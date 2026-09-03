.PHONY: help setup override config build up down restart logs ps watch update-submodules

help:
	@echo "Targets:"
	@echo "  setup   - init/checkout git submodules (chatwire, softmod)"
	@echo "  chown   - change ownership of the data directory to the current user"
	@echo "  override - create docker-compose.override.yml from the example (if missing)"
	@echo "  config  - print the merged compose config (base + override)"
	@echo "  build   - build the cw-a and web images"
	@echo "  up      - setup + build (if needed) + start all services in the background"
	@echo "  down    - stop and remove containers"
	@echo "  restart - restart the cw-a service"
	@echo "  logs    - follow cw-a logs"
	@echo "  watch   - follow logs of all services"
	@echo "  ps      - show service status"
	@echo "  update-submodules - pull latest commits for chatwire@main and softmod@Main"

setup:
	git submodule update --init --recursive

override:
	@if [ -e docker-compose.override.yml ]; then \
		echo "docker-compose.override.yml already exists, leaving it alone"; \
	else \
		cp docker-compose.override.yml.example docker-compose.override.yml; \
		echo "created docker-compose.override.yml (gitignored) - edit it, then: make up"; \
	fi

config:
	docker compose config

build: setup
	docker compose build

up: setup chown
	docker compose up -d --build

down:
	docker compose down

watch:
	docker compose logs -f

restart:
	docker compose restart cw-a

logs:
	docker compose logs -f cw-a

ps:
	docker compose ps

update-submodules:
	git submodule update --remote --merge

chown:
	sudo mkdir -p data www/public_html/archive www/public_html/modpack
	sudo chown -R 1000:1000 data www