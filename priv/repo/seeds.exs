# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It seeds the single shared store, its Route (ordered Sections with hints), and
# a handful of uncategorised Items. Re-running it resets that data, so it is safe
# to run from `mix ecto.setup` and `mix ecto.reset`.

alias Pearview.Repo
alias Pearview.Shopping.{Item, Section, Store}

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

# A few Items on the shared list, in a mix of states so the list view shows
# each one. Uncategorised (no section yet) — categorisation runs in the Shopper
# view in a later phase.
[
  {"Bananas", :pending},
  {"Oat milk", :pending},
  {"Sourdough loaf", :checked},
  {"Free-range eggs", :pending},
  {"Spaghetti", :checked},
  {"Capers", :not_available},
  {"Bin bags", :pending}
]
|> Enum.each(fn {name, status} ->
  Repo.insert!(%Item{
    name: name,
    normalized_name: normalize.(name),
    status: status
  })
end)
