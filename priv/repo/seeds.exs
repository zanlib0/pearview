# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It seeds the single shared store, its Route (ordered Sections with hints), and
# a handful of uncategorised Items. Re-running it resets that data, so it is safe
# to run from `mix ecto.setup` and `mix ecto.reset`.

alias Pearview.Repo
alias Pearview.Shopping.{Item, Section, Store}

import Ecto.Query

# Start clean so re-seeding is idempotent.
Repo.delete_all(Item)
Repo.delete_all(Section)
Repo.delete_all(Store)

normalize = fn name ->
  name
  |> String.trim()
  |> String.downcase()
  |> String.replace(~r/\s+/u, " ")
end

store = Repo.insert!(%Store{name: "Tesco Extra"})

# The Route: sections in the order the Shopper walks the store.
sections = [
  {"Produce", "fruit, vegetables, salad, herbs"},
  {"Bakery", "bread, rolls, bagels, pastries"},
  {"Dairy & Eggs", "milk, cheese, butter, yoghurt, eggs"},
  {"Meat & Fish", "chicken, beef, mince, salmon, bacon"},
  {"Frozen", "frozen peas, ice cream, fish fingers, chips"},
  {"Tinned & Dry Goods", "pasta, rice, tinned tomatoes, beans, flour"},
  {"Household", "washing up liquid, kitchen roll, bin bags, cleaner"}
]

sections
|> Enum.with_index(1)
|> Enum.each(fn {{name, hints}, position} ->
  Repo.insert!(%Section{
    store_id: store.id,
    name: name,
    position: position,
    hints: hints
  })
end)

# Look up the sections we just created so we can assign section_ids by hand.
# This stubs the AI categoriser (slice #6): most items are pre-categorised,
# a couple are left nil so the Shopper view's Other bucket is exercised.
section = fn name ->
  Repo.one!(from s in Section, where: s.name == ^name and s.store_id == ^store.id)
end

[
  {"Bananas", :pending, section.("Produce")},
  {"Oat milk", :pending, section.("Dairy & Eggs")},
  {"Sourdough loaf", :checked, section.("Bakery")},
  {"Free-range eggs", :pending, section.("Dairy & Eggs")},
  {"Spaghetti", :checked, section.("Tinned & Dry Goods")},
  {"Capers", :not_available, nil},
  {"Bin bags", :pending, section.("Household")},
  {"Lightbulbs", :pending, nil}
]
|> Enum.each(fn {name, status, sec} ->
  Repo.insert!(%Item{
    name: name,
    normalized_name: normalize.(name),
    status: status,
    section_id: sec && sec.id
  })
end)
