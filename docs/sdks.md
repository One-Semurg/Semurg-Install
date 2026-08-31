# Client SDKs

You never *need* an SDK — Semurg's data plane is plain HTTP + JSON, so any language talks to a
node today with its standard library. The official SDKs are thin, idiomatic convenience wrappers
over that same API.

---

## The universal path: HTTP from any language

Every example here hits your own node at `http://localhost:4000`.

```python
# Python (stdlib) — no dependency
import json, urllib.request
def query(op, **args):
    body = json.dumps({"op": op, **args}).encode()
    req = urllib.request.Request("http://localhost:4000/v1/query", body,
                                 {"content-type": "application/json"})
    return json.load(urllib.request.urlopen(req))
print(query("histogram", field_offset=8, buckets=8))
```

```javascript
// JavaScript (fetch) — browser or Node, no dependency
const r = await fetch("http://localhost:4000/v1/query", {
  method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ op: "histogram", field_offset: 8, buckets: 8 }),
});
console.log(await r.json());
```

```go
// Go (net/http) — no dependency
body := strings.NewReader(`{"op":"histogram","field_offset":8,"buckets":8}`)
resp, _ := http.Post("http://localhost:4000/v1/query", "application/json", body)
io.Copy(os.Stdout, resp.Body)
```

For auth, add an `Authorization: Bearer <token>` header. That's the whole integration story for
most apps — see the full endpoint list in [api.md](api.md).

---

## Official libraries (11 languages)

Idiomatic wrappers with the same method surface in every language:

| Language | HTTP stack | 3rd-party deps |
|---|---|---|
| **Rust** | hand-rolled HTTP/1.1 + rustls | serde_json, rustls |
| **Elixir** | `:httpc` (OTP) | none |
| Go | `net/http` | none |
| Java | `java.net.http` (JDK 11+) | none |
| C# / F# | `HttpClient` (BCL) | none |
| C++ | hand-rolled sockets | none |
| Erlang | `httpc` | none |
| OCaml | Unix sockets (+ optional TLS) | none |
| Julia | `Downloads` | none |
| Python | `urllib` | none |

Shared methods (per-language idiom): `health`, `status`, `query(op, args)` and its wrappers
`fetch` / `resolve` / `search` / `histogram`, and `ingest` (with a write token). Return
convention follows each language (Rust `Result<Value>`, Elixir `{:ok, term} | {:error, …}`,
Go `(value, error)`, Java `Map`, and so on).

### Transports, honestly

Each SDK can speak more than one transport, and the SDKs never fake one they don't have:

| Transport | Status |
|---|---|
| **HTTP** | Live in **all** languages. The working default — start here. |
| **ATP** (binary TCP wire, low latency) | Fully implemented in **Rust** and **Elixir** (loopback / SSH-tunnel). The other SDKs carry the frame codec but return a `Roadmap` error for ATP data ops. |
| **WebSocket** data verbs | `Roadmap` everywhere — the node's WebSocket is the web console, not a data API. See [protocols.md](protocols.md). |

---

## Rust

```toml
# Cargo.toml
[dependencies]
semurg = { path = "clients/rust" }   # ships with your node
```

```rust
use semurg::Client;

let c = Client::new("http://localhost:4000");        // your own node
let health = c.health()?;                             // GET  /api/health
let status = c.status()?;                             // GET  /v1/status
let hist   = c.histogram(8, 16)?;                     // POST /v1/query op=histogram
let found  = c.search("abc")?;                        // POST /v1/query op=search

// authenticated write:
let w = Client::new("http://localhost:4000").with_token(std::env::var("SEMURG_TOKEN")?);
w.ingest(serde_json::json!({ "passages": [{ "text": "Paris is the capital of France." }] }))?;

// low-latency binary reads over ATP (same call, faster wire):
let fast = Client::new("http://localhost:4000").with_token("TOKEN").prefer_atp();
let bytes = fast.fetch_batch(&[1, 2, 3])?;            // N*64 raw container bytes
```

## Elixir

```elixir
# mix.exs
{:semurg, path: "clients/elixir"}
```

```elixir
c = Semurg.new("http://localhost:4000")
{:ok, health}  = Semurg.health(c)
{:ok, status}  = Semurg.status(c)
{:ok, res}     = Semurg.histogram(c, 8, 16)
{:ok, buckets} = Semurg.query(c, :search, %{needle: "abc"})

# write:
w = Semurg.new("http://localhost:4000", token: System.get_env("SEMURG_TOKEN"))
Semurg.ingest(w, %{passages: [%{text: "Paris is the capital of France."}]})

# ATP fast path:
c = Semurg.new("http://localhost:4000", transport: :atp, token: "TOKEN")
{:ok, bytes} = Semurg.fetch_batch(c, [1, 2, 3])
```

**Elixir has one more trick — the in-process path.** A first-party Elixir extension compiled
into the node calls the data primitives directly, with *no HTTP and no socket at all*:

```elixir
{:ok, frames} = Semurg.InProcess.fetch(store_handle, [1, 2, 3])   # zero wire, zero copy
```

That is the fastest possible path, and it is exactly what [building an extension](extensions.md)
gives you.

---

Next: [building an extension](extensions.md) for zero-serialization, bare-metal performance, or
back to the [REST reference](api.md).
