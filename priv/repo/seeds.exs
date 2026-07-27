# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It seeds the shared stores, each with its own Route (ordered Sections with
# hints), and points the Selected store at the first of them. The Route
# definitions themselves live in `Pearview.Release.seed_data/0` so dev and
# production seed from one source. This script first clears the existing data so
# re-running is a clean reset — safe for `mix ecto.setup` / `mix ecto.reset`.
#
# NOTE: this is destructive (it deletes Items). In production, use the
# idempotent `Pearview.Release.seed/0` instead, which only inserts what's
# missing and never deletes.

alias Pearview.Repo
alias Pearview.Shopping.{Item, Section, Store}

# Start clean so re-seeding is idempotent.
Repo.delete_all(Item)
Repo.delete_all(Section)
Repo.delete_all(Store)

Pearview.Release.seed_data()
