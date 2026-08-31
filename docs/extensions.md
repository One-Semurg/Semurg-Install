# Tiers, extensions & integrations

This is how you build *on top of* Semurg — your own apps, domain models, and connectors — and
get bare-metal performance because your code runs **inside** the node, against the one data layer,
with no serialization round-trip.

---

## The three tiers

Everything composes on **one data layer**. There are three tiers, an inward-only stack:

| Tier | What it is | Examples |
|---|---|---|
| **Core** | The platform itself — the substrate engine + its primitives. Ships in the download; you don't modify it. | the storage/graph/vector/scan engine, the conveyor, the model runtime |
| **Extensions** | *Your* apps — a domain knowledge graph, a company app, a per-team overlay — each a peer on the substrate. | a contacts graph, a legal KG, an email app |
| **Integrations** | Two-way connectors to outside databases (ingest in, egress out). | CSV, DuckDB, MongoDB, MySQL, Postgres, Redis, SQLite, Neo4j |

An extension is tagged with a **block** category — `:industry`, `:company`, `:personal`,
`:service`, or `:foundation` — which is a *scope*, not a rank. A company extension composes an
industry one, a personal overlay composes the company one, and each layer only *adds*
content-addressed edges onto the layer below, so a lower layer can never be broken by one above.

---

## Why build an extension instead of calling the API?

Because an extension runs **in-process**, inside the node, so it reaches the data with **zero
serialization tax** — no HTTP, no socket, no JSON, no copy. The REST/ATP APIs are for talking to a
node *from outside*; an extension *is* part of the node. That is the difference between "fast" and
"as fast as the metal allows."

The rule that buys that speed:

> **Data stays raw binary everywhere inside the perimeter; only 64-bit *coordinates* (a handle,
> an id, a count) ever cross the language boundary; and you cross it once per *batch*, never once
> per item.**

Four corollaries every extension author follows:

| # | Do this | Not that |
|---|---|---|
| 1 · **Binary perimeter** | Keep data as raw 64-byte containers through storage, traversal, and compute; decode to a number only at the ALU, re-encode immediately. | `Jason.decode`, `binary_to_term`, building a map from container bytes on a hot path. |
| 2 · **Only coordinates cross** | Down: a store handle + a `u64` id (or a packed-u64 binary) + a count. Up: a handle, an id, or a small fixed tuple. | Returning a map / list-of-N-ids / a struct rebuilt from bytes. |
| 3 · **Fan wide, cut deep** | Elixir spreads concurrency across cores; each core's hot work is a small native routine (SIMD, direct I/O). | A message queue on the per-operation path. |
| 4 · **Batch the crossing** | Hand the native side a whole page / frontier / id-vector in one call. | One native call per item — that loses to staying in Elixir. |

A result set (say a graph traversal producing millions of ids) stays resident on the native side
behind an opaque handle; only a small top-K is ever materialized at the edge. The graph itself
never crosses the boundary.

The first-party in-process call looks like this:

```elixir
{:ok, frames} = Semurg.InProcess.fetch(store_handle, [1, 2, 3])   # == the engine's own fetch, zero wire
```

---

## Build one — step by step

Semurg ships a deterministic scaffolder that turns a short spec into a working, wall-compliant
extension. (It is templated, not guesswork — same spec in, same code out.)

**1. Write a spec** — an `.exs` file describing your ontology (nodes + edges), the workflows, and
at least one screen:

```elixir
%{
  version: 1,
  block: :industry,                     # :foundation | :industry | :company | :personal | :service
  name: :rolodex,
  title: "Rolodex",
  description: "A people & organizations knowledge graph.",
  composes: [],                         # peer extensions this one borrows from
  ontology: %{
    nodes: [%{tag: :person, type_tag: 1, doc: "a contact"},
            %{tag: :company, type_tag: 2, doc: "an employer"}],
    edges: [%{rel: :works_at, rel_id: 10, from: :person, to: :company, hops: 2}]
  },
  workflows: [
    %{name: :add_person, kind: :store,    node: :person},
    %{name: :employ,     kind: :connect,  edge: :works_at},
    %{name: :colleagues, kind: :traverse, seed: :person, hops: 2}
  ],
  surfaces: [%{name: :directory, route: "/", title: "Directory"}],   # >=1 LiveView screen
  capabilities: [:read, :write, :connect, :traverse]
}
```

**2. Generate the app:**

```bash
mix semurg.gen.extension path/to/spec.exs --into .
```

It emits a complete umbrella app: the manifest, an ontology module, a session module, the
workflows, one LiveView per screen, an oracle test (build → store → connect → traverse), and a README.

**3. Prove the wall, then build and test** — exactly what the generator tells you to run next:

```bash
mix semurg.check_rings && mix compile && mix test apps/<name>
```

---

## The composition wall (`mix semurg.check_rings`)

`check_rings` is the safety envelope — a fast source scan (no compile) that runs first in CI and
**fails the build** on any violation. It is what makes extensions safe to compose and publish. It
enforces:

- **Data path is substrate-only** — an extension may not pull in a foreign database (Postgres,
  Redis, Mongo, Ecto, Mnesia…); the substrate *is* the store.
- **Web surface is LiveView-only** — no bare JSON controller.
- **Composition is acyclic** — peers borrow each other by additive, content-addressed edges;
  cross-references may only name a peer's declared public surface; no cycles.
- **Inward-only** — an extension never reaches "up" into the host gateway.

If it's green, your extension is a well-behaved peer on the one substrate.

---

## Distribution — the marketplace

An extension's identity is its **envelope** — `{version, name, block, composes, exposes}` —
content-addressed to a version id (`mkt:<sha256>`), so the same envelope is the same id
(idempotent) and any change mints a new one, appended, never overwriting. Membership of the
marketplace is the fixpoint of the wall: an entry is publishable exactly when `check_rings`
returns zero violations for it. The envelope, the wall, and the version-id math are live today;
the packaged download + dependency resolver + one-click install are on the near-term roadmap.

---

## Integrations — two-way database connectors

Semurg ingests from and egresses back to outside databases through **one** canonical seam (a
shared intermediate representation), so each of the shared cores — fold, schema catalog, reverse
projector, credentials — is written once, never per database.

Connectors on the platform today include **CSV, DuckDB, MongoDB, MySQL, Postgres/SQL Server
(ODBC), Redis, SQLite, and Neo4j**. Each is hand-rolled over a plain socket (no third-party
driver in the perimeter).

The proof standard is the **round-trip**: load data into database A → ingest A into Semurg →
egress Semurg into a *different, empty* instance of A → verify equal answers at both ends, then
drop the store and repeat. The fold path is a native routine that is bit-exact to a pure-Elixir
reference, so ingestion is verified, not asserted.

---

Next: the [REST API](api.md), the [wire protocols](protocols.md), the [SDKs](sdks.md), or the
[admin console](access.md).
