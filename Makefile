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
RELAY ?= 0
STATE ?= dashboard-running

.PHONY: \
	help \
	repo-init repo-check repo-reset \
	install \
	dev \
	demo-start demo-foreground demo-stop demo-logs demo-onboard demo-smoke demo-pair-check \
	compose-start compose-stop compose-restart compose-logs \
	test-smoke test-fast test-live test-demo test-e2e verify screenshot test-prep test-affected test-release \
	pwa-multisig-demo \
	browser-wasm-refresh browser-wasm-sync browser-wasm-check wasm-toolchain-check \
	igloo-paper-sync igloo-paper-verify igloo-paper-usage-coverage-sync igloo-ui-paper-token-sync igloo-ui-paper-token-check igloo-ui-watch \
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
		'  make install [INSTALL_UPDATE=1]' \
		'  make demo-start [PORT=<port>]' \
		'  make demo-foreground [PORT=<port>]' \
		'  make demo-stop' \
		'  make demo-logs' \
		'  make demo-onboard' \
		'  make dev [PORT=<relay-port>]' \
		'  make demo-smoke [PORT=<port>]' \
		'  make demo-pair-check' \
		'  make compose-start SERVICES="<service> [service...]"' \
		'  make compose-stop SERVICES="<service> [service...]"' \
		'  make compose-restart SERVICES="<service> [service...]"' \
		'  make compose-logs SERVICES="<service> [service...]"' \
		'  make test-smoke' \
		'  make test-fast' \
		'  make test-live' \
		'  make test-demo' \
		'  make test-e2e' \
		'  make verify' \
		'  make screenshot [STATE=dashboard-running|dashboard-stopped|welcome-returning]' \
		'  make test-prep' \
		'  make test-affected' \
		'  make test-release' \
		'  make browser-wasm-refresh' \
		'  make browser-wasm-sync' \
		'  make browser-wasm-check' \
		'  make wasm-toolchain-check' \
		'  make igloo-paper-sync [STRICT=1]' \
		'  make igloo-paper-verify [STRICT=1]' \
		'  make igloo-paper-usage-coverage-sync' \
		'  make igloo-ui-paper-token-sync' \
		'  make igloo-ui-paper-token-check' \
		'  make igloo-ui-watch' \
		'  make igloo-chrome-dev' \
		'  make igloo-chrome-build' \
		'  make igloo-chrome-test-unit' \
		'  make igloo-chrome-test-e2e' \
		'  make igloo-pwa-dev [RELAY=1] [PORT=<port>]' \
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
		'  scripts/, dev/scripts/, and test/scripts/ remain private implementation detail.' \
		'  demo-start launches the demo stack in the background.' \
		'  demo-foreground stays attached to the terminal.' \
		'  dev is the fast native loop: relay + igloo-shell co-signer (from dev/fixtures) + the igloo-pwa dev server. No Docker, no onboarding; Ctrl-C stops everything.' \
		'  igloo-pwa-dev RELAY=1 starts a native local relay, points the app at it, and stops it when the dev server exits (the Docker dev-relay is for the demo/CI lanes via make demo-start).' \
		'  igloo-paper-sync and igloo-paper-verify are manual; excluded from default test/CI lanes (require Paper desktop and Paper MCP).' \
		'  igloo-ui-paper-token-sync is a parent-owned handoff; igloo-ui does not depend on Paper tooling.'

repo-init:
	@cd "$(ROOT_DIR)" && git submodule sync && git submodule update --init
	@echo "Initialized top-level submodules (non-recursive by design)."

repo-check:
	@"$(ROOT_DIR)/scripts/check-setup.sh"

repo-reset:
	@"$(ROOT_DIR)/scripts/reset.sh" --force

# Install npm deps for every JS client in one pass. The repos/ submodules stay
# self-contained (independent installs, per-leaf node_modules) — deliberately not
# an npm workspace, which would hoist deps and break the leaves' build scripts.
# Default is lockfile-exact `npm ci` (reproducible, leaves the tree clean);
# INSTALL_UPDATE=1 runs incremental `npm install` (may rewrite lockfiles).
install:
	@INSTALL_UPDATE="$(INSTALL_UPDATE)" "$(ROOT_DIR)/scripts/install.sh"

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

dev:
	@PORT="$(PORT)" "$(ROOT_DIR)/scripts/dev.sh"

demo-smoke:
	@RELAY_PORT="$(PORT)" "$(ROOT_DIR)/test/scripts/test-demo-harness-onboard.sh"

# Fast gate that the pinned bifrost-rs + igloo-shell submodule pair compiles
# together (igloo-shell path-depends on bifrost-rs, so an API change can break it
# with no version bump). Front-runs the slower in-Docker demo build in CI.
# Uses `--all-targets` (not just `--bin`) so it also compiles the submodules'
# `#[cfg(test)]` modules: a bin-only check misses test-fixture drift (e.g. a
# bifrost-rs struct gaining fields rots igloo-shell-core's struct-literal
# fixtures), which is exactly the rot this gate now exists to catch.
demo-pair-check:
	@echo "==> Checking bifrost-devtools compiles (repos/bifrost-rs, all targets)"
	@cargo check --locked --all-targets --manifest-path "$(ROOT_DIR)/repos/bifrost-rs/Cargo.toml" -p bifrost-devtools
	@echo "==> Checking igloo-shell compiles against the pinned bifrost-rs (repos/igloo-shell, all targets)"
	@cargo check --locked --all-targets --manifest-path "$(ROOT_DIR)/repos/igloo-shell/Cargo.toml"

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

