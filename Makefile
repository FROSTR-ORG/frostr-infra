SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TEST_DIR := $(ROOT_DIR)/test
IGLOO_UI_DIR := $(ROOT_DIR)/repos/igloo-ui
IGLOO_PAPER_DIR := $(ROOT_DIR)/repos/igloo-paper
IGLOO_PWA_DIR := $(ROOT_DIR)/repos/igloo-pwa
IGLOO_CHROME_DIR := $(ROOT_DIR)/repos/igloo-chrome
IGLOO_HOME_DIR := $(ROOT_DIR)/repos/igloo-home
PORT ?= 8194

.PHONY: \
	help \
	repo-init repo-check repo-reset \
	demo-start demo-foreground demo-stop demo-logs demo-onboard demo-smoke \
	compose-start compose-stop compose-restart compose-logs \
	test-smoke test-fast test-live test-demo test-e2e test-prep test-affected test-release \
	browser-wasm-sync browser-wasm-check \
	igloo-paper-verify \
	igloo-chrome-dev igloo-chrome-build igloo-chrome-test-unit igloo-chrome-test-e2e \
	igloo-pwa-dev igloo-pwa-build igloo-pwa-test-unit igloo-pwa-test-e2e \
	igloo-home-dev igloo-home-tauri-dev igloo-home-build igloo-home-typecheck igloo-home-test-unit \
	igloo-home-test-visual igloo-home-test-desktop igloo-home-test-desktop-xvfb igloo-home-test-e2e

help:
	@printf '%s\n' \
		'Usage:' \
		'  make repo-init' \
		'  make repo-check' \
		'  make repo-reset' \
		'  make demo-start [PORT=<port>]' \
		'  make demo-foreground [PORT=<port>]' \
		'  make demo-stop' \
		'  make demo-logs' \
		'  make demo-onboard' \
		'  make demo-smoke [PORT=<port>]' \
		'  make compose-start SERVICES="<service> [service...]"' \
		'  make compose-stop SERVICES="<service> [service...]"' \
		'  make compose-restart SERVICES="<service> [service...]"' \
		'  make compose-logs SERVICES="<service> [service...]"' \
		'  make test-smoke' \
		'  make test-fast' \
		'  make test-live' \
		'  make test-demo' \
		'  make test-e2e' \
		'  make test-prep' \
		'  make test-affected' \
		'  make test-release' \
		'  make browser-wasm-sync' \
		'  make browser-wasm-check' \
		'  make igloo-paper-verify [STRICT=1]' \
		'  make igloo-chrome-dev' \
		'  make igloo-chrome-build' \
		'  make igloo-chrome-test-unit' \
		'  make igloo-chrome-test-e2e' \
		'  make igloo-pwa-dev' \
		'  make igloo-pwa-build' \
		'  make igloo-pwa-test-unit' \
		'  make igloo-pwa-test-e2e' \
		'  make igloo-home-dev' \
		'  make igloo-home-tauri-dev' \
		'  make igloo-home-build' \
		'  make igloo-home-typecheck' \
		'  make igloo-home-test-unit' \
		'  make igloo-home-test-visual' \
		'  make igloo-home-test-desktop' \
		'  make igloo-home-test-desktop-xvfb' \
		'  make igloo-home-test-e2e' \
		'' \
		'Notes:' \
		'  Makefile is the only supported root command interface.' \
		'  scripts/ remains private implementation detail.' \
		'  demo-start launches the demo stack in the background.' \
		'  demo-foreground stays attached to the terminal.' \
		'  igloo-paper-verify requires Paper desktop and Paper MCP.'

repo-init:
	@cd "$(ROOT_DIR)" && git submodule sync && git submodule update --init
	@echo "Initialized top-level submodules (non-recursive by design)."

repo-check:
	@"$(ROOT_DIR)/scripts/check-setup.sh"

repo-reset:
	@"$(ROOT_DIR)/scripts/reset.sh" --force

demo-start:
	@BG=1 "$(ROOT_DIR)/scripts/demo.sh" start "$(PORT)"

demo-foreground:
	@"$(ROOT_DIR)/scripts/demo.sh" foreground "$(PORT)"

demo-stop:
	@"$(ROOT_DIR)/scripts/demo.sh" stop

demo-logs:
	@"$(ROOT_DIR)/scripts/demo.sh" logs

demo-onboard:
	@"$(ROOT_DIR)/scripts/demo.sh" onboard

demo-smoke:
	@RELAY_PORT="$(PORT)" "$(ROOT_DIR)/test/scripts/test-demo-harness-onboard.sh"

