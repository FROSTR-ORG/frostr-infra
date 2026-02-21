.PHONY: init start start-prod dev daemon stop restart reset logs shell build build-prod check health setup update logs-% start-% stop-% restart-%

SERVICES := igloo-server igloo-web igloo-cli

ifdef BG
  COMPOSE_UP := docker compose -f compose.yml up -d
  COMPOSE_UP_DEV := docker compose -f compose.yml -f compose.override.yml up -d
else
  COMPOSE_UP := docker compose -f compose.yml up
  COMPOSE_UP_DEV := docker compose -f compose.yml -f compose.override.yml up
endif

help:
	@echo "Bifrost Infra Commands:"
	@echo ""
	@echo "  make init      - Initialize submodules and start prerequisites"
	@echo "  make start     - Start all services"
	@echo "  make start-prod - Start production-style profile (no source mounts)"
	@echo "  make dev       - Start services with generated compose.override.yml"
	@echo "  make daemon    - Alias for 'make start BG=1'"
	@echo "  make stop      - Stop all services"
	@echo "  make restart   - Restart all services"
	@echo "  make reset     - Clear data and dependency caches"
	@echo "  make logs      - Follow logs from all services"
	@echo "  make shell     - Open shell in igloo-cli container"
	@echo "  make check     - Verify local prerequisites"
	@echo "  make health    - Show compose service status"
	@echo "  make setup     - Generate compose.override.yml for local package mounts"
	@echo "  make update    - Update service dependencies"

init:
	git submodule sync
	git submodule update --init
	@echo "Initialized top-level submodules (non-recursive by design)."

start:
	$(COMPOSE_UP) $(SERVICES)

start-prod:
	docker compose -f compose.yml -f compose.prod.yml up $(if $(BG),-d,) $(SERVICES)

dev:
	@if [ ! -f compose.override.yml ]; then ./scripts/setup-dev.sh; fi
	$(COMPOSE_UP_DEV) $(SERVICES)

daemon:
	$(MAKE) start BG=1

stop:
	docker compose -f compose.yml down

restart: stop start

reset:
	./scripts/reset.sh --force

logs:
	docker compose -f compose.yml logs -f

shell:
	docker compose -f compose.yml exec igloo-cli sh

build:
	docker compose -f compose.yml build

build-prod:
	docker compose -f compose.yml -f compose.prod.yml build

check:
	./scripts/check-setup.sh

health:
	@docker compose -f compose.yml ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

setup:
	./scripts/setup-dev.sh

update:
	./scripts/update.sh

logs-%:
	docker compose -f compose.yml logs -f $*

start-%:
	docker compose -f compose.yml up -d $*

stop-%:
	docker compose -f compose.yml stop $*

restart-%:
	docker compose -f compose.yml restart $*
