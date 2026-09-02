# gnosis-node

Docker Compose full node for [Gnosis Chain](https://docs.gnosischain.com/node): **reth** (execution) + **nimbus** (consensus).

Layout matches [cel2-node](https://github.com/grassrootseconomics/cel2-node): one compose file, env-only client config, a bootstrap script for first-time data. Change an env file (or an image tag) and reload.

This stack is a **full node**, not a validator. There is no validator client and no keystores.

## System requirements

From the [Gnosis node docs](https://docs.gnosischain.com/node):

- CPU with at least 4 threads
- At least 16 GB RAM
- NVMe SSD preferred (SATA SSD acceptable)
- Unmetered or high-cap network

A reth **full** snapshot plus nimbus checkpoint data is hundreds of GB and grows. Plan on **1.5 TB+** free NVMe so download, extract, and later growth all fit.

## Features

- Reth `--full` + official snapshot restore (`reth download`)
- Nimbus trusted-node / checkpoint sync so the beacon node does not sync from genesis
- Env-only client flags (`reth.env`, `nimbus.env`)
- Engine API JWT generated once and shared
- RPC/WS/metrics bound to localhost; P2P ports public
- Optional Caddy reverse proxy

## Firewall

Allow inbound:

- `30303/tcp` and `30303/udp` (reth P2P)
- `9000/tcp` and `9000/udp` (nimbus P2P)
- `80/tcp` and `443/tcp` if you use `caddy/`

RPC (`8545`), WS (`8546`), Engine API (`8551`), and Beacon REST (`5052`) are published on `127.0.0.1` only.

## Setup

Assumes Ubuntu/Debian. Keep time in sync; consensus clients are sensitive to clock drift.

```bash
apt update && apt upgrade --yes
apt install curl chrony git openssl xxd
curl -fsSL https://get.docker.com | bash

cd gnosis-node

# Review / edit client config (mainnet is the default)
vi reth.env
vi nimbus.env

# JWT, datadirs, reth snapshot, nimbus checkpoint
./bootstrap.sh

# Start EL + CL
docker compose up -d
```

`bootstrap.sh` is idempotent. It skips snapshot/checkpoint work when `data/reth` or `data/nimbus` already contain files.

### Snapshot restore

Reth does not snap-sync from peers the way geth does. Without a snapshot it executes from genesis, which takes days. Bootstrap runs:

```text
reth download --chain gnosis --full --datadir /data \
  --manifest-url https://reth-snapshots.gnosischain.com/latest/gnosis/manifest.json
```

That is the official path from [reth_gnosis](https://github.com/gnosischain/reth_gnosis): presets `minimal`, `full`, `archive`. This project defaults to **full**.

Nimbus then runs `trustedNodeSync` against `https://checkpoint.gnosischain.com` with `--backfill=false`, so it can follow head in minutes and fill historical blocks from the p2p network afterwards. See [Nimbus trusted node sync](https://nimbus.guide/trusted-node-sync.html).

To skip either step:

```bash
RETH_SNAPSHOT=false NIMBUS_CHECKPOINT=false ./bootstrap.sh
```

To force a re-download, stop the stack, wipe the datadir, and re-run bootstrap:

```bash
docker compose down
rm -rf data/reth/*          # or data/nimbus/*
./bootstrap.sh
docker compose up -d
```

## Operating

```bash
docker compose logs -f --tail=200 reth
docker compose logs -f --tail=200 nimbus
```

Sync checks:

```bash
# Execution: `false` means not syncing (at head). An object means still catching up.
curl -s -X POST http://127.0.0.1:8545 \
  -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

curl -s -X POST http://127.0.0.1:8545 \
  -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Consensus
curl -s http://127.0.0.1:5052/eth/v1/node/syncing
curl -s http://127.0.0.1:5052/eth/v1/node/peer_count
```

After a checkpoint sync, compare the beacon head with another source:

```bash
curl -s http://127.0.0.1:5052/eth/v1/beacon/blocks/head/root
curl -s https://checkpoint.gnosischain.com/eth/v1/beacon/genesis
```

### Reload config

Client flags are env files mapped by `scripts/*.sh`. After editing `reth.env` or `nimbus.env`:

```bash
docker compose up -d
```

### Update images

Bump the tags in `docker-compose.yaml` (and the matching defaults at the top of `bootstrap.sh` if you will re-bootstrap), then:

```bash
docker compose pull
docker compose up -d
```

Current pins:

- Execution: `ghcr.io/gnosischain/reth_gnosis:v2.0.0`
- Consensus: `ghcr.io/gnosischain/gnosis-nimbus-eth2:v26.6`

Official docs: [Reth](https://docs.gnosischain.com/node/manual/execution/reth), [Nimbus](https://docs.gnosischain.com/node/manual/beacon/nimbus).

### Optional HTTPS

```bash
# edit caddy/Caddyfile with your domain
cd caddy
docker compose up -d
```

## Chiado testnet

In `reth.env`:

```bash
RETH_CHAIN=chiado
RETH_SNAPSHOT_MANIFEST_URL=https://reth-snapshots.gnosischain.com/latest/chiado/manifest.json
```

In `nimbus.env`:

```bash
NIMBUS_NETWORK=chiado
NIMBUS_CHECKPOINT_SYNC_URL=https://checkpoint.chiadochain.net
```

Then `./bootstrap.sh` and `docker compose up -d`.

## Layout

```text
.
├── docker-compose.yaml   # images, ports, volumes
├── reth.env              # execution client
├── nimbus.env            # consensus client
├── bootstrap.sh          # JWT + snapshot + checkpoint
├── scripts/              # env → CLI flags
├── shared/               # jwt.hex (created, gitignored)
├── data/reth             # execution datadir
├── data/nimbus           # consensus datadir
└── caddy/                # optional reverse proxy
```

## License

MIT. Client images remain under their upstream licenses.
