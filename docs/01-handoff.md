# Shopping List App — Tech Stack & Architecture Handoff

> Outcome of a design grilling session. This is the agreed starting spec: decisions,
> rationale, data model, AI integration, and build order. Optimised for a 2-person
> household app on a homelab — deliberately small.

## 1. Purpose

A multiplayer (2-user) shopping list that **sorts the list by the order I walk a given
store**. The home operator (wife) jots down what to buy; the shopper (me) picks a store
and shops a route-ordered list. AI categorises items into the chosen store's sections.

The route-ordered, AI-categorised list **is the product** — it's the reason to use this
over our current "Signal messages with emoji reactions" workflow. A plain checklist is
*not* the MVP.

## 2. Locked decisions

| Area | Decision |
|---|---|
| **Platform** | Mobile-first **web app**. Android, both users on phones. No native, no PWA, no offline — connection is a non-issue. |
| **Liveness** | No real-time. **Refetch on unlock** (`visibilitychange`) + decaying poll (1→2→5→10→30s, reset on next unlock). Plain HTTP, no WebSockets. |
| **Concurrency** | No conflict handling. Last-write-wins. A 404 when checking off an already-deleted item is acceptable. |
| **Roles** | Soft split, **not auth-enforced**: home operator adds/deletes; shopper adds, checks off, marks "not available". Two views of the same app. |
| **Stores** | ~3 stores. Each is an **ordered list of sections** (the route), each section with optional hints/example products. |
| **AI categorisation** | **Core MVP.** Keyed on `(item, store)`. Runs **at start-of-session** against the chosen store's route. Batched, **synchronous** (brief spinner). |
| **"Learning"** | A `(store, normalized_item) → section` cache/override table. Cache hit = free + instant; only new items hit the API. User corrections persist and **beat** the AI. No fine-tuning, no vector DB initially. |
| **AI provider** | Cloud API — **Anthropic** and/or **OpenRouter** credits. No local model, no GPU on the homelab. |
| **Backend** | **Elixir**, Phoenix, rendering HTMX views |
| **Frontend** | **Server-rendered HTML + Masthead CSS + HTMX.** No SPA, no JS build step. |
| **Data store** | **SQLite** on a mounted Docker volume (`/data/shopping.db`). No backups. |
| **Deploy** | Single container → Gitea CI builds image → Portainer deploys → behind **Cloudflare Access**. |

## 3. Architecture

A **single stateless container**: one Phoenix web server that renders Masthead-classed HTML,
serves HTMX fragment swaps, reads/writes a local SQLite file on a mounted volume, and
makes occasional **batched** LLM calls. No queue, no worker, no cache server, no
separate API+SPA. This is the entire system.

```
Android browser ──HTTPS──> Cloudflare Access ──> Container
                                                  ├─ Phoenix (HTML + HTMX fragments)
                                                  ├─ SQLite      -> /data/shopping.db (volume)
                                                  └─ LLM client -> Anthropic / OpenRouter
```

## 4. Data model

Concrete shape that falls out of the session/carryover + per-store categorisation
requirements. Names are indicative.

### `store`
- `id`, `name`, `created_at`

### `section` (one store's route = its ordered sections)
- `id`, `store_id` (FK), `name`, `position` (int, route order), `hints` (text — example
  products / refinements, e.g. "coconut yoghurt, tofu")

### `session` (a shopping trip)
- `id`, `store_id` (FK, **nullable** until shopper picks a store), `status`
  (`open` → being filled at home; `shopping` → store chosen, active; `closed`),
  `created_at`, `completed_at`
- There is always **one `open` session** for the operator to add to.

### `item`
- `id`, `session_id` (FK), `name` (raw text as typed), `normalized_name` (see §5.3),
  `section_id` (FK, **nullable** until categorised), `status`
  (`pending` | `checked` | `not_available` | `deleted`), `position` (sort within
  section), `created_at`
- **Carryover:** on closing a session, items with `status = not_available` (and
  optionally still-`pending`) are re-created in the next `open` session.

### `categorization` (the cache + override / "learning" table)
- `store_id` (FK), `normalized_item_name`, `section_id` (FK), `source`
  (`ai` | `user`), `updated_at`
- **Unique** on `(store_id, normalized_item_name)`.
- `source = user` (a manual correction) **always wins** and is never overwritten by AI.

## 5. AI integration

Two call-sites only. Both send **structured JSON schemas** and parse responses into
Elixir structs (all LLM I/O and DB row shapes are typed at the boundaries).

### 5.1 Categorisation (MVP, on "Start shopping")
1. Shopper picks a store for the open session → `session.store_id` set, `status = shopping`.
2. For each `pending` item, look up `(store_id, normalized_name)` in `categorization`:
   - **hit** → assign `section_id`, no API call.
   - **miss** → add to a batch.
3. **One batched LLM call** with the store's sections (name + hints + order) as context →
   returns a section per batched item.
