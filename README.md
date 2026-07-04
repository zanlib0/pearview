# Pearview

Pearview is a shopping-list app for a two-person household whose distinguishing feature is a route-ordered, AI-categorised list: items are grouped and ordered by the sections of whichever store the shopper picks, so the list follows the walk through that store.

One person - the operator - fills the list at home. The other - the shopper - picks a store and runs the list, which arrives already sorted into the store's aisles. A small LLM does the categorising: never-seen item names are sorted into the store's route sections once, cached, and served free and instant from then on. User corrections always win and are never overwritten.

See [`CONTEXT.md`](./CONTEXT.md) for the bounded context and ubiquitous language, and [`docs/adr/`](./docs/adr/) for the architecture decisions behind it.

The coding is mostly hands-off, only correcting styles from time to time.

## Stack

| Layer | Choice |
|-------|--------|
| Backend | Elixir / [Phoenix](https://www.phoenixframework.org/) 1.8 |
| Frontend | Server-rendered HEEx + [HTMX](https://htmx.org/) 2 |
| Design system | [Masthead](https://github.com/zanlib0/masthead), a custom editorial design system |
| Database | SQLite via [ecto_sqlite3](https://hex.pm/packages/ecto_sqlite3) |
| AI categorisation | [OpenRouter](https://openrouter.ai/) (OpenAI-compatible) calling `deepseek/deepseek-v4-flash` via [Req](https://hex.pm/packages/req), forced through a tool call |

## Development

```sh
mix setup          # install deps, create + migrate the SQLite DB, run seeds
mix phx.server     # http://localhost:4000  (or: iex -S mix phx.server)
```

The shopper view lives at [`/shopper`](http://localhost:4000/shopper); the operator's list is at [`/`](http://localhost:4000/).

AI categorisation reads its credentials from the environment at call time:

| Variable | Purpose | Default |
|----------|---------|---------|
| `OPENROUTER_API_KEY` | OpenRouter API key | _(required for live categorising)_ |
| `OPENROUTER_MODEL` | Override the model | `deepseek/deepseek-v4-flash` |

Without a key the app still runs - items simply stay uncategorised in *Other* until a key is present (categorisation retries on the next view-open, see [ADR-0002](./docs/adr/0002-categorization-cache-not-items.md) and [ADR-0003](./docs/adr/0003-async-categorisation-on-open.md)). Tests route every OpenRouter call through `Req.Test`, so they never hit the network.

## Testing

```sh
mix test           # full suite against an isolated SQLite test DB
mix precommit      # compile (warnings as errors), check unused deps, format, test
```

`mix precommit` must pass before any change is considered done.

## How it fits together

- **`Pearview.Shopping`** - the domain core: stores, sections (the route), trips, items, and the categorisation cache.
- **`Pearview.AI`** - the OpenRouter boundary. One synchronous, batched call that sorts grocery names into a store's sections; never raises, returning `{:error, _}` so callers can leave items uncategorised and retry later.
- **`PearviewWeb`** - Phoenix controllers returning HTML fragments that HTMX swaps in place, no full-page reloads.

Currently deployed in production on a homelab, behind Cloudflare Access. Code hosted on self-hosted Gitea instance, using Gitea CI and Docker container registry. Deployed using Portainer.
