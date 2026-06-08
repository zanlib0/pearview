---
phase: 1
status: ready-for-agent
---

# PRD: Minimal AI shopping loop (local)

> Phase 1 of the roadmap (`docs/02-roadmap.md`). Glossary: `CONTEXT.md`.
> Architecture decision: `docs/adr/0001-htmx-masthead-over-liveview.md`.

## Problem Statement

Our household coordinates shopping over Signal messages with emoji reactions. The
person at home (the Operator) lists what to buy; the person at the store (the
Shopper) has to mentally re-sort that list into the order they actually walk the
store, aisle by aisle. It's slow, error-prone, and easy to miss things. A plain
checklist wouldn't fix this — the value is in the list being **ordered by the
store walk**. We want to prove that core experience end-to-end, running locally,
before investing in sessions, learning, and deployment.

## Solution

A mobile-first web app with two views over one shared, predefined store:

- The **Operator** view is a flat list where they add, edit, and delete items.
- The **Shopper** view, on open, asks an LLM to sort every not-yet-categorised
  item into the store's **Sections**, then shows the list **grouped by section in
  route order** — the exact order the Shopper walks the store. The Shopper checks
  items off and marks ones that weren't available.

Because the store and its route are predefined (seeded), and there are no
sessions or learning yet, this is the smallest thing that demonstrates the
product's reason to exist: a route-ordered, AI-categorised shopping list.

## User Stories

### Operator — managing the list

1. As an Operator, I want to add an item by typing its name, so that the Shopper knows to buy it.
2. As an Operator, I want my new item to appear in the list immediately without a full page reload, so that adding several items in a row feels fast.
3. As an Operator, I want to edit an item's name after adding it, so that I can fix typos or clarify ("milk" → "oat milk").
4. As an Operator, I want to delete an item, so that things we no longer need don't clutter the Shopper's list.
5. As an Operator, I want to see the full current list of items, so that I know what's already on it before adding more.
6. As an Operator, I want the list to work one-handed on my phone, so that I can jot things down while doing something else.

### Shopper — shopping the route

7. As a Shopper, I want to open the shopping view and have the list automatically sorted into the store's sections, so that I don't have to mentally re-order it.
8. As a Shopper, I want the sections shown in the order I physically walk the store, so that I can move through the store in one pass without backtracking.
9. As a Shopper, I want items grouped under their section heading, so that I can grab everything in one part of the store before moving on.
10. As a Shopper, I want to see a brief loading indicator while categorisation runs, so that I know the app is working and not frozen.
11. As a Shopper, I want to check an item off, so that I can track what I've already put in the cart.
12. As a Shopper, I want a checked-off item to visibly change (e.g. struck through / moved), so that I can tell at a glance what's left.
13. As a Shopper, I want to mark an item as "not available", so that I record that the store didn't have it rather than just skipping it.
14. As a Shopper, I want large touch targets for check-off, so that I can tap accurately while holding a basket.
15. As a Shopper, I want any item the AI couldn't confidently place to appear in an "Other" group at the bottom, so that nothing silently disappears from my list.
16. As a Shopper, I want items I add or check off to update without a full reload, so that shopping feels responsive.
17. As a Shopper, I want the list to refetch when I unlock my phone or return to the tab, so that I see what the Operator added while my screen was off — without me hitting refresh.

### Shared / system

18. As either user, I want both views to read and write the same single shared list, so that what one person does is visible to the other.
19. As a Shopper, I want items that were already categorised to not be re-sent to the AI, so that opening the shopping view repeatedly is fast and cheap.
20. As a developer, I want the store and its route defined in seed data, so that I can set up and tweak the store without building a management UI yet.
21. As a developer, I want the AI provider and model configured via environment, so that I can change models without code changes.

## Implementation Decisions

### Architecture
- Server-rendered HEEx from Phoenix **controllers** (dead views), **HTMX** for
  interactivity, **Masthead** CSS for styling. **No LiveView.** (ADR-0001.)
- Apply Masthead classes as views are built; no dedicated styling-polish pass in
  this phase.
- SQLite via `ecto_sqlite3` (already in deps).

### Data model (Phase 1 only)
Three tables. **No `session`, no `categorization` table, no `item.position`.**

