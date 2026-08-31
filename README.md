# Semurg-Install

The official one-command installer for **Semurg** — the universal operating system for intelligence: one
platform where your data, models, and agents run on a single copy on your own hardware. It downloads and
runs the released Semurg engine on your own machine. **Your first node is always free** — install it, load
your own data, and query it the moment it lands.

This repository is the **installer only** (a small, verifiable bootstrap script). It does **not** contain
the engine source. The engine is downloaded, checksum-verified, from the official release channel.

---

## What you are installing

A single 64-byte container that is at once the database record, the index entry, the log entry, and the
network frame — one store, one copy of your data, queryable immediately through **graph, search, vector,
key-value, analytics, and time-series** lenses. The engine is native (deep-queue O_DIRECT + io_uring,
AVX-512 kernels where the CPU has them) and ships prebuilt — no compiler, no Rust, no separate Erlang.

The install gives you:

- the native engine,
- a **web console on port 4000**,
- the **`/v1` data API** for loading and querying your own data (calls need an
  `Authorization: Bearer <token>` — the installer prints the token in its SUCCESS banner),
- `/api/health` and `/api/version` for liveness and build provenance.

The node comes up with a small **Panama Papers demo graph preloaded**, so you have something to query
immediately (pass `SEMURG_PRELOAD_PANAMA=0` at install to start empty). You load your own data through `/v1`.
Benchmarks live in the separate [Semurg-Benchmark-Suite](https://github.com/One-Semurg/Semurg-Benchmark-Suite).

---

## Requirements

| Requirement | Minimum | Notes |
|---|---|---|
| OS | **Ubuntu 24.04 LTS** | 22.04 needs a separate build (preflight tells you plainly) |
| glibc | 2.38+ | 24.04 ships 2.39 |
| Architecture | **x86_64** (amd64) | **AMD and Intel both work** (the installer auto-picks the AVX-512 / AVX2 / generic engine variant for your CPU). Apple Silicon / Mac ARM (**arm64**) is **not supported yet** |
| CPU | 4 physical cores | shards map 1:1 to physical cores |
| RAM | 8 GB | residency budget derives from this |
| Free disk | 20 GB | more is better (the store is a value log) |
| Privilege | root (`sudo`) | installs a systemd unit |

Recommended for the fast path: an AVX-512 CPU (Zen 4/5, Ice Lake or newer), NVMe SSD(s) — the engine
stripes shards across every NVMe disk it finds — and 32 GB+ RAM.

---

## Install

**Option A — the bootstrap script (recommended).** Read it, then run it. It fetches the current release
manifest, verifies the bundle's sha256, unpacks it, and runs the bundled installer:

```bash
curl -fsSLO https://raw.githubusercontent.com/One-Semurg/Semurg-Install/main/install.sh
less install.sh          # read before you run
sudo bash install.sh
```

**Option B — the explicit, verified steps** (version-agnostic; always installs the current release):

```bash
curl -fsSL https://one.semurg.io/dl/LATEST.json -o LATEST.json
URL=$(grep -oE '"installer_url"[^,]*' LATEST.json | cut -d'"' -f4)
SHA=$(grep -oE '"sha256"[^,]*'        LATEST.json | cut -d'"' -f4)
curl -fsSLO "$URL"
echo "$SHA  $(basename "$URL")" | sha256sum -c -      # must print: OK
tar xzf "$(basename "$URL")" && cd semurg_installer
sudo ./semurg-install.sh
```

The installer is idempotent (safe to re-run) and fails with a plain-English reason, never a stack trace.
You will see seven steps: **preflight → hardware scan → dependencies → engine → configure → license → start & verify**.

---

## Not on Ubuntu? Install with Docker

The bare-metal Ubuntu installer above is the **primary** path — it gives the full deep-queue O_DIRECT
performance. If you are on **Windows, macOS (Intel), or another Linux distro**, run Semurg in Docker
instead:

```bash
curl -fsSLO https://one.semurg.io/dl/semurg-docker.tar.gz
tar xzf semurg-docker.tar.gz && cd semurg-docker
docker compose up
```

`docker compose up` supplies the three capabilities the engine needs (`memlock` unlimited,
`seccomp=unconfined`, a data volume). Then open the health check at
<http://127.0.0.1:4100/api/health> (compose maps container `:4000` → host loopback `:4100`).

**On Windows (Intel/AMD):** install [Docker Desktop](https://www.docker.com/products/docker-desktop/) —
on first run it enables **WSL2** for you (one reboot), so there is **no separate Ubuntu to install** and
no Linux distro to configure by hand; Docker Desktop bundles and manages its own WSL2 Linux VM. Then open
the **WSL2 (Ubuntu) terminal** Docker Desktop provides and run the three lines above. A Windows PC is
x86_64, so the amd64 image runs at **native speed through WSL2** — not emulated. **Intel Macs** use the
same Docker steps in a normal terminal.

> **x86_64 only — no Mac ARM.** The image is amd64 and the engine's kernels are AVX2 / AVX-512 (with a
> `generic` x86_64 floor), so it runs on **AMD and Intel**. **Apple Silicon (Mac ARM / arm64) is not
> supported** — even under Docker the amd64 image would run emulated, without the native IO path; an arm64
> build is not available yet.

Docker gives you the data console + `/v1` API. For the **admin cluster UI**, the bare-metal install is
recommended (it provisions the fail-closed TLS admin console described next).

---

## Start & access the admin cluster UI

The installer registers and starts a systemd unit, so the engine is already running when it finishes.
There are **two** surfaces:

**1. The data console + API — port 4000 (HTTP).** Where you load and query your own data.
- Web console: `http://<this-host>:4000` (locally `http://localhost:4000`)
- Data API: `http://<this-host>:4000/v1`  ·  health: `http://<this-host>:4000/api/version`

**2. The admin cluster UI — port 4610 (HTTPS, loopback-only).** The operator console for the cluster.
It is **fail-closed and provisioned automatically during install** (you do not run anything by hand). At
the end of the install, the green **`SUCCESS — Semurg is running`** banner prints everything you need —
**copy it then; it is shown once** — and it is also saved to **`/opt/semurg/tmp/.admin_bootstrap_banner`**:

```
Console URL : https://127.0.0.1:4610/cluster   (loopback-only)
SSH tunnel  : ssh -N -L 4610:127.0.0.1:4610 root@<your-server>   then open  https://localhost:4610/cluster
Admin secret (one-time; type into the unlock form): ********
```

> ⚠️ **Save the admin secret now — it is shown only ONCE.** Semurg stores only a *hash* of it; the
> plaintext exists only in this banner and the saved banner file
> (`/opt/semurg/tmp/.admin_bootstrap_banner`). If you lose both, you must re-mint it with
> `SEMURG_ADMIN_REPROVISION=1`. Copy it somewhere safe before you close the terminal.

To reach it:
- **On the box:** open `https://127.0.0.1:4610/cluster` (accept the self-signed cert).
- **Remotely:** it is loopback-bound for safety, so tunnel first —
  ```bash
  ssh -N -L 4610:127.0.0.1:4610 root@<your-server>
  ```
  then open `https://localhost:4610/cluster` in your browser.
- **Log in:** enter the one-time **admin secret** from the banner. If two-factor **TOTP** is enabled (the
  banner will then also show a TOTP secret), add that secret to your authenticator app — Google
  Authenticator, Authy, 1Password, … — and complete the code.

**Where do I get the secret / did I miss it?**
- It is in the **`SUCCESS`** banner at the end of the install — copy it there.
- Missed it or closed the terminal? Re-read the saved banner anytime:
  ```bash
  sudo cat /opt/semurg/tmp/.admin_bootstrap_banner
  ```
- Not sure of the URL? Open the plain-HTTP **signpost** `http://<this-host>:4000/cluster-admin` — it tells
  you the reachable admin path.
- Lost it entirely? Mint fresh credentials: re-run the install with `SEMURG_ADMIN_REPROVISION=1`.

Other knobs: skip the admin portal at install with `SEMURG_ADMIN_PORTAL=0`; change the port/bind with
`SEMURG_ADMIN_PORT` / `SEMURG_ADMIN_BIND`.

**Manage the service:**
```bash
sudo systemctl status semurg     # is it running?
sudo systemctl restart semurg    # restart
journalctl -u semurg -f          # follow logs
```

Your admin console is entirely **yours and local** — the loopback `:4610/cluster` above, on your own
hardware. There is no third-party or hosted dependency.

---

## Load and query your own data

```bash
# health / version — no auth needed
curl -s http://localhost:4000/api/version

# /v1 data API — needs your token (shown in the install SUCCESS banner; also in /etc/semurg/semurg.env)
TOKEN=<your-token>
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:4000/v1/status
# ...then ingest + query the same way. The web console gives you all of this through the browser.
```

The web console gives you the same capability through the browser: ingest a source, watch it land, and
query it through any lens. Full, copy-pasteable detail for every surface is in the documentation below.

---

## Documentation

Once your node is running, these guides cover every way to use it — all copy-pasteable, and honest
about what is live today:

| Guide | What it covers |
|---|---|
| **[docs/api.md](docs/api.md)** | The REST `/v1` API — read (`query`), write (`ingest`), generate (SSE), AI memory, auth, errors. **Start here.** |
| **[docs/protocols.md](docs/protocols.md)** | The wire protocols — the ATP binary fast path for low-latency reads, SSE streaming, and what the WebSocket actually is. |
| **[docs/sdks.md](docs/sdks.md)** | Client libraries for 11 languages, plus the "just use HTTP" path that works from anywhere today. |
| **[docs/extensions.md](docs/extensions.md)** | Tiers (Core / Extensions / Integrations), how to build your own extension, and the zero-serialization bare-metal pattern. |
| **[docs/access.md](docs/access.md)** | Reaching the data plane and the admin console from another machine (SSH tunnels, exposing safely). |

---

## Reproduce the benchmarks

Semurg's benchmark harness is a separate, run-it-yourself public repository —
**[Semurg-Benchmark-Suite](https://github.com/One-Semurg/Semurg-Benchmark-Suite)**. It runs Semurg and
leading databases side by side on **your** hardware, with equal-answer gates, so the numbers are yours.

---

## Licensing

- The **installer scripts in this repository** are Apache-2.0 (see [LICENSE](LICENSE)).
- The **Semurg engine** they download is separately licensed: your **first node is free forever** for
  development and testing. Additional nodes are licensed per node. See <https://one.semurg.io>.

---

## Links

- Product & downloads: <https://one.semurg.io>
- Benchmark suite: <https://github.com/One-Semurg/Semurg-Benchmark-Suite>
