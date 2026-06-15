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
  {"Hobby and Homeware",
   "technology, car supplies, lightbulbs, hobby, homeware, plates, glasses"},
  {"Bakery", "bread, rolls, bagels, pastries, tortillas, crispbread"},
  {"World cuisine", "Japanese, Chinese, Thai, Indian, pasta, noodles"},
  {"Bio", "Vegan food, special diets, gluten-free, bio, tofu, coconut yoghurt"},
  {"Deli", "Sliced meats, cheese"},
  {"Meat", "Raw meat"},
  {"Produce", "Fruits, vegetables"},
  {"Bulk pantry", "Nuts, cereals, grains, kasha, rice"},
  {"Tinned food", "Canned chickpeas, beans, peas, olives, fish"},
  {"Spices", "Salt, pepper, spices"},
  {"Tomato products", "Passata, tomato puree, tinned tomatoes, ketchup"},
  {"Alcohol", "Beer, wine, liquor"},
  {"Sweets and Baking",
   "Tea, coffee, sweets, baking ingredients - soda bicarb, yeast, sourdough starter, jams, honeys, flours"},
  {"Frozen", "Fish, frozen foods, ready meals"},
  {"Dairy", "Milk, butter, yoghurt, quark"}
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
