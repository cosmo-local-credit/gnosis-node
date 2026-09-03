#!/usr/bin/env bash
# Map reth.env onto `reth node` flags. Image entrypoint is overridden by compose.
set -euo pipefail

chain="${RETH_CHAIN:-gnosis}"
datadir="${RETH_DATADIR:-/data}"
jwt="${RETH_AUTHRPC_JWTSECRET:-/shared/jwt.hex}"
node_type="${RETH_NODE_TYPE:-full}"

args=(
  node
  --chain "${chain}"
  --datadir "${datadir}"
  --authrpc.jwtsecret "${jwt}"
  --authrpc.addr "${RETH_AUTHRPC_ADDR:-0.0.0.0}"
  --authrpc.port "${RETH_AUTHRPC_PORT:-8551}"
  --port "${RETH_PORT:-30303}"
  --discovery.port "${RETH_DISCOVERY_PORT:-30303}"
  --discovery.addr "${RETH_DISCOVERY_ADDR:-0.0.0.0}"
)

case "${node_type}" in
  full) args+=(--full) ;;
  minimal) args+=(--minimal) ;;
  archive) ;;
  *)
    echo "unknown RETH_NODE_TYPE=${node_type} (full|minimal|archive)" >&2
    exit 1
    ;;
esac

if [ "${RETH_HTTP:-true}" = "true" ]; then
  args+=(
    --http
    --http.addr "${RETH_HTTP_ADDR:-0.0.0.0}"
    --http.port "${RETH_HTTP_PORT:-8545}"
    --http.api "${RETH_HTTP_API:-net,eth,web3,txpool}"
    --http.corsdomain "${RETH_HTTP_CORSDOMAIN:-*}"
  )
fi

if [ "${RETH_WS:-true}" = "true" ]; then
  args+=(
    --ws
    --ws.addr "${RETH_WS_ADDR:-0.0.0.0}"
    --ws.port "${RETH_WS_PORT:-8546}"
    --ws.api "${RETH_WS_API:-net,eth,web3,txpool}"
    --ws.origins "${RETH_WS_ORIGINS:-*}"
  )
fi

if [ -n "${RETH_CONFIG:-}" ]; then
  args+=(--config "${RETH_CONFIG}")
fi

if [ -n "${RETH_NAT:-}" ]; then
  args+=(--nat "${RETH_NAT}")
fi

if [ "${RETH_METRICS:-true}" = "true" ]; then
  args+=(--metrics "${RETH_METRICS_ADDR:-0.0.0.0}:${RETH_METRICS_PORT:-9001}")
fi

if [ -n "${RETH_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  extra=(${RETH_EXTRA_ARGS})
  args+=("${extra[@]}")
fi

exec reth "${args[@]}"
