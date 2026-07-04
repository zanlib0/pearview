# Categorisation knowledge lives in the cache, not on items

> **Partially superseded by ADR-0004.** Rule 1's "a user correction (`source =
> user`) always wins" no longer holds: per-item overrides were dropped in favour
> of editing Section hints. Everything else below still stands.


Items get deleted: **End trip** removes every checked item, and the Operator
deletes freely. If the AI's placements lived only on item rows (`section_id`),
every trip would throw away knowledge we paid the LLM for, and next week's
"milk" would cost another call. So the durable record of "where does this thing
go in this store" is the **categorizations** table, pulled forward from Phase 2
into the first AI slice (#6). An item's `section_id` is just a copy taken from
the cache — safe to lose, cheap to restamp.

## The rules, in plain words

1. **One row per (store, normalized name).** The row says which Section that
   name belongs to in that store, and who said so (`source`: `ai` or `user`).
   The `user` value isn't written until Phase 2's corrections, but the column
   exists from day one because the rule "a user correction always wins and is
   never overwritten by AI" needs somewhere to live.
2. **Cache first, LLM second.** When the Shopper opens the view, every
   uncategorised item is first resolved against the cache. Only names the cache
   has *never seen* go to the LLM, in one batched call.
3. **Every successful LLM answer is written back** to the cache, including the
   failures to place: if the model couldn't put a name in any real section, we
   write a row with *no* section ("asked, unplaced"). That item sits in Other
   and is never sent again — repeat view-opens cost nothing.
4. **Errors write nothing.** An HTTP failure or unparseable response leaves the
   cache untouched, so the next view-open simply retries. This is the line
   between "the model said no" (cache it) and "we never got an answer" (don't).
   If errors wrote "unplaced" rows, one outage would permanently glue the whole
   list into Other.
5. **Renaming is the retry button.** A rename re-derives `normalized_name`,
   which is a new cache key, and resets the item's `section_id` to nil — so the
   item re-resolves on the next view-open (cache hit if the new name is known,
   LLM otherwise). Invariant: *an item's placement is always the placement of
   its current name.* There is no other retry mechanism, on purpose.
6. **The trigger is view-open, permanently — not trip start.** The Operator
   adds items mid-trip; those must get placed the next time the Shopper's
   screen wakes, not on the next trip. The cache is what makes this trigger
   affordable: with every known name a free hit, "categorise on every open"
   really means "call the LLM only when something genuinely new appeared".

## Rejected alternative

Categorising once at trip start (a "session start" event) was considered and
rejected: it reads as the temporally natural moment, but it strands every
mid-trip addition in Other for the rest of the trip, which is exactly when the
Shopper can't re-sort the list themselves.