4. Write results to `categorization` (`source = ai`); assign `section_id` to items.
5. Sort the shopping view by `section.position`, then item `position`.
6. **Correction:** when the shopper moves an item to a different section, upsert
   `categorization` with `source = user`.

Net effect: groceries repeat heavily, so after a few weeks most items are cache hits —
a typical trip is one small batched call for the genuinely new items.

### 5.2 Route parsing (v2 — see build order)
Operator pastes a free-text/bulleted route → LLM → ordered `section` rows
(`name`, `position`, `hints`). Forgiving by design; fuzzier stores get coarser routes.
Editable after parsing.

Example input the parser must handle (most detailed store):

```
Auchan Gliwice:
"Stuff" (garden, electronics, car supplies, supplements, sports, hobby, homeware)
-> international cuisine -> bio/eco products -> vegetarian/vegan section (coconut
yoghurt, tofu) -> deli (ham and cheese) -> produce and bulk pantry, dried goods
(kasha, nuts, dried fruit) -> raw meat -> ... -> dairy and eggs
```

### 5.3 Normalisation (cache key)
Start simple: lowercase, trim, collapse internal whitespace. Defer singularisation and
semantic/fuzzy matching (embeddings) until cache misses on obvious repeats actually
annoy us (§9 v3).

### 5.4 Provider abstraction
Single thin client — `Req` (or `Finch`) + JSON. Call Anthropic directly or OpenRouter
via its OpenAI-compatible endpoint. Model id + key from env (`ANTHROPIC_API_KEY` /
`OPENROUTER_API_KEY`). Default to a current Claude model.

## 6. Frontend

- **Server-rendered Phoenix HEEx templates**, styled with **Masthead** classes. No build step.
- **HTMX** for interactivity: check-off, add/delete, "start shopping" swap, section moves
  — all return HTML fragments that already carry Masthead classes.
- **Refetch on unlock:** HTMX trigger on `visibilitychange`/focus, plus the decaying poll
  schedule (1→2→5→10→30s, reset on next unlock).
- Two primary views: **list view** (operator: add/delete) and **shopping view**
  (shopper: route-ordered, large touch targets, one-thumb check-off, mark not-available).

## 7. Typing policy

Elixir is dynamically typed — exploit that for velocity, but seal the boundaries.
**No Dialyzer in CI, no type-checker blocking builds.**
- **Typed (because it does real work):** Ecto changesets, embedded schemas (LLM I/O +
  DB row shapes), and Phoenix controller params. These *are* the validation/schema, and
  they make AI-assisted coding reliable (the agent reads shapes instead of guessing).
- **Loose:** local variables, private helpers, pipeline glue — spec only if it helps.
- **Type-checking lives in the editor as an LSP, never in CI.** Use standard Elixir
  language server (ElixirLS). `@spec` annotations on public functions are encouraged
  where the signature is non-obvious.
- **Runtime contracts > compile-time proofs.** Ecto changesets catch bad data before
  it hits the DB; pattern matching on function heads catches control-flow errors. These
  are the canonical Elixir safety tools.

## 8. Toolchain & deployment

### Dev (mise + Mix)
```toml
# mise.toml
[tools]
elixir = "latest"

[tasks.dev]
run = "mix phx.server"

[tasks.lint]
run = "mix format --check-formatted && mix credo --strict"
```
- **Mix** manages deps (`mix deps.get`) and the build.
- **SQLite** via `exqlite` — local file, no external DB server.
- Editors: neovim / Zed, with ElixirLS.

### Container & deploy
- Slim Elixir/OTP base image, deps fetched with Mix, single process (`mix phx.server` via `server: true` in prod).
- SQLite at `/data/shopping.db` on a **named Docker volume** (survives redeploys).
- Secrets via env: LLM key(s), model id.
- **Gitea CI** builds + pushes the image; **Portainer** pulls + deploys.
- **Cloudflare Access** sits in front — no in-app auth.

## 9. Build order

**v1 / MVP** (AI categorisation is in scope — it's the point):
- Store(s) with sections entered via a **simple structured form** (ordered list + hints).
  *(The slick free-text route parser is deferred to v2.)*
- Operator add/delete items into the open session.
- Shopper "start shopping at <store>" → batched AI categorisation of new items +
  cache/override table.
- Route-ordered shopping view: check-off, mark not-available.
- Session close → carryover of not-available items to the next open session.
- Refetch-on-unlock + decaying poll.
- Containerised, on the Gitea→Portainer pipeline, behind Cloudflare Access.

**v2:**
- Free-text route → AI-parsed JSON (§5.2) + nice route editing.

**v3:**
- Fuzzy/semantic cache matching (embeddings) for near-duplicate item names.
- Route order *learned from observed check-off order* in-store.

## 10. Explicitly out of scope / deferred

Native app · offline / local-first · real-time / WebSockets · in-app auth (Cloudflare
Access handles it) · conflict resolution · DB backups · barcode scanning ·
multi-household / productisation (only if it becomes indispensable).