- **store** — `id`, `name`, timestamps.
- **section** — `id`, `store_id` (FK), `name`, `position` (integer, route order),
  `hints` (text, nullable — example products for AI context), timestamps.
- **item** — `id`, `name` (raw text as typed), `normalized_name`, `section_id`
  (FK, **nullable** until categorised), `status` (`pending` | `checked` |
  `not_available`), timestamps.
  - `normalized_name` = lowercase, trim, collapse internal whitespace.
  - Delete is a **hard delete** (`Repo.delete`), not a soft `deleted` status.

**As built:** schemas live under `Pearview.Shopping.{Store, Section, Item}`; the
DB tables are idiomatically pluralised (`stores`, `sections`, `items`) — the
singular names above are the conceptual entities. `status` is an `Ecto.Enum`
(`:pending | :checked | :not_available`, default `:pending`). The `section`
FK uses `on_delete: :nilify_all` (deleting a section uncategorises its items
rather than deleting them); `section.store_id` uses `:delete_all`.

The single store and its ordered sections (with hints) are created in
`priv/repo/seeds.exs`. Items belong directly to the app's single shared list
(no session wrapper). Seed items are inserted **uncategorised** (`section_id`
nil) in a mix of statuses so the list view exercises each state.

### Domain — `Pearview.Shopping` context
The context owns all data access and the categorisation orchestration:
- Add item (normalises name, status `pending`, `section_id` nil).
- Edit item name (re-normalises).
- Delete item.
- List items.
- List items grouped + ordered for the shopper view (see Rendering).
- `categorize_uncategorized/0` (name indicative): finds items with `section_id =
  nil`, calls the AI for the seeded store's sections, and writes the returned
  `section_id` onto each item. Items the AI leaves unplaced (unknown/off-route
  section, or AI error) keep `section_id = nil`.

### AI — `Pearview.AI`
- **Provider:** OpenRouter, OpenAI-compatible endpoint
  (`https://openrouter.ai/api/v1/chat/completions`), called via **`Req`**.
- **Key:** `OPENROUTER_API_KEY` from env.
- **Model:** default **`deepseek/deepseek-v4-flash`**, overridable via env.
- **Single thin module.** No provider abstraction / no second provider in this
  phase.
- **Call shape:** one **synchronous, batched** call for all uncategorised items.
  Input context = the store's sections (name + hints + position). Output via
  **forced OpenAI-style tool/function call** whose schema is an array of
  `{item, section}` objects, with `section` constrained to the seeded section
  names. (Fallback to `response_format: json_schema` if the chosen model lacks
  tool-calling support on OpenRouter — confirm at implementation.)
- Returned sections are mapped back to `section_id`; any item whose returned
  section doesn't match a real section is left uncategorised (→ Other bucket).

### Rendering — shopper view ordering
1. Group items by `section`.
2. Order section groups by `section.position` (the route).
3. Within a section, order items by `inserted_at` (insertion order).
4. Items with `section_id = nil` render in an **"Other"** group pinned **last**.

### Rendering — item-list display (issue #1, as built)
The first vertical slice renders the **flat list of items** (the Operator's read
view) at the app root `/`, replacing the generated Phoenix welcome page. It is
**read-only** in this slice: rows reflect each item's status but do not yet write
— check-off / not-available persistence arrives with the Shopper view and its
HTMX fragment swaps. The markup is already shaped for that (add `hx-*`, remove
nothing).

- **Each item is a Masthead `.tick-box`** whose state mirrors `item.status`:
  - `pending` → unchecked box + plain name.
  - `checked` → checked box + name struck through.
  - `not_available` → **no checkbox**, name struck through. No status tag/stamp;
    the strikethrough alone marks it (distinguished from `checked` by the absence
    of a box).
- **No rules between rows** — row padding carries the vertical rhythm; the list
  is a ruleless column. Rows keep a comfortable touch target (`min-height`).
- **Masthead anatomy:** a `<label>` wraps the bare `<input class="tick-box">`
  with the name as label text. The strikethrough / faded treatments are
  caller-layer CSS built from Masthead tokens (`--ink-3`, `--space-*`), not
  contract departures.

