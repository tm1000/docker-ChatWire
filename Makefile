.PHONY: help setup build up down restart logs ps update-submodules

help:
	@echo "Targets:"
	@echo "  setup   - init/checkout git submodules (chatwire, softmod)"
	@echo "  build   - build the cw-a and web images"
	@echo "  up      - setup + build (if needed) + start all services in the background"
	@echo "  down    - stop and remove containers"
	@echo "  restart - restart the cw-a service"
	@echo "  logs    - follow cw-a logs"
	@echo "  ps      - show service status"
	@echo "  update-submodules - pull latest commits for chatwire@main and softmod@Main"

setup:
	git submodule update --init --recursive

build: setup
	docker compose build

up: setup
	docker compose up -d --build

down:
	docker compose down

restart:
	docker compose restart cw-a

logs:
	docker compose logs -f cw-a

ps:
	docker compose ps

update-submodules:
	git submodule update --remote --merge