compose-start:
	@if [[ -z "$(strip $(SERVICES))" ]]; then echo 'error: compose-start requires SERVICES="<service> [service...]"' >&2; exit 1; fi
	@docker compose -f "$(ROOT_DIR)/compose.test.yml" up -d $(SERVICES)

compose-stop:
	@if [[ -z "$(strip $(SERVICES))" ]]; then echo 'error: compose-stop requires SERVICES="<service> [service...]"' >&2; exit 1; fi
	@docker compose -f "$(ROOT_DIR)/compose.test.yml" stop $(SERVICES)

compose-restart:
	@if [[ -z "$(strip $(SERVICES))" ]]; then echo 'error: compose-restart requires SERVICES="<service> [service...]"' >&2; exit 1; fi
	@docker compose -f "$(ROOT_DIR)/compose.test.yml" restart $(SERVICES)

compose-logs:
	@if [[ -z "$(strip $(SERVICES))" ]]; then echo 'error: compose-logs requires SERVICES="<service> [service...]"' >&2; exit 1; fi
	@docker compose -f "$(ROOT_DIR)/compose.test.yml" logs -f $(SERVICES)

test-smoke:
	@npm --prefix "$(TEST_DIR)" run test:e2e:smoke

test-fast:
	@npm --prefix "$(TEST_DIR)" run test:e2e:fast

test-live:
	@npm --prefix "$(TEST_DIR)" run test:e2e:live

test-demo:
	@npm --prefix "$(TEST_DIR)" run test:e2e:demo

test-e2e:
	@npm --prefix "$(TEST_DIR)" run test:e2e

test-prep:
	@"$(ROOT_DIR)/scripts/test-prebuild.sh" release

test-affected:
	@"$(ROOT_DIR)/scripts/test-affected.sh"

test-release:
	@"$(ROOT_DIR)/scripts/release-matrix.sh"

browser-wasm-sync:
	@"$(ROOT_DIR)/scripts/prepare-browser-wasm.sh" sync all

browser-wasm-check:
	@"$(ROOT_DIR)/scripts/prepare-browser-wasm.sh" check all

igloo-paper-verify:
	@if [[ ! -f "$(IGLOO_PAPER_DIR)/scripts/verify.py" ]]; then \
		echo 'error: igloo-paper submodule is not initialized. Run make repo-init.' >&2; \
		exit 1; \
	fi
	@if [[ "$(STRICT)" == "1" ]]; then \
		python3 "$(IGLOO_PAPER_DIR)/scripts/verify.py" --strict-drift; \
	else \
		python3 "$(IGLOO_PAPER_DIR)/scripts/verify.py"; \
	fi

igloo-chrome-dev:
	@npm --prefix "$(IGLOO_CHROME_DIR)" run dev

igloo-chrome-build:
	@npm --prefix "$(IGLOO_CHROME_DIR)" run build

igloo-chrome-test-unit:
	@npm --prefix "$(IGLOO_CHROME_DIR)" run test:unit

igloo-chrome-test-e2e:
	@npm --prefix "$(IGLOO_CHROME_DIR)" run test:e2e

igloo-pwa-dev:
	@npm --prefix "$(IGLOO_PWA_DIR)" run dev

igloo-pwa-build:
	@npm --prefix "$(IGLOO_PWA_DIR)" run build

igloo-pwa-test-unit:
	@npm --prefix "$(IGLOO_PWA_DIR)" run test:unit

igloo-pwa-test-e2e:
	@npm --prefix "$(IGLOO_PWA_DIR)" run test:e2e

igloo-home-dev:
	@npm --prefix "$(IGLOO_HOME_DIR)" run dev

igloo-home-tauri-dev:
	@npm --prefix "$(IGLOO_HOME_DIR)" run tauri -- dev

igloo-home-build:
	@npm --prefix "$(IGLOO_HOME_DIR)" run build

igloo-home-typecheck:
	@npm --prefix "$(IGLOO_HOME_DIR)" run typecheck

igloo-home-test-unit:
	@npm --prefix "$(IGLOO_HOME_DIR)" run test:unit

igloo-home-test-visual:
	@npm --prefix "$(IGLOO_HOME_DIR)" run test:visual

igloo-home-test-desktop:
	@npm --prefix "$(IGLOO_HOME_DIR)" run test:desktop

igloo-home-test-desktop-xvfb:
	@npm --prefix "$(IGLOO_HOME_DIR)" run test:desktop:xvfb

igloo-home-test-e2e:
	@npm --prefix "$(TEST_DIR)" run test:e2e:igloo-home
