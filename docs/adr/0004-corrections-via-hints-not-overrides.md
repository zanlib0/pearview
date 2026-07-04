# Placements are corrected by editing hints, not by per-item overrides

ADR-0002 gave every Categorization a `source` of `ai` or `user` and promised that
a **user correction always wins and is never overwritten by AI**. Using the app
for real changed our mind: a miscategorised item is not something you fix *in the
store, mid-trip* — it is something you fix **at home, maintaining the app**. And
when you fix it, patching one item ("put *this* milk in Dairy") is the wrong
lever. The right lever is to improve the **Section's `hints`** so the *rule* gets
better and every future "milk" lands correctly. You teach the store, not the item.

So the per-item override is **dropped**. There is no UI to reassign one item's
Section. The `source: :user` value is never written; the column survives only so
the schema need not migrate and so the distinction can return if a future phase
wants it. In practice every Categorization is now `source: :ai`.

This reverses one rule of ADR-0002 (the "user correction wins" rule). Everything
else in ADR-0002 stands: the cache is still the durable record, items still carry
a disposable `section_id` projection, "unplaced" rows still park a name in Other,
and errors still write nothing.

## The rules, in plain words

1. **Correction is Manage-time, never Shopper-time.** The Shopper never edits
   placements; they only shop the route as given. Fixing a bad placement happens
   in the **Manage** surface, between trips.
2. **The fix is: edit hints, then delete the cache row.** Improving a Section's
   `hints` does nothing to names already in the cache — the row still says
   `milk → Snacks`. So the correction is two moves: reword the hints, then
   **delete the stale Categorization**. The name re-resolves — with the better
   hints — the next time it appears as a fresh Item.
3. **There are exactly two retries, both Operator-driven.** *Rename the Item*
   (ADR-0002 rule 5 — a new normalized name is a new cache key) or *delete its
   Categorization*. There is deliberately no third retry, and none that a Shopper
   can reach mid-trip.
4. **Deleting a cache row deletes only the row.** It does **not** cascade to
   un-stamp Items already carrying that `section_id`. This is safe because the
   cache outlives items: bought items are removed on End trip, and the name is
   re-added fresh (`section_id` nil) next trip, so it re-resolves against the
   corrected cache with no extra machinery. The one thing given up — a delete does
   not move an item that is *currently on-screen* mid-trip — is exactly the case
   we decided never happens (rule 1); the mid-trip escape hatch is rename.

## Rejected alternative

Keeping ADR-0002's per-item `source: :user` override with a Shopper-facing
"move this to another section" control was the obvious path and was rejected. It
optimises the wrong moment (mid-trip, basket in hand) and the wrong grain (one
item, not the rule), and it leaves the *next* identical name still miscategorised
until it too is hand-moved. Hint-editing fixes the cohort once; overriding fixes
one item forever-repeatedly.
