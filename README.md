# gnosis-node
  
Docker Compose full node for [Gnosis Chain](https://docs.gnosischain.com/node): **reth** (execution) + **nimbus** (consensus).

## System requirements

From the [Gnosis node docs](https://docs.gnosischain.com/node):

- CPU with at least 4 threads
- At least 16 GB RAM
- 1 TB+NVMe SSD preferred (SATA SSD acceptable)
- Unmetered or high-cap network

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

`bootstrap.sh` records a completion marker for each bootstrap step. Stop the
stack (`docker compose down`) before bootstrapping.

An interrupted reth download resumes on the next run. Nimbus checkpoint data is
staged under `data/.nimbus-checkpoint.*` and moved into `data/nimbus` only after
a successful sync. Leftover staging dirs from a failed run are deleted on the
next checkpoint attempt.

To skip either reth snapshot restore and nimbus checkpoint sync steps:

```bash
RETH_SNAPSHOT=false NIMBUS_CHECKPOINT=false ./bootstrap.sh
```

To force a re-download, stop the stack, remove the relevant datadir (including its
completion marker), and re-run bootstrap:

```bash
docker compose down
rm -rf data/reth            # or data/nimbus
./bootstrap.sh
docker compose up -d
```

## Operating

```bash
docker compose logs -f --tail=200 reth
docker compose logs -f --tail=200 nimbus
```

### Reload config

Client flags are env files mapped by `scripts/*.sh`. After editing `reth.env` or `nimbus.env`:

```bash
docker compose up -d
```

### Memory tuning

`reth.toml` (mounted read-only, selected by `RETH_CONFIG` in `reth.env`) is
merged over reth's built-in defaults; unset keys keep theirs. It exists because
reth also writes a `reth.toml` **inside the datadir**, which is gitignored and
regenerated with upstream defaults whenever the datadir is wiped.

It currently lowers the execution-stage commit thresholds. Reth buffers state
changes in memory until one trips, and the upstream defaults
(`max_cumulative_gas` 1.5 Tgas, `max_duration` 10m) are sized for a much larger
machine: at ~1 Ggas/s that accumulates hundreds of Ggas before committing, which
grew reth to 29 GB RSS and OOM-killed a 30 GB host mid-sync.

When reth exhausts host memory the whole box wedges rather than just reth
dying - sshd accepts TCP but never sends a banner, journald hits its watchdog,
tailscale goes quiet - and recovery needs an out-of-band reboot. It looks
exactly like a disk fault. Check for it with:

```bash
journalctl -b -1 -p err | grep -i "out of memory"
```

On a host with substantially more RAM these can be raised; the tradeoff is
throughput, since every commit is a pause. Restarting reth resumes from the last
committed checkpoint, losing only the uncommitted window - but do not restart
while RSS is already near the ceiling, because the graceful shutdown has to
flush the whole buffer and can itself tip the host over.

### Update images

Bump the tags in `docker-compose.yaml` (and the matching defaults at the top of `bootstrap.sh` if you will re-bootstrap), then:

```bash
docker compose pull
docker compose up -d
```

### Optional HTTPS

Domains are read from `caddy/.env` (gitignored), so host-specific names stay out
of git:

```bash
cd caddy
cp .env.example .env
vi .env                 # RPC_DOMAIN, WS_DOMAIN, BEACON_DOMAIN
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
