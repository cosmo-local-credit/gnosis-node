#!/usr/bin/env bash
# One-shot setup: JWT, datadirs, reth snapshot, nimbus checkpoint sync.
# Safe to re-run. Successful bootstrap steps are recorded with completion markers.
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

service_running() {
  local id
  id="$(docker compose ps -q "$1" 2>/dev/null || true)"
  [ -n "${id}" ] && [ "$(docker inspect -f '{{.State.Running}}' "${id}" 2>/dev/null || true)" = "true" ]
}

require_service_stopped() {
  local name="$1"
  if service_running "${name}"; then
    echo "error: ${name} is running; stop the stack before bootstrapping:" >&2
    echo "  docker compose down" >&2
    exit 1
  fi
}

# Nimbus image runs as uid 1000. Bind-mounts created as root are not writable.
make_nimbus_writable() {
  local dir="$1"
  if command -v chown >/dev/null 2>&1; then
    chown -R 1000:1000 "${dir}" 2>/dev/null || chmod -R a+rwX "${dir}"
  else
    chmod -R a+rwX "${dir}"
  fi
}

cleanup_nimbus_staging() {
  local leftover
  shopt -s nullglob
  for leftover in data/.nimbus-checkpoint.*; do
    echo "==> Removing leftover checkpoint staging ${leftover}"
    rm -rf "${leftover}"
  done
  shopt -u nullglob
}

# Move a completed checkpoint dir into data/nimbus. Prefer replacing the
# directory; if it is a busy bind-mount, move contents into the mount instead.
install_staged_nimbus_datadir() {
  local staging="$1"
  local dest="data/nimbus"

  if [ -e "${dest}" ] && ! datadir_empty "${dest}"; then
    echo "error: ${dest} is no longer empty; leaving staging at ${staging}" >&2
    exit 1
  fi

  mkdir -p "${dest}"
  if rmdir "${dest}" 2>/dev/null; then
    mv "${staging}" "${dest}"
    return
  fi

  if ! datadir_empty "${dest}"; then
    echo "error: ${dest} became non-empty during swap; leaving staging at ${staging}" >&2
    exit 1
  fi

  # Busy empty mount point: move hidden and regular files, never . or ..
  shopt -s dotglob nullglob
  mv "${staging}"/* "${dest}"/
  shopt -u dotglob nullglob
  rmdir "${staging}"
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

make_nimbus_writable data/nimbus

case "${node_type}" in
  full) snap_flag=--full ;;
  minimal) snap_flag=--minimal ;;
  archive) snap_flag=--archive ;;
  *)
    echo "unknown RETH_NODE_TYPE=${node_type} (full|minimal|archive)" >&2
    exit 1
    ;;
esac

reth_snapshot_marker=data/reth/.bootstrap-snapshot-complete
if [ "${RETH_SNAPSHOT:-true}" != "true" ]; then
  echo "==> Skipping reth snapshot (disabled)"
elif [ -f "${reth_snapshot_marker}" ]; then
  echo "==> Skipping reth snapshot (already completed)"
elif [ -f data/reth/reth.toml ]; then
  echo "==> Skipping reth snapshot (existing reth datadir without bootstrap marker)"
else
  require_service_stopped reth
  echo "==> Downloading or resuming reth ${node_type} snapshot for ${chain}"
  echo "    This is large. Keep the process running until it exits 0."
  download_args=(
    download
    --chain "${chain}"
    --datadir /data
    --resumable
    "${snap_flag}"
  )
  if [ -n "${RETH_SNAPSHOT_MANIFEST_URL:-}" ]; then
    download_args+=(--manifest-url "${RETH_SNAPSHOT_MANIFEST_URL}")
  fi
  docker run --rm \
    -v "$(pwd)/data/reth:/data" \
    "${RETH_IMAGE}" \
    "${download_args[@]}"
  touch "${reth_snapshot_marker}"
fi

nimbus_checkpoint_marker=data/nimbus/.bootstrap-checkpoint-complete
if [ "${NIMBUS_CHECKPOINT:-true}" != "true" ]; then
  echo "==> Skipping nimbus checkpoint sync (disabled)"
elif [ -f "${nimbus_checkpoint_marker}" ]; then
  echo "==> Skipping nimbus checkpoint sync (already completed)"
elif ! datadir_empty data/nimbus; then
  echo "==> Skipping nimbus checkpoint sync (existing datadir without bootstrap marker)"
else
  require_service_stopped nimbus
  checkpoint_url="${NIMBUS_CHECKPOINT_SYNC_URL:-https://checkpoint.gnosischain.com}"
  backfill="${NIMBUS_CHECKPOINT_BACKFILL:-false}"
  cleanup_nimbus_staging
  checkpoint_staging_dir="$(mktemp -d data/.nimbus-checkpoint.XXXXXX)"
  make_nimbus_writable "${checkpoint_staging_dir}"
  echo "==> Nimbus trusted-node sync from ${checkpoint_url}"
  echo "    Staging checkpoint data in ${checkpoint_staging_dir} until it completes."
  docker run --rm \
    --user 1000:1000 \
    -v "$(pwd)/${checkpoint_staging_dir}:/data" \
    "${NIMBUS_IMAGE}" \
    trustedNodeSync \
    --network="${nimbus_network}" \
    --data-dir=/data \
    --trusted-node-url="${checkpoint_url}" \
    --backfill="${backfill}" \
    --with-deposit-snapshot
  install_staged_nimbus_datadir "${checkpoint_staging_dir}"
  touch "${nimbus_checkpoint_marker}"
fi

echo
echo "Bootstrap complete."
echo "Start the node with:  docker compose up -d"
echo "Follow logs with:     docker compose logs -f --tail=200"
