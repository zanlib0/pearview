---
phase: 2
status: ready-for-agent
---

# PRD: Multi-store + the Manage surface

> Phase 2 of the roadmap (`docs/02-roadmap.md`). Glossary: `CONTEXT.md`.
> Architecture decisions: `docs/adr/0002-categorization-cache-not-items.md`,
> `docs/adr/0004-corrections-via-hints-not-overrides.md`.

## Problem Statement

We've shopped with Pearview several times now, and Phase 1 proved the core loop —
but real use exposed three walls, all of which currently require editing
`seeds.exs` and restarting the app:

1. **There is only one store, hard-coded.** Our household actually shops at
   several stores, each with its own walk. Today the Shopper is stuck with the one
   seeded Route, so at every other store the "route-ordered" list is in the wrong
   order — the product's whole reason to exist stops working away from the seeded
   store.
2. **We can't fix a bad placement without touching code.** When the AI puts an
   item in the wrong Section, the only real lever is to improve that Section's
   **hints** — but hints live in `seeds.exs`. There's no way to reword a Section's
   example products from the app.
3. **Bad AI guesses are sticky.** A wrong (or "unplaced") Categorization sits in
   the cache forever and is never re-asked, so once the AI mis-files "sour cream"
   it stays mis-filed on every future trip. We need to prune individual cache
   entries so a corrected hint can take effect.

Crucially, all of this is **at-home maintenance work**, done between trips — not
something the Shopper does mid-aisle. Phase 1 has no home for it.

## Solution

Two additions, sharing one theme ("the app is now maintainable without code"):

- **Multi-store shopping.** The Shopper view gains a **store dropdown**. Picking a
  store makes it the **Selected store**: the app nulls every Item's Section and
  re-resolves the whole list against that store's Route (cache-first, so mostly
  free). There is one Selected store at a time, shared across both phones; a plain
  reload/refetch reads it and only resolves still-uncategorised Items.

