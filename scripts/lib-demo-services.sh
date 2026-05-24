#!/usr/bin/env bash

# Shared names for the parent-owned demo harness services.
DEMO_RELAY_SERVICE="${DEMO_RELAY_SERVICE:-dev-relay}"
DEMO_NODE_SERVICE="${DEMO_NODE_SERVICE:-igloo-demo}"
DEMO_NODE_SERVICE_DIR="${DEMO_NODE_SERVICE_DIR:-services/igloo-demo}"
DEMO_RELAY_IMAGE="${DEMO_RELAY_IMAGE:-bifrost-infra-dev-relay:dev}"
DEMO_NODE_IMAGE="${DEMO_NODE_IMAGE:-bifrost-infra-igloo-demo:dev}"
DEMO_HARNESS_SERVICES=("${DEMO_RELAY_SERVICE}" "${DEMO_NODE_SERVICE}")
