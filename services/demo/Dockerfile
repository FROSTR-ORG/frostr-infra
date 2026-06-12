# syntax=docker/dockerfile:1
#
# Self-contained demo-harness images. The Rust binaries are compiled INSIDE this
# build (for the image's own platform) instead of bind-mounting host-native
# builds — so the demo stack runs on Linux, macOS, and Windows-WSL alike. (A
# host-built macOS Mach-O binary can never exec in a Linux container.)
#
# Builder stages are chained so each binary compiles once and the relay image
# does NOT need the igloo-shell source:
#   builder-relay  -> bifrost-devtools           -> dev-relay
#   builder-demo   -> (+ igloo-shell)            -> igloo-demo
# Select the runtime target per service with compose `target:`.
#
# bifrost-devtools needs a recent stable: edition 2024 (>= 1.85) and `if let`
# chains / let_chains (stabilized in 1.88). Pinned to match the workspace's
# current stable toolchain (rustc 1.95) for reproducible image builds; override
# RUST_IMAGE to bump.
ARG RUST_IMAGE=rust:1.95-bookworm

# ---- builder-relay: compile bifrost-devtools (needs only repos/bifrost-rs) ----
FROM ${RUST_IMAGE} AS builder-relay

# bifrost-devtools and igloo-shell are both pure rustls (tokio-tungstenite
# rustls-tls-webpki-roots) — no OpenSSL/native-tls in either Cargo.lock — so no
# system TLS build deps are needed (ring uses the image's bundled C compiler).

WORKDIR /src
# `**/target` is excluded via .dockerignore, so only source is copied.
COPY repos/bifrost-rs /src/repos/bifrost-rs

# Cargo caches + the target dir are BuildKit cache mounts (fast rebuilds); cache
# mounts are not persisted into the layer, so copy the binary out to /out.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/repos/bifrost-rs/target \
    set -eux; \
    cargo build --locked --manifest-path /src/repos/bifrost-rs/Cargo.toml \
      -p bifrost-devtools --bin bifrost-devtools; \
    mkdir -p /out; \
    cp /src/repos/bifrost-rs/target/debug/bifrost-devtools /out/bifrost-devtools

# ---- builder-demo: add igloo-shell (reuses builder-relay's bifrost compile) ----
FROM builder-relay AS builder-demo
COPY repos/igloo-shell /src/repos/igloo-shell
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/repos/igloo-shell/target \
    set -eux; \
    cargo build --locked --manifest-path /src/repos/igloo-shell/Cargo.toml \
      -p igloo-shell-cli --bin igloo-shell; \
    cp /src/repos/igloo-shell/target/debug/igloo-shell /out/igloo-shell

# ---- runtime base: minimal image to run the compiled binaries ----
# rustls links no system OpenSSL, so libssl3 is unnecessary; ca-certificates is
# kept for any outbound TLS (rustls-webpki-roots bundles roots, but it's cheap).
FROM ubuntu:24.04 AS runtime
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       bash ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace

# ---- dev-relay: just the relay binary ----
FROM runtime AS dev-relay
COPY --from=builder-relay /out/bifrost-devtools /usr/local/bin/bifrost-devtools
COPY services/dev-relay/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# ---- igloo-demo: relay tooling + igloo-shell CLI ----
FROM runtime AS igloo-demo
COPY --from=builder-demo /out/bifrost-devtools /usr/local/bin/bifrost-devtools
COPY --from=builder-demo /out/igloo-shell /usr/local/bin/igloo-shell
COPY services/igloo-demo/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# Pre-create the short `/w` state link as root. The container runs as a non-root
# host uid (compose `user:`), which cannot create a symlink at `/`; the link
# must stay 2 chars so the daemon's XDG_STATE_HOME socket path fits the Unix
# sun_path limit. It points into world-writable /tmp, which the entrypoint then
# repoints at the real (bind-mounted) XDG state dir at runtime.
RUN ln -sfn /tmp/igloo-shell-state /w
# Short, container-local XDG_RUNTIME_DIR for the daemon's control socket. The
# socket must live on a socket-capable filesystem: macOS Docker bind mounts
# (virtiofs/gRPC-FUSE) reject AF_UNIX bind() with EINVAL, so it cannot sit under
# the bind-mounted artifact dir. `/r` is on the container's own overlay fs and
# stays short enough for sun_path. World-writable+sticky for the non-root uid.
RUN mkdir -p /r && chmod 1777 /r
ENTRYPOINT ["/entrypoint.sh"]
