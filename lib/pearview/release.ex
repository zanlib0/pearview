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
  Seeds the Stores and their Routes (ordered Sections), and points the
  Selected-store singleton at the first of them so a fresh install opens on a
  working route. Idempotent: inserts only what is missing, never deletes
  anything, and never overwrites a selection the Shopper has already made — so
  it is safe to run on every boot or by hand. Started under `with_repo` so it
  works from a release where the app's supervision tree isn't running.
  """
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _repo -> seed_data() end)
    end
  end

  @doc """
  DESTRUCTIVE reset of the seed data: clears Items, the cache, the Routes and the
  Stores, then re-seeds from `seed_data/0`. Use this (not `seed/0`) after editing
  a Route in a way `seed/0` can't reconcile — renamed/reordered/removed
  sections or changed hints. Deleting a Store cascades to its Sections and
  Categorizations; Items survive with their `section_id` nilified, so they get
  re-categorised on the next shopper-view open. The Selected store goes with the
  stores and is seeded afresh.
  """
  def reseed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          Pearview.Repo.delete_all(Pearview.Shopping.Categorization)
          Pearview.Repo.delete_all(Pearview.Shopping.Store)
          seed_data()
        end)
    end
  end

  # The actual inserts, assuming the repo is already running. Public so the dev
  # seeds script (priv/repo/seeds.exs) can reuse it as the single source of the
  # Route definitions.
  @doc false
  def seed_data do
    alias Pearview.Repo
    alias Pearview.Shopping.{Section, Store}

    stores =
      Enum.map(routes(), fn {store_name, route} ->
        store = Repo.get_by(Store, name: store_name) || Repo.insert!(%Store{name: store_name})

        route
        |> Enum.with_index(1)
        |> Enum.each(fn {{name, hints}, position} ->
          unless Repo.get_by(Section, store_id: store.id, name: name) do
            Repo.insert!(%Section{
              store_id: store.id,
              name: name,
              position: position,
              hints: hints
            })
          end
        end)

        store
      end)

    select_first_store(stores)

    :ok
  end

  # Point the Selected store at the first store defined below, so the Shopper
  # view opens on a working route out of the box. A selection already made wins:
  # `seed/0` may run on every boot and must never bounce the Shopper to another
  # store mid-trip.
  defp select_first_store([]), do: :ok

  defp select_first_store([first | _]) do
    alias Pearview.Repo
    alias Pearview.Shopping.Settings

    case Repo.get(Settings, Settings.singleton_id()) do
      %Settings{selected_store_id: store_id} when not is_nil(store_id) ->
        :ok

      _ ->
        Repo.insert!(
          %Settings{id: Settings.singleton_id(), selected_store_id: first.id},
          on_conflict: [set: [selected_store_id: first.id]],
          conflict_target: :id
        )
    end
  end

  # The Routes: for each store, its sections in the order the Shopper walks it.
  # The first store here is the one a fresh install starts out shopping.
  defp routes do
    [
      {"Tesco Extra",
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
         {"Cleaning and Bathroom", "Kitchen roll, toilet paper"},
         {"Frozen", "Fish, frozen foods, ready meals"},
         {"Dairy", "Milk, butter, yoghurt, quark"},
         {"Rossmann", "Drugstore items, baby nappies, powdered dates, carob, biodegradable bags"}
       ]},
      {"Lidl",
       [
         {"Bakery", "Bread, rolls, pastries, baguettes"},
         {"Produce", "Fruits, vegetables, fresh herbs, potatoes"},
         {"Middle aisle", "Tools, clothes, kitchenware, seasonal odds and ends"},
         {"Dairy", "Milk, butter, yoghurt, quark, cream"},
         {"Deli and Meat", "Sliced meats, cheese, raw meat, sausages"},
         {"Frozen", "Frozen vegetables, fish, ready meals, ice cream"},
         {"Pantry", "Pasta, rice, flour, sugar, tinned food, oils, spices"},
         {"Sweets and Snacks", "Chocolate, biscuits, crisps, nuts"},
         {"Drinks", "Water, juice, coffee, tea, beer, wine"},
         {"Household", "Kitchen roll, toilet paper, cleaning supplies, toiletries"}
       ]}
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
