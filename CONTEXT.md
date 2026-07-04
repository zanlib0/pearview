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
A row in the cache/override table keyed on (Store, normalized item name) → Section,
with a source of **ai** or **user**. A cache hit is free and instant; only
never-seen names hit the LLM. A Categorization may also record that the AI
could not place a name ("unplaced"); such items stay in Other and are not
re-asked — renaming the item is the retry. A user correction (source=user)
always wins and is never overwritten by AI.
_Avoid_: classification, mapping, label.

**Normalized name**:
The cache key derived from an Item's raw name — initially just lowercase, trim,
and collapse internal whitespace. Fuzzy/semantic matching is deferred.
_Avoid_: slug, canonical name.
