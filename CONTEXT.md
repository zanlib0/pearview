# Pearview

A 2-user household shopping-list app whose distinguishing feature is a
route-ordered, AI-categorised list: items are grouped and ordered by the
sections of whichever store the shopper picks, so the list follows the walk
through that store.

## Language

### Roles

**Operator**:
The household member who fills the list at home — adds and deletes items. Maps to
"the wife" in the original brief. Roles are a soft UI split, not auth-enforced.
_Avoid_: admin, user, owner.

**Shopper**:
The household member who shops — picks a store, runs the route-ordered list,
checks items off, marks items not available. Maps to "me" in the brief.
_Avoid_: user, customer.

**Manage**:
The maintenance surface, distinct from the Operator and Shopper views, where
Stores and their Routes are created and edited and the Categorization cache is
pruned. Used by the same two household members — it is **not a third persona**, it
is the "at home, maintaining the app" area. Sits alongside the two role views.
_Avoid_: admin, dashboard, settings, owner.

### Store & route

**Store**:
A physical shop the shopper visits. Has a name and an ordered set of Sections.
_Avoid_: shop, market.

**Section**:
One stop on a store's walk (e.g. produce, dairy, deli). Has a name, a position
in the route, and optional hints (example products that belong there). Belongs to
exactly one Store.
_Avoid_: aisle, category, department.

**Route**:
The ordered sequence of a Store's Sections — the path the shopper walks. Not a
separate entity; it *is* the Sections ordered by position.
_Avoid_: path, layout.

**Selected store**:
The one Store the Shopper is currently walking. There are now several Stores; the
Shopper picks one and there is a single Selected store at a time, shared across
both users (not per-device). Changing the Selected store re-resolves every Item's
Section against the new Store's Route. Absent a Trip entity, the selection is what
tells the Shopper view which Route to render.
_Avoid_: active store, current shop, default store.

### The trip

**Trip**:
One shopping trip's worth of list. Moves through states: **open** (being filled
at home, no store chosen yet), **shopping** (store picked, route-ordered, active),
**ended** (shopping done). The Shopper's **End trip** action ends the current
Trip and opens the next one. There is always exactly one open Trip for the
Operator to add to.
_Avoid_: session, list, cart.

**Item**:
One thing to buy, as typed by the Operator. Has a raw name, a normalized name
(the cache key), an assigned Section (once categorised), and a status:
**pending**, **checked**, or **not_available**. Removing an Item from the list
is deletion, not a status.
_Avoid_: product, entry, line.

**Carryover**:
On ending a Trip, its unbought items (not_available and still-pending) remain
wanted and appear in the next open Trip. A not_available mark records that
trip's stock, so it does not persist into the next Trip.
_Avoid_: rollover, leftover.

### AI categorisation

**Categorization**:
A row in the cache table keyed on (Store, normalized item name) → Section, with a
source of **ai** or **user**. A cache hit is free and instant; only never-seen
names hit the LLM. A Categorization may also record that the AI could not place a
name ("unplaced"); such items stay in Other and are not re-asked. Placements are
corrected during **home maintenance, never in-store**: the Operator improves a
Section's **hints** and deletes the stale Categorization row, so the name
re-resolves — with better context — the next time it appears. There are exactly
two retries, both Operator-driven: **rename the Item**, or **delete its
Categorization**. The `source` column survives from ADR-0002 but is effectively
always `ai`; the per-item **user override was dropped** in favour of hint-editing
(the old "a user correction always wins" rule no longer holds).
_Avoid_: classification, mapping, label.

**Normalized name**:
The cache key derived from an Item's raw name — initially just lowercase, trim,
and collapse internal whitespace. Fuzzy/semantic matching is deferred.
_Avoid_: slug, canonical name.
