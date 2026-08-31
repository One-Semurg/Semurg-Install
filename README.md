# Semurg-Install

The official one-command installer for **Semurg**. It downloads and runs the released Semurg engine on
your own machine. **Your first node is always free** — install it, load your own data, and query it the
moment it lands.

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
- the **`/v1` data API** for loading and querying your own data,
- the **`/api` benchmark API**, so you can reproduce results on your own hardware.

A fresh node starts empty; you load your own data through `/v1`.

---

## Requirements

| Requirement | Minimum | Notes |
|---|---|---|
| OS | **Ubuntu 24.04 LTS** | 22.04 needs a separate build (preflight tells you plainly) |
| glibc | 2.38+ | 24.04 ships 2.39 |
| Architecture | x86_64 (amd64) | arm64 not yet built |
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
You will see seven steps: **preflight → hardware scan → dependencies → engine → service → verify → done**.

---

## Start & access the admin console

The installer registers and starts a systemd unit, so the engine is already running when it finishes.

- **Web console / admin UI:** `http://<this-host>:4000` (locally, `http://localhost:4000`).
- **Set up admin + TOTP:** from the unpacked `semurg_installer/` directory, run:
  ```bash
  sudo ./provision-admin.sh
  ```
  This provisions the administrator and its TOTP (time-based one-time-password) login, then you sign in
  to the console.
- **Manage the service:**
  ```bash
  sudo systemctl status semurg     # is it running?
  sudo systemctl restart semurg    # restart
  journalctl -u semurg -f          # follow logs
  ```

A **hosted** console for the reference cluster runs at `https://cluster.semurg.io`; your own node's
console is the `:4000` above.

---

## Load and query your own data

```bash
# health / version
curl -s http://localhost:4000/api/version

# load and query through the /v1 data API (see the console for the interactive surface)
```

The web console gives you the same capability through the browser: ingest a source, watch it land, and
query it through any lens.

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
