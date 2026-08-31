# Wire protocols: ATP, SSE, WebSocket

Semurg speaks to clients three ways. Pick by what you need:

| You want… | Use | Where |
|---|---|---|
| The simplest thing that works, from any language | **HTTP / REST** | [api.md](api.md) |
| The lowest latency for high-rate reads on-box | **ATP** (binary wire, TCP 4064) | below |
| A token stream from the model | **SSE** (`POST /v1/generate/stream`) | below |
| To drive the built-in web console | **WebSocket** (LiveView) | below — *not* a programmatic data API |

---

## ATP — the Atomic Transfer Protocol (binary wire)

ATP is Semurg's native transport for the `/v1` **read** data plane. A client opens **one
authenticated TCP socket** and carries reads as a stream of **64-byte frames** — no HTTP
request line, no headers, no JSON or base64 on the container path. It is the same data core
the REST `/v1` endpoint uses, so answers are byte-identical; you just skip the HTTP tax.

**Why it is faster:** HTTP pays a connect + header parse + JSON/base64 marshal on every call.
ATP reuses one socket and moves raw 64-byte frames. Measured against a live node:

```
                 HTTP        ATP        speedup
  BATCH FETCH    210.6 us    74.3 us    2.83x
  POINT QUERY    138.5 us     8.2 us    16.9x     (HTTP pays a full connect per request)
```

**Where it listens:** `127.0.0.1:4064` by default — loopback only. A node answers ATP on-box
or over an SSH tunnel, never on a public interface by accident. Exposing it on a non-loopback
address is opt-in **and** refuses to start unless a token is set (fail-closed).

**How a session goes:**

```
client                                  server
  |-- AUTH (token) ------------------->  |   first frame MUST be AUTH
  |<-- AUTH_OK ------------------------  |
  |-- fetch_batch (packed ids) ------->  |
  |<-- N*64 container bytes -----------  |
  |-- resolve (id) ------------------->  |
  |<-- offset -------------------------  |
  |   ... one socket, many ops ...       |
```

**Ops:** `status`, `fetch` / `fetch_batch`, `resolve`, `search`, `histogram`. Each frame is a
legal 64-byte container with a CRC-32C integrity field; a torn or spoofed frame is rejected
before dispatch. Writes (`/v1/ingest`) and the `/api` liveness plane always ride HTTP.

**Speaking it:** the **Rust** and **Elixir** SDKs implement the full ATP transport today (see
[sdks.md](sdks.md)); both are transport-transparent — the same call returns the same result over
ATP or HTTP, so you develop on HTTP and flip a switch for the fast path:

```rust
let c = semurg::Client::new("http://127.0.0.1:4000")
    .with_token("YOUR_TOKEN")
    .with_transport(semurg::Transport::Atp);   // or .prefer_atp() to auto-detect
let bytes = c.fetch_batch(&[1, 2, 3])?;         // N*64 raw container bytes, over one socket
```

```elixir
c = Semurg.new("http://127.0.0.1:4000", transport: :atp, token: "YOUR_TOKEN")
{:ok, bytes} = Semurg.fetch_batch(c, [1, 2, 3])
```

**Config knobs:** `SEMURG_ATP_ENABLED` (default `1`), `SEMURG_ATP_PORT` (`4064`),
`SEMURG_ATP_BIND` (`127.0.0.1`), `SEMURG_ATP_EXPOSE` (bind `0.0.0.0`, still token-gated),
`SEMURG_ATP_IDLE_MS` (`120000`).

---

## SSE — streaming model output

`POST /v1/generate/stream` returns `text/event-stream`: one `data: {"delta":"…"}` frame per
token, ending with `data: [DONE]`. Any HTTP client that reads a chunked response can consume it
(`curl -N`, `EventSource` in a browser, a streaming HTTP client in your language). See
[api.md](api.md#generating-text--post-v1generatestream-sse).

---

## WebSocket — the web console (be precise about this)

The only WebSocket on a Semurg node is the **Phoenix LiveView socket** that drives the built-in
server-rendered web console/UI (`/live/websocket`). It is not a programmatic data channel: there
is **no** WebSocket data API or channel for clients to call, and every SDK's `ws` transport
raises a `Roadmap` error for data verbs on purpose (the SDKs never fake a wire).

**So, for programmatic real-time / streaming, use:**

- **SSE** (`/v1/generate/stream`) for model token streams, or
- **ATP** (above) for low-latency reads.

If you are wiring a browser UI directly, the LiveView socket is at `/live/websocket?vsn=2.0.0`;
the SDKs expose `socket_url` / `join_message` helpers for that handshake.

---

Next: the [client SDKs](sdks.md), or the [REST reference](api.md).
