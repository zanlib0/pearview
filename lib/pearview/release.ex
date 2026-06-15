defmodule Pearview.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :pearview

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Seeds the single shared Store and its Route (ordered Sections). Idempotent:
  inserts only what is missing and never deletes anything, so it is safe to run
  on every boot or by hand. Started under `with_repo` so it works from a release
  where the app's supervision tree isn't running.
  """
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _repo -> seed_data() end)
    end
  end

  # The actual inserts, assuming the repo is already running. Public so the dev
  # seeds script (priv/repo/seeds.exs) can reuse it as the single source of the
  # Route definition.
  @doc false
  def seed_data do
    alias Pearview.Repo
    alias Pearview.Shopping.{Section, Store}

    store = Repo.get_by(Store, name: "Tesco Extra") || Repo.insert!(%Store{name: "Tesco Extra"})

    route()
    |> Enum.with_index(1)
    |> Enum.each(fn {{name, hints}, position} ->
      unless Repo.get_by(Section, store_id: store.id, name: name) do
        Repo.insert!(%Section{store_id: store.id, name: name, position: position, hints: hints})
      end
    end)

    :ok
  end

  # The Route: sections in the order the Shopper walks the store.
  defp route do
    [
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
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