# Canonical "did I break anything" gate for humans and agents: lean guards +
# typecheck + the render-only fast e2e lane. Deterministic, clear exit code.
verify:
	@npm --prefix "$(TEST_DIR)" run test:verify

# Render a PWA screen headlessly and write a PNG + visible-text dump to
# .tmp/agent/. STATE is a dev scenario (dashboard-running, dashboard-stopped,
# welcome-returning) — the running dashboard renders via a seeded runtimeSnapshot
# that storage-only seeding can't reach. For agents and humans alike.
screenshot:
	@FROSTR_SCREENSHOT_STATE="$(STATE)" npm --prefix "$(TEST_DIR)" run test:screenshot

pwa-multisig-demo:
	@"$(TEST_DIR)/scripts/pwa-multisig-demo.sh"

test-prep:
	@"$(ROOT_DIR)/scripts/test-prebuild.sh" release

test-affected:
	@"$(ROOT_DIR)/scripts/test-affected.sh"

test-release:
	@"$(ROOT_DIR)/scripts/release-matrix.sh"

browser-wasm-refresh:
	@"$(ROOT_DIR)/scripts/prepare-browser-wasm.sh" sync all
	@"$(ROOT_DIR)/test/scripts/check-browser-wasm-stamp.sh" --write

browser-wasm-sync: browser-wasm-refresh

browser-wasm-check:
	@"$(ROOT_DIR)/scripts/prepare-browser-wasm.sh" check all

wasm-toolchain-check:
	@"$(ROOT_DIR)/test/scripts/check-wasm-toolchain.sh"

igloo-paper-sync:
	@if [[ ! -f "$(IGLOO_PAPER_DIR)/scripts/export_from_paper.py" ]]; then \
		echo 'error: igloo-paper submodule is not initialized. Run make repo-init.' >&2; \
		exit 1; \
	fi
	@cd "$(IGLOO_PAPER_DIR)" && PYTHONDONTWRITEBYTECODE=1 python3 scripts/export_from_paper.py
	@if [[ "$(STRICT)" == "0" ]]; then \
		cd "$(IGLOO_PAPER_DIR)" && PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify.py; \
	else \
		cd "$(IGLOO_PAPER_DIR)" && PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify.py --strict-drift; \
	fi

igloo-paper-verify:
	@if [[ ! -f "$(IGLOO_PAPER_DIR)/scripts/verify.py" ]]; then \
		echo 'error: igloo-paper submodule is not initialized. Run make repo-init.' >&2; \
		exit 1; \
	fi
	@if [[ "$(STRICT)" == "1" ]]; then \
		cd "$(IGLOO_PAPER_DIR)" && PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify.py --strict-drift; \
	else \
		cd "$(IGLOO_PAPER_DIR)" && PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify.py; \
	fi

igloo-paper-usage-coverage-sync:
	@if [[ ! -f "$(IGLOO_PAPER_DIR)/scripts/update_usage_coverage.py" ]]; then \
		echo 'error: igloo-paper submodule is not initialized. Run make repo-init.' >&2; \
		exit 1; \
	fi
	@cd "$(IGLOO_PAPER_DIR)" && PYTHONDONTWRITEBYTECODE=1 python3 scripts/update_usage_coverage.py

igloo-ui-paper-token-sync:
	@cd "$(ROOT_DIR)" && node dev/scripts/sync-igloo-paper-tokens-to-ui.mjs sync

igloo-ui-paper-token-check:
	@cd "$(ROOT_DIR)" && node dev/scripts/sync-igloo-paper-tokens-to-ui.mjs check

# Rebuild igloo-ui's dist/styles.css on every CSS source change. The pwa dev
# server loads igloo-ui CSS from dist (JS already resolves to src via vite), so
# run this alongside `make igloo-pwa-dev` for instant CSS hot-reload instead of a
# manual `npm run build` after each edit.
igloo-ui-watch:
	@cd "$(IGLOO_UI_DIR)" && npx tailwindcss -c ./tailwind.config.js -i ./src/styles.css -o ./dist/styles.css --watch

igloo-chrome-dev:
	@npm --prefix "$(IGLOO_CHROME_DIR)" run dev

igloo-chrome-build:
	@npm --prefix "$(IGLOO_CHROME_DIR)" run build

igloo-chrome-test-unit:
	@npm --prefix "$(IGLOO_CHROME_DIR)" run test:unit

igloo-chrome-test-e2e:
	@npm --prefix "$(IGLOO_CHROME_DIR)" run test:e2e

igloo-pwa-dev:
	@RELAY="$(RELAY)" RELAY_PORT="$(PORT)" "$(ROOT_DIR)/scripts/igloo-pwa-dev.sh"

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
