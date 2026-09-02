#!/usr/bin/env bash
# One-shot setup: JWT, datadirs, reth snapshot, nimbus checkpoint sync.
# Safe to re-run. Existing data is left alone.
set -euo pipefail

cd "$(dirname "$0")"

RETH_IMAGE="${RETH_IMAGE:-ghcr.io/gnosischain/reth_gnosis:v2.0.0}"
NIMBUS_IMAGE="${NIMBUS_IMAGE:-ghcr.io/gnosischain/gnosis-nimbus-eth2:v26.6}"

if [ -f ./reth.env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./reth.env
  set +a
fi
if [ -f ./nimbus.env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./nimbus.env
  set +a
fi

chain="${RETH_CHAIN:-gnosis}"
node_type="${RETH_NODE_TYPE:-full}"
nimbus_network="${NIMBUS_NETWORK:-${chain}}"

datadir_empty() {
  local dir="$1"
  [ ! -d "${dir}" ] || [ -z "$(ls -A "${dir}" 2>/dev/null)" ]
}

echo "==> Ensuring docker network 'gnosis'"
docker network inspect gnosis >/dev/null 2>&1 || docker network create gnosis

echo "==> Preparing directories"
mkdir -p shared data/reth data/nimbus

if [ ! -f ./shared/jwt.hex ]; then
  echo "==> Creating Engine API JWT"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32 | tr -d '\n' > ./shared/jwt.hex
  else
    dd bs=1 count=32 if=/dev/urandom of=/dev/stdout 2>/dev/null | xxd -p -c 32 > ./shared/jwt.hex
  fi
  chmod 644 ./shared/jwt.hex
fi

# Nimbus image runs as uid 1000. Bind-mounts created as root are not writable.
if command -v chown >/dev/null 2>&1; then
  chown -R 1000:1000 data/nimbus 2>/dev/null || chmod -R a+rwX data/nimbus
else
  chmod -R a+rwX data/nimbus
fi

case "${node_type}" in
  full) snap_flag=--full ;;
  minimal) snap_flag=--minimal ;;
  archive) snap_flag=--archive ;;
  *)
    echo "unknown RETH_NODE_TYPE=${node_type} (full|minimal|archive)" >&2
    exit 1
    ;;
esac

if [ "${RETH_SNAPSHOT:-true}" = "true" ] && datadir_empty data/reth; then
  echo "==> Downloading reth ${node_type} snapshot for ${chain}"
  echo "    This is large. Keep the process running until it exits 0."
  download_args=(
    download
    --chain "${chain}"
    --datadir /data
    "${snap_flag}"
  )
  if [ -n "${RETH_SNAPSHOT_MANIFEST_URL:-}" ]; then
    download_args+=(--manifest-url "${RETH_SNAPSHOT_MANIFEST_URL}")
  fi
  docker run --rm \
    -v "$(pwd)/data/reth:/data" \
    "${RETH_IMAGE}" \
    "${download_args[@]}"
else
  echo "==> Skipping reth snapshot (disabled or data/reth is not empty)"
fi

if [ "${NIMBUS_CHECKPOINT:-true}" = "true" ] && datadir_empty data/nimbus; then
  checkpoint_url="${NIMBUS_CHECKPOINT_SYNC_URL:-https://checkpoint.gnosischain.com}"
  backfill="${NIMBUS_CHECKPOINT_BACKFILL:-false}"
  echo "==> Nimbus trusted-node sync from ${checkpoint_url}"
  docker run --rm \
    --user 1000:1000 \
    -v "$(pwd)/data/nimbus:/data" \
    "${NIMBUS_IMAGE}" \
    trustedNodeSync \
    --network="${nimbus_network}" \
    --data-dir=/data \
    --trusted-node-url="${checkpoint_url}" \
    --backfill="${backfill}" \
    --with-deposit-snapshot
else
  echo "==> Skipping nimbus checkpoint sync (disabled or data/nimbus is not empty)"
fi

echo
echo "Bootstrap complete."
echo "Start the node with:  docker compose up -d"
echo "Follow logs with:     docker compose logs -f --tail=200"
