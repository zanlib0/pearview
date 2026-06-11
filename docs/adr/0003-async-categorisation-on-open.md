# Categorisation never blocks the first paint

The Shopper view is categorised cache-first (ADR-0002): repeat opens are free,
but the *first* open of a genuinely-new name still has to pay the LLM. Doing that
synchronously means GET `/shopper` waits on the full OpenRouter round-trip before
it paints — a noticeable freeze, verified by hand in #6.

So the orchestration seam is split. The **cache pass stays synchronous**: a
cache-hit name is cheap DB work and still opens already placed. Only the
**cache-missed LLM resolution moves to an unlinked, supervised background task**
(a `Task.Supervisor` in the tree). The view renders immediately from current
state; the missed items sit in Other under a static **Categorising** note (a
Masthead `.cancel-stamp`) and are picked up on the **next** request for the view.
There is no polling and no in-page swap.

This had to land before #7 (refetch on visibility-unlock): #7 re-requests the
current view on every focus/unlock, so with categorisation still synchronous each
refocus that found new items would block on the LLM — turning a freshness feature
into a recurring freeze. Decoupling render from resolution keeps #7's refetch
instant.

## The rules, in plain words

1. **Cache pass synchronous, LLM pass backgrounded.** On view-open the cache is
   resolved inline and stamps its hits before the page renders. If — and only if
   — names remain that the cache has never seen, an unlinked task is started for
   them and the orchestration reports `:categorising`; otherwise `:idle`.
2. **The task is supervised and unlinked.** It runs under `Pearview.TaskSupervisor`,
   not linked to the request process, so a phone-lock right after open (which
   kills the request connection) can't kill an in-flight OpenRouter call.
3. **Results appear on the next request, not via a live swap.** While the task
   runs, missed items stay in Other and the view shows the Categorising note.
   The stamped sections are read on the next view-open — near-automatic once #7
   refetches on every unlock.
4. **The error path is unchanged (ADR-0002 rule 4).** A failed call writes no
   cache rows and leaves items in Other; the note simply shows again on the next
   open while those names remain unresolved, and that open retries.

## Rejected alternatives

Both were considered in triage and rejected as more machinery than a 2-user app
needs:

- **An `hx-trigger="load"` POST region** that categorises after first paint: ties
  the LLM call to a client connection (a phone-lock right after open can kill it
  mid-flight), and under #7's refetch-on-focus it re-fires on every refocus,
  duplicating OpenRouter calls.
- **A poll-until-done endpoint** (background task + `hx-trigger="every 2s"` +
  286-to-stop): works, but is more moving parts than is warranted once #7
  refetches on every unlock anyway.
