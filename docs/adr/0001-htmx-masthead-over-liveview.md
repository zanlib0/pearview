# Server-rendered HEEx + HTMX + Masthead, not LiveView

The app renders plain server-side HEEx from Phoenix controllers (dead views),
uses **HTMX** for interactivity (fragment swaps over plain HTTP), and styles with
**Masthead** CSS — no JS build step. We deliberately do **not** use Phoenix
LiveView, despite it being the framework default and despite `phoenix_live_view`
appearing as a transitive dependency in `mix.exs`.

The project was generated with `mix phx.new . --database sqlite3 --no-assets
--no-dashboard --no-gettext --no-live --no-mailer --install`, which omits the
LiveView and asset-pipeline wiring on purpose.

Why: this is a 2-user homelab app with no scaling pressure. The liveness
requirement is modest ("refetch on unlock" + a decaying poll), which plain HTTP
serves directly. Avoiding the persistent socket keeps the system stateless and
simple, and the author prefers HTMX's request/response model over LiveView. The
things LiveView would have bought us (server-rendered HTML, no SPA, no JS build)
are all retained without it.

Consequence: a future reader who sees `phoenix_live_view` in deps or the
auto-generated `AGENTS.md` (which is full of LiveView conventions) should ignore
both — they are scaffolding artifacts, not the chosen architecture.
