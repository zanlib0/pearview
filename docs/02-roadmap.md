# Pearview — Phase Roadmap

Product-level phasing. Each phase becomes one or more PRDs (`docs/prd/`) and then
bite-sized issues. Phase 1 is the current focus. See `CONTEXT.md` for the glossary
and `docs/adr/` for architectural decisions. Source brief: `docs/01-handoff.md`.

The guiding cut: **the route-ordered, AI-categorised list is the product**, so AI
categorisation lands in Phase 1. Everything that makes it *robust for a real
two-person household* (sessions, learning, deploy) is deliberately pushed to
Phase 2 so Phase 1 stays a minimal, locally-runnable proof of the core loop.

## Phase 1 — Minimal AI shopping loop (local)

PRD: `docs/prd/00-minimal-ai-shopping-loop.md`

A single store with a predefined route, seeded into the DB. Operator adds/edits/
deletes items in a flat list. Shopper opens the shopping view → uncategorised
items are batch-categorised via OpenRouter → list renders grouped by section in
route order, with check-off and not-available. Refetch on visibility-unlock.
Runs on the developer's machine; no deploy.

Data model: `store`, `section`, `item` only. **No** `session`, **no**
`categorization` table — an item's section lives on the item row.

## Phase 2 — Household-ready & deployed

Turns the proof-of-loop into something the Operator and Shopper actually use.

- **Sessions:** the `open` → `shopping` → `closed` lifecycle (`session` table,
  `item.session_id`), with **carryover** of not-available / still-pending items
  into the next open session.
- **Learning:** the `categorization` cache + override table — repeat items are
  free, and a Shopper's manual section reassignment (`source = user`) persists and
  beats AI.
- **Multi-store + store picker:** seed the ~3 real stores; Shopper picks which
  store's route to shop, exercising the per-store cache key.
- **Liveness:** add the decaying poll (1→2→5→10→30s, reset on unlock) on top of
  the visibility-unlock refetch.
- **Polish + deploy:** Masthead polish pass; containerise and ship via the
  Gitea → Portainer → Cloudflare Access pipeline.

## Phase 3 — Route parser (handoff v2)

- Operator pastes a free-text/bulleted route → LLM → ordered `section` rows.
- Store/section **management UI** and route editing (replaces hand-editing
  `seeds.exs`).

## Phase 4 — Smarter matching (handoff v3)

- Fuzzy/semantic cache matching (embeddings) for near-duplicate item names.
- Route order **learned from observed check-off order** in-store.

## Explicitly out of scope (all phases, per handoff §10)

Native app · offline / local-first · real-time / WebSockets · in-app auth
(Cloudflare Access handles it) · conflict resolution · DB backups · barcode
scanning · multi-household / productisation.
