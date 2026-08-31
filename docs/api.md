# The REST API (`/v1`)

Every Semurg node exposes a plain HTTP + JSON API. It is the simplest way to use your
node from any language — `curl`, `fetch`, `requests`, anything that speaks HTTP.

- **Base URL:** your own node, `http://localhost:4000` (loopback by default; see [access.md](access.md) to reach it from another machine).
- **Try it read-only, no install:** the public demo node at `https://one.semurg.io` answers the same read endpoints.
- **Two API groups:** `/api/*` = liveness + identity (no data); `/v1/*` = the data plane (read, write, generate, memory).

Everything below is copy-pasteable and verified against a live node.

---

## Authentication

Auth is a single optional token.

| State | Behaviour |
|---|---|
| No token set on the node | Node is **open** — reads work with no credentials (this is how the public demo runs). |
| A token is set (`SEMURG_API_TOKEN`) | Every `/v1` call must present it, or gets **401**. |

Present the token either way:

```bash
curl -H "Authorization: Bearer $SEMURG_API_TOKEN" ...
# or
curl -H "x-api-key: $SEMURG_API_TOKEN" ...
```

Prove the gate:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4000/v1/whoami   # 401 without a valid token, 200 with
curl -s http://localhost:4000/v1/status | grep auth_required               # shows whether the node enforces auth
```

---

## Liveness & identity (`/api`, `/v1/status`)

```bash
curl -s http://localhost:4000/api/health
# {"ok":true,"version":"0.1.0","service":"semurg benchmark api"}

curl -s http://localhost:4000/api/version
# {"ok":true,"version":"0.1.0","service":"semurg","built_at":"...","commit":"..."}

curl -s http://localhost:4000/v1/status
# {"ok":true,"store":{"name":"user.bin","state":"open"},"writable":true,
#  "licence":{"state":"licensed"},"api":"semurg /v1 data api","auth_required":false}
```

`/api/health` returns fuller build/conveyor/model detail when you present a valid token.

---

## Reading data — `POST /v1/query`

There is **one read door**: `POST /v1/query` with an `op`. This keeps a single, batched,
belt-served path for every read (no second endpoint to drift). `op` is required.

| `op` | Body | Returns |
|---|---|---|
| `fetch` | `{"op":"fetch","ids":[<u64>,…]}` | The 64-byte containers for those ids (base64 JSON, or raw bytes — see below). |
| `resolve` | `{"op":"resolve","id":<u64>}` | The byte offset of that id. |
| `search` | `{"op":"search","needle":"<bytes>"}` | `{matches, containers_scanned, bytes_scanned}`. |
| `histogram` | `{"op":"histogram","field_offset":0..63,"buckets":1..4096}` | Bucket counts over a byte field. |
| `traverse` | `{"op":"traverse","seeds":[<u64>,…],"hops":1..32}` | `{nodes_visited, edge_hops, teps}` — a whole-graph BFS, out-of-core. |
| `vector_search` | `{"op":"vector_search","query":"<text>","k":<n>}` | Exact top-k nearest by SimHash code. |
| `similar` | `{"op":"similar","id":<u64>,"k":<n>}` | The most-similar nodes to a node. |

```bash
# fetch — as JSON base64
curl -s -X POST http://localhost:4000/v1/query -H 'content-type: application/json' \
  -d '{"op":"fetch","ids":[1,2,3]}'

# fetch — raw binary fast path: N ids -> exactly N*64 bytes, no base64
curl -s -X POST http://localhost:4000/v1/query \
  -H 'content-type: application/json' -H 'Accept: application/octet-stream' \
  -d '{"op":"fetch","ids":[1,2,3]}' --output containers.bin

# histogram
curl -s -X POST http://localhost:4000/v1/query -H 'content-type: application/json' \
  -d '{"op":"histogram","field_offset":8,"buckets":8}'

