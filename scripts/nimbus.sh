#!/usr/bin/env bash
# Map nimbus.env onto nimbus_beacon_node flags. Image entrypoint is overridden by compose.
set -euo pipefail

bin="${NIMBUS_BIN:-/home/user/nimbus_beacon_node}"

args=(
  --network="${NIMBUS_NETWORK:-gnosis}"
  --data-dir="${NIMBUS_DATADIR:-/data}"
  --el="${NIMBUS_EL:-http://reth:8551}"
  --jwt-secret="${NIMBUS_JWTSECRET:-/shared/jwt.hex}"
  --non-interactive
  --status-bar=false
  --tcp-port="${NIMBUS_TCP_PORT:-9000}"
  --udp-port="${NIMBUS_UDP_PORT:-9000}"
)

if [ -n "${NIMBUS_HISTORY:-}" ]; then
  args+=(--history="${NIMBUS_HISTORY}")
fi

if [ -n "${NIMBUS_NAT:-}" ]; then
  args+=(--nat="${NIMBUS_NAT}")
fi

if [ "${NIMBUS_ENR_AUTO_UPDATE:-true}" = "true" ]; then
  args+=(--enr-auto-update)
fi

if [ "${NIMBUS_REST:-true}" = "true" ]; then
  args+=(
    --rest
    --rest-address="${NIMBUS_REST_ADDRESS:-0.0.0.0}"
    --rest-port="${NIMBUS_REST_PORT:-5052}"
  )
fi

if [ "${NIMBUS_METRICS:-true}" = "true" ]; then
  args+=(
    --metrics
    --metrics-address="${NIMBUS_METRICS_ADDRESS:-0.0.0.0}"
    --metrics-port="${NIMBUS_METRICS_PORT:-8008}"
  )
fi

if [ "${NIMBUS_LIGHT_CLIENT:-true}" = "true" ]; then
  args+=(
    --light-client-data-serve=true
    --light-client-data-import-mode="${NIMBUS_LIGHT_CLIENT_IMPORT_MODE:-only-new}"
  )
fi

if [ -n "${NIMBUS_MAX_PEERS:-}" ]; then
  args+=(--max-peers="${NIMBUS_MAX_PEERS}")
fi

if [ -n "${NIMBUS_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  extra=(${NIMBUS_EXTRA_ARGS})
  args+=("${extra[@]}")
fi

exec "${bin}" "${args[@]}"