### Masthead wiring (as built)
- Masthead is linked via its CDN stylesheet; the document sets
  `data-theme="light"` and `data-accent="peridot"` on `<html>`.
- The generated **daisyUI / Tailwind scaffolding was removed** as dead code under
  Masthead: `priv/static/assets/default.css`, `CoreComponents`
  (button / input / flash / table / icon), and the daisyUI chrome in `Layouts`
  (`app/1`, the flash group). `translate_error/translate_errors` went with it and
  will be reintroduced (Masthead-styled) when the Operator add/edit forms need
  form-error rendering.

### Web / HTMX interactions (contract, not file paths)
- **Operator view:** renders the flat list + add form. Add / edit / delete each
  return an HTML fragment so the list updates without full reload.
- **Shopper view:** on load, triggers `categorize_uncategorized`, shows a brief
  spinner, then renders the route-ordered grouped list. Check-off and
  not-available each return an updated HTML fragment.
- **Liveness:** an HTMX trigger on `visibilitychange`/focus refetches the current
  view when the user unlocks the phone or refocuses the tab (like React Router
  refetch-on-focus). **No decaying poll in this phase** (deferred to Phase 2).

## Testing Decisions

A good test asserts **external behaviour**, not implementation details: given DB
state and (stubbed) AI responses, assert the data written and the HTML rendered —
never private function internals. Three seams:

- **Domain (`Pearview.Shopping`) via the existing `Pearview.DataCase` seam.**
  These functions write to the DB, so tests insert/seed rows and assert on
  persisted results: adding normalises the name and leaves `section_id` nil;
  editing re-normalises; deleting removes the row; `categorize_uncategorized`
  (with a stubbed AI) assigns the right `section_id`s and leaves AI-unplaced items
  null; the grouped/ordered query returns sections in `position` order with the
  Other bucket last.
- **AI boundary (`Pearview.AI`) via `Req.Test` (new seam, no Mox/behaviour).**
  Stub OpenRouter responses to assert: the request is built correctly (endpoint,
  auth header, model, tool schema with the seeded section names); a well-formed
  tool-call response parses into item→section mappings; an off-route/unknown
  section is dropped; an HTTP error or malformed body yields "nothing
  categorised" rather than crashing.
- **Web/HTMX via the existing `PearviewWeb.ConnCase` seam.** Request-level tests:
  operator add/edit/delete return the expected fragments and change the list;
  the shopper view (with a stubbed AI) renders section groups in route order with
  Other last; check-off and not-available update item status and return the right
  fragment.

**Prior art:** `test/pearview_web/controllers/item_controller_test.exs` is the
ConnCase pattern to follow for request tests (it replaced the generated
`page_controller_test.exs`).

## Out of Scope

Deferred to later phases (see `docs/02-roadmap.md`):

- **Sessions** (open/shopping/closed lifecycle) and **carryover** — Phase 2.
- **Learning:** the `categorization` cache + user-correction override — Phase 2.
  No section-reassignment UI; categorisation quality is eyeballed for now.
- **Multiple stores / store picker** — Phase 2 (Phase 1 is one seeded store).
- **Decaying poll** liveness — Phase 2 (Phase 1 has visibility-unlock refetch
  only).
- **Deployment** (Gitea → Portainer → Cloudflare Access) — Phase 2.
- **Store/section management UI** and the **free-text route parser** — Phase 3.
- **Fuzzy/semantic matching; learned route order** — Phase 4.
- Within-section manual reordering (`item.position`); soft-delete; provider
  abstraction / OpenRouter-vs-Anthropic switching; auth (Cloudflare Access).

## Further Notes

- **Liveness assumption to confirm:** your "just on visibility unlock" comment was
  read as *include the visibility-unlock refetch in Phase 1, defer the decaying
  poll*. If you meant defer all liveness to Phase 2, drop user story #17 and the
  liveness interaction above.
- **Model caveat:** `deepseek/deepseek-v4-flash` must support OpenAI-style tool
  calling on OpenRouter for the forced-tool-call output contract; if not, use the
  `response_format: json_schema` fallback for that model. Verify at
  implementation.
- Mobile-first, Android, both users on phones; large touch targets matter for the
  shopper view even in this minimal phase.