# traverse — the out-of-core deep-graph crown
curl -s -X POST http://localhost:4000/v1/query -H 'content-type: application/json' \
  -d '{"op":"traverse","seeds":[1,2,3],"hops":3}'
```

**Limits:** up to 100,000 ids per query, 100,000 seeds per traverse, 32 hops. An absent
or deleted id returns 64 zero bytes in `fetch` (never an error).

> The raw-binary variant (`Accept: application/octet-stream`) is the fast path — the container
> bytes cross the wire byte-for-byte, no base64. It replaces the older `/v1/fetch_batch` route.

---

## Writing data — `POST /v1/ingest`

Requires the `write` capability (a standalone node ships writable; the public demo is read-only,
so it answers **403** here). Two body shapes:

```bash
# (a) packed 64-byte containers, base64-encoded (up to 65,536 per request)
curl -s -X POST http://localhost:4000/v1/ingest \
  -H "Authorization: Bearer $SEMURG_API_TOKEN" -H 'content-type: application/json' \
  -d '{"containers_b64":"<base64 of packed 64*N bytes>"}'

# (b) text passages — embedded and stored server-side, then searchable/resolvable
curl -s -X POST http://localhost:4000/v1/ingest \
  -H "Authorization: Bearer $SEMURG_API_TOKEN" -H 'content-type: application/json' \
  -d '{"passages":[{"text":"Paris is the capital of France."}]}'
```

Success: `{"ok":true,"containers":N,"bytes":B,"elapsed_us":…,"containers_per_s":…}`.

---

## Generating text — `POST /v1/generate/stream` (SSE)

Server-Sent Events, one token per frame. This is the streaming door for model output
(there is no `/api/chat` — one generation endpoint).

```bash
curl -N -X POST http://localhost:4000/v1/generate/stream \
  -H 'content-type: application/json' \
  -d '{"prompt":"Explain MoE routing in one sentence.","max_tokens":64}'
# data: {"delta":"Mixture"}
# data: {"delta":"-of-experts…"}
# data: [DONE]
```

Body: `{"prompt": "...", "model": "<optional>", "max_tokens": <optional, default 256>}`.

---

## AI memory — `/v1/memory/*`

Agent memory as a knowledge graph with GraphRAG recall (write facts, recall with provenance,
relate with typed edges, forget by superseding). Writes need a token; reads are open.

```bash
curl -s http://localhost:4000/v1/memory/status

curl -s -X POST http://localhost:4000/v1/memory/remember \
  -H "Authorization: Bearer $SEMURG_API_TOKEN" -H 'content-type: application/json' \
  -d '{"scope":"team-a","content":"Paris is the capital of France."}'

curl -s -X POST http://localhost:4000/v1/memory/recall \
  -H 'content-type: application/json' \
  -d '{"scope":"team-a","query":"capital of France"}'
```

| Endpoint | Body | Auth |
|---|---|---|
| `GET /v1/memory/status` | — | open |
| `POST /v1/memory/remember` | `{scope, content\|facts, source?}` | token |
| `POST /v1/memory/recall` | `{scope, query\|subject, k?}` | open |
| `POST /v1/memory/relate` | `{scope, from, to, type}` | token |
| `POST /v1/memory/forget` | `{scope, subject, reason?}` | token |

---

## Errors & rate-limiting

Every JSON response carries `ok`. Failures look like:

```json
{"ok":false,"error":"short reason","detail":"what to do about it"}
```

with an HTTP status: **401** auth, **403** read-only / write-cap missing, **413** too large,
**422** malformed, **429** rate-limited (with `Retry-After`), **503** store/model warming, **500** engine.

A node you run yourself (`onprem`, the default) is never rate-throttled on its own box — the
guard only caps a node deployed in `public` mode.

---

Next: the [ATP wire protocol](protocols.md) for the low-latency binary path, the
[client SDKs](sdks.md) for idiomatic wrappers, or [building an extension](extensions.md)
to run your own code inside the node with zero serialization tax.
