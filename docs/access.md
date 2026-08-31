# Accessing your node & the admin console

A Semurg node has two surfaces:

| Surface | Address | For |
|---|---|---|
| **Data plane** — the `/v1` API + web console | `http://<node>:4000` | Loading and querying data — the everyday product surface. |
| **Admin console** — the cluster operator UI | `https://127.0.0.1:4610/cluster` | Operating the node: health, the 8 operator views, controls. |

By default both bind to **loopback** on the machine that runs the node — nothing is exposed to
the network until you choose to expose it. That is the point: your node is private until you open
a door.

---

## Reach the data plane

On the box itself:

```bash
curl -s http://localhost:4000/v1/status
```

From another machine, forward the port over SSH (no need to expose port 4000 publicly):

```bash
ssh -N -L 4000:127.0.0.1:4000 you@YOUR_NODE
# then, locally:
curl -s http://localhost:4000/v1/status
```

To expose the data API on the network deliberately, set `SEMURG_BIND=0.0.0.0` and put a token on
the node (`SEMURG_API_TOKEN`) so it isn't an open write target. See [api.md](api.md#authentication).

---

## Reach the admin console

The admin console is **loopback-only, HTTPS (self-signed), and fail-closed** — it will not serve
without a provisioned secret + TOTP, and it is never on the public host. Reach it by forwarding
its port over SSH:

```bash
ssh -N -L 4610:127.0.0.1:4610 you@YOUR_NODE
```

Leave that running, then open in your browser:

```
https://localhost:4610/cluster
```

Accept the self-signed certificate the first time (it is your own node's certificate).

> Forgot the path? `http://<node>:4000/cluster-admin` prints the reachable admin address and the
> exact SSH one-liner.

### Log in

1. Enter the **one-time admin secret** (shown once, at install).
2. Complete **TOTP** with the code from your authenticator app (enrolled from the TOTP secret
   shown at install).

### If you've lost the secret

The plaintext secret is shown **once** at install; only a hash is kept on disk afterwards, so it
can't be read back. Mint fresh credentials by re-provisioning on the node — this prints a new
one-time secret + TOTP secret and does not weaken any hardening:

```bash
ssh you@YOUR_NODE
export SEMURG_ADMIN_REPROVISION=1
# re-run the installer's admin bootstrap (provision-admin.sh), then restart the gateway:
sudo systemctl restart semurg-gw
```

Enroll the new TOTP secret in your authenticator and log in with the new one-time secret.

---

## Manage the node

```bash
systemctl status semurg-gw       # the service that runs the node + admin console
journalctl -u semurg-gw -f       # follow its logs
```

Admin knobs (in the node's admin env file):

| Variable | Meaning | Default |
|---|---|---|
| `SEMURG_ADMIN_PORTAL` | admin console on/off | `1` (on) |
| `SEMURG_ADMIN_PORT` | console port | `4610` |
| `SEMURG_ADMIN_BIND` | bind address | `127.0.0.1` (loopback) |
| `SEMURG_ADMIN_REPROVISION` | set `1` + re-run bootstrap to mint fresh credentials | — |

---

## Security notes

- The admin console is loopback-bound on purpose — the SSH tunnel is the intended (and only)
  remote access path. Don't change `SEMURG_ADMIN_BIND` to `0.0.0.0` without your own auth/TLS
  proxy in front.
- Credentials are per-node — each node has its own secret + TOTP.
- The one-time secret is never persisted in the clear. Save it somewhere safe when you first see it.