- **The Manage surface.** A third view — *not* a third persona, just the "at home,
  maintaining the app" area (see `CONTEXT.md`) — where the Operator can:
  - create, rename, and delete **Stores**;
  - within a Store, create / rename / reorder / delete **Sections** and edit their
    **hints** (the AI's per-Section example products);
  - browse a Store's **Categorization cache** and **delete individual entries**,
    so a name re-resolves (with freshly-edited hints) the next time it appears.

Corrections follow ADR-0004: you fix a placement by editing a Section's hints and
deleting the stale cache row — never by overriding one Item. The two retries are
*rename the Item* and *delete its Categorization*; both are Operator actions.

## User Stories

### Shopper — picking a store

1. As a Shopper, I want to pick which store I'm shopping from a dropdown on the
   shopping view, so that the list is ordered for the store I'm actually standing in.
2. As a Shopper, I want the section groups and their order to reflect the store I
   picked, so that the walk matches this store's aisles, not some other store's.
3. As a Shopper, I want picking a store to re-sort my whole list into that store's
   sections automatically, so that I don't have to re-categorise anything by hand.
4. As a Shopper, I want re-sorting to be instant for items the app has seen before
   at this store, so that switching stores doesn't stall on the AI.
5. As a Shopper, I want the store I picked to still be selected when I lock and
   unlock my phone or the page refetches, so that I don't get bounced back to a
   different store mid-trip.
6. As a Shopper, I want my chosen store to be the same one my partner sees, so that
   we're both looking at one shared list for one store.
7. As a Shopper, I want items the AI can't place at the picked store to fall into
   the Other group, so that nothing disappears when I switch stores.

### Operator (in Manage) — stores

8. As an Operator, I want to open a Manage view separate from the Operator and
   Shopper views, so that I can maintain the app without cluttering the shopping
   screens.
9. As an Operator, I want to see all the stores I've set up, so that I know what's
   available to shop.
10. As an Operator, I want to create a new store with a name, so that I can start
    defining a store we've begun shopping at.
11. As an Operator, I want to rename a store, so that I can fix a typo or clarify
    which shop it is.
12. As an Operator, I want to delete a store I no longer use, so that it stops
    showing up in the Shopper's dropdown.
13. As an Operator, I want deleting a store to also discard that store's cached
    categorisations, so that stale knowledge for a dead store doesn't linger.
14. As an Operator, I want deleting the store that's currently selected to simply
    clear the selection (so the Shopper re-picks), so that the app doesn't point at
    a store that no longer exists.

### Operator (in Manage) — sections and route

15. As an Operator, I want to see a store's sections in route order, so that I can
    see the walk the way the Shopper will.
16. As an Operator, I want to add a section to a store, so that I can extend the
    route as I learn the store's layout.
17. As an Operator, I want to rename a section, so that its heading reads the way I
    think of that part of the store.
18. As an Operator, I want to edit a section's hints (example products), so that the
    AI has better context and files future items correctly.
19. As an Operator, I want to reorder a store's sections, so that the route matches
    the order I actually walk the aisles.
20. As an Operator, I want to delete a section, so that I can remove a part of the
    store that isn't a useful stop.
21. As an Operator, I want deleting a section to leave its items on the list
    (uncategorised, so they re-sort next open) rather than deleting them, so that I
    never lose an item by editing the route.
22. As an Operator, I want deleting a section to drop that section's cache entries
    (rather than freezing them as "unplaced"), so that those names get re-asked
    against the new route instead of being stuck in Other.

### Operator (in Manage) — the cache

23. As an Operator, I want to browse a store's categorisation cache, so that I can
    see where the app thinks each known item belongs at that store.
24. As an Operator, I want cache entries the AI couldn't place ("unplaced") to be
    visible in that list, so that I can see what's falling through to Other.
25. As an Operator, I want to delete an individual cache entry, so that after I
    improve a section's hints, that name gets re-asked next time it appears.
26. As an Operator, I want deleting a cache entry to remove only that entry (not
    touch items currently on a list), so that cache pruning is a predictable,
    between-trips maintenance action.

### System / shared

27. As either user, I want stores, sections, and the cache to be shared server-side,
    so that both phones see the same setup and the same selected store.
28. As a developer, I want the seed data to define more than one store, so that
    multi-store works out of the box in dev and prod.
29. As a developer, I want the "which store is being shopped" decision to come from
    the selected store rather than "first store by id", so that adding stores
    doesn't silently change what the Shopper sees.

## Implementation Decisions

### The Selected store (replaces the single-store assumption)

- Today `CategorizeUncategorized.current_store/1` picks *the first store by id*.
  That hard-wired single-store assumption is removed: the current store is the
  **Selected store**.
- **A singleton "settings" row** holds `selected_store_id` (nullable FK to
  `stores`). One row, app-wide, read by both the Shopper view and the
  categorisation orchestration. **No Trip/session table** — the selection is the
  only "current shopping context" we need this phase.
- `Pearview.Shopping` gains `get_selected_store/0` and `select_store/1`.
  `get_selected_store/0` returns the store the singleton points at (or `nil`).
- The orchestration reads the Selected store instead of "first by id"; everything
  else in `CategorizeUncategorized` (cache-first, background LLM pass, one-run
  guard, write-through, ADR-0002 error rule) is unchanged.

### Shopper view — the store dropdown

- The Shopper view renders a dropdown of all stores, with the Selected store
  chosen. It also renders that store's Route-ordered groups exactly as today.
- **Plain GET `/shopper`** reads the Selected store, renders its Route, and runs
  the existing `categorize_uncategorized` (resolves only `section_id`-nil items,
  cache-first). It does **not** null anything. Cycling an item and the
  visibility-unlock refetch (Phase 1 story #17) hit this path.
- **Changing the dropdown** posts to a `select_store` action which:
  1. sets the singleton to the chosen store;
  2. **nulls `section_id` on every Item** (`Repo.update_all`);
  3. runs `categorize_uncategorized` against the new store (cache-first);
  4. re-renders the grouped list (HTMX fragment swap).
- Re-stamping is a full re-resolve, so an item's placement is always the placement
  *at the currently selected store*. This is the mechanism by which
  `item.section_id` means "section in the store I'm currently shopping."

### Manage surface — routing and controllers

- A new **`ManageController`** (and HTML module) under a `/manage` scope, in the
  existing `:browser` pipeline. Roles are a soft UI split (`CONTEXT.md`); no auth.
- Store operations: list, create, rename, delete. Section operations (scoped to a
  store): list in route order, create, rename, edit hints, reorder, delete. Cache
  operations (scoped to a store): list categorizations, delete one.
- All mutations return **HTML fragments** for HTMX swaps, consistent with the
  Operator and Shopper views (no full reloads). Navigation links connect the
  Operator, Shopper, and Manage surfaces.
- Reordering sections uses up/down controls that swap adjacent `position` values
  (no drag-and-drop library — keep it HTMX-only). `position` stays the route
  order; the Shopper query already orders by it.

### Domain — `Pearview.Shopping` context additions

- **Stores:** `list_stores/0`, `create_store/1`, `update_store/2`,
  `delete_store/1`. `delete_store/1` clears the Selected-store singleton first if
  it points at that store, then deletes (cache rows cascade via FK — see Schema).
- **Sections:** `list_sections/1` (by store, position order), `create_section/1`,
  `update_section/2` (name and/or hints), `move_section/2` (reorder),
  `delete_section/1`.
- **Cache:** `list_categorizations/1` (by store, including "unplaced" rows),
  `delete_categorization/1` (removes **only** that row — no cascade to items, per
  ADR-0004).
- **Selection:** `get_selected_store/0`, `select_store/1` (sets singleton, nulls
  all item sections, recategorises).

### Schema changes

- **New `settings` singleton table:** `selected_store_id` (nullable FK to
  `stores`, `on_delete: :nilify_all` so deleting the selected store clears the
  selection). Enforced single row (id fixed to 1, or a `Repo`-level upsert helper).
- **`categorizations.section_id` FK flips `:nilify_all` → `:delete_all`.** Deleting
  a Section must **drop** that section's cache rows, not turn them into "unplaced"
  (which would freeze those names in Other and never re-ask them). `store_id`
  stays `:delete_all` (already correct — store delete cascades its cache).
- `sections.store_id` (`:delete_all`) and `items.section_id` (`:nilify_all`) are
  unchanged — deleting a store cascades its sections; deleting a section
  un-stamps (not deletes) its items.
- **`categorizations.source`** stays but is dormant: only `:ai` is ever written
  (ADR-0004). No migration to drop it.

### Seed data

- `Pearview.Release.seed_data/0` (the single source for dev + prod seeds) defines
  **multiple stores**, each with its own ordered Sections + hints. `seeds.exs`
  stays the destructive dev reset; `Release.seed/0` stays idempotent for prod.
- The Selected-store singleton is seeded to one store (or left null so the Shopper
  picks on first open — either is acceptable; default to the first seeded store
  for a working out-of-the-box view).

## Testing Decisions

A good test asserts **external behaviour** — given DB state and (stubbed) AI
responses, assert the data written and the HTML rendered, never private
internals. Three seams, all already established in Phase 1:

- **Domain (`Pearview.Shopping`) via `Pearview.DataCase`.** Store CRUD (create
  normalises nothing special; delete cascades cache and clears the singleton when
  it pointed there); section CRUD (create/rename/edit-hints; reorder swaps
  positions; **delete un-stamps its items and deletes its cache rows**); cache
  list returns a store's rows including "unplaced"; `delete_categorization`
  removes only the row and leaves items untouched; `select_store` sets the
  singleton, nulls all item sections, and re-stamps from cache; `get_selected_store`
  reflects it. Prior art: the existing `CategorizeUncategorized` / grouped-query
  tests.
- **Web/HTMX via `PearviewWeb.ConnCase`.** `ManageController`: store and section
  create/rename/delete and hint-edit return the expected fragments and change the
  DB; section reorder returns sections in the new order; cache list renders a
  store's entries; delete-cache-entry removes the row. Shopper: the dropdown
  renders all stores with the selected one chosen; the select-store action nulls +
  re-groups the list for the new store; a plain GET does **not** re-null. Prior
  art: `test/pearview_web/controllers/item_controller_test.exs` and the shopper
  controller tests.
- **AI boundary (`Pearview.AI`) — unchanged.** No new behaviour; existing
  `Req.Test` stubs cover categorisation. Multi-store is exercised by passing a
  given store's sections, which the domain/orchestration tests already drive.

Store-switch re-stamping should be asserted with a **stubbed AI** and a
**pre-seeded cache** so the "mostly free" cache-first path is what's tested, not a
live LLM call.

## Out of Scope

Deferred to later phases (see `docs/02-roadmap.md`) or explicitly dropped:

- **Free-text route parser** (paste a route → LLM → ordered Sections) — **Phase 3**,
  and deliberately *not* pulled forward ("AI analysis of a store description is
  unnecessary"). Section hints are hand-edited in Manage.
- **Per-item section override / manual re-sort** — **dropped** (ADR-0004).
  Corrections are hint-edit + cache-delete only. No Shopper-facing "move this item"
  control, and the `source: :user` path stays dormant.
- **A Trip/session table and formal open→shopping→ended lifecycle** — not needed;
  `end_trip` and the Selected-store singleton cover this phase's needs. Carryover
  already works (Phase 1).
- **Per-device / per-person store selection** — the Selected store is a single
  shared value; both phones agree.
- **Decaying-poll liveness** — still Phase 2-later; this PRD keeps only the Phase 1
  visibility-unlock refetch.
- **Fuzzy/semantic name matching; learned route order** — Phase 4.
- **Auth** — Cloudflare Access handles it; Manage is not access-controlled in-app.

## Further Notes

- **Re-stamp cost.** Switching stores nulls and re-resolves *every* item. With a
  warm per-store cache this is all DB work; only genuinely-new names at that store
  hit the LLM (via the existing background task), so the switch stays responsive
  and the Shopper view paints immediately with a "Categorising" note if needed.
- **The correction loop, end to end** (ADR-0004): AI mis-files "sour cream" at
  Store A → Operator opens Manage, edits Store A's "Dairy" hints to include *sour
  cream*, and deletes the "sour cream" cache entry → next trip the Operator re-adds
  it (or it's re-added fresh) → cache miss → LLM re-asks with the better hints →
  correct. Editing hints alone does nothing without the cache delete; that's why
  both live in Manage.
- **Single-row settings.** Keep the singleton trivial (one row, upserted). If it's
  ever absent, treat as "no store selected" and prompt the Shopper to pick.
