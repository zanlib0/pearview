defmodule Pearview.ShoppingFixtures do
  @moduledoc """
  Shared arrange-phase helpers for `Pearview.Shopping` tests: inserting Items
  directly (bypassing `Shopping.add_item/1`) and standing up the canonical
  two-section test store.
  """

  import Ecto.Query, only: [from: 2]

  alias Pearview.Repo
  alias Pearview.Shopping
  alias Pearview.Shopping.{Categorization, Item, Section, Store}

  @doc """
  Inserts an Item, deriving `normalized_name` from `name` the same way
  `Shopping.add_item/1` does. Opts: `:status` (default `:pending`),
  `:section_id` (default `nil`).
  """
  def item!(name, opts \\ []) do
    Repo.insert!(%Item{
      name: name,
      normalized_name: Shopping.normalize_name(name),
      status: Keyword.get(opts, :status, :pending),
      section_id: Keyword.get(opts, :section_id)
    })
  end

  @doc """
  Inserts a bare Store (no Sections) with the given name.
  """
  def store!(name), do: Repo.insert!(%Store{name: name})

  @doc """
  Inserts a Section on a Store's Route. Opts: `:position` (default: appended
  after the store's current last stop), `:hints` (default `nil`).
  """
  def section!(%Store{} = store, name, opts \\ []) do
    Repo.insert!(%Section{
      store_id: store.id,
      name: name,
      position: Keyword.get_lazy(opts, :position, fn -> next_position(store) end),
      hints: Keyword.get(opts, :hints)
    })
  end

  defp next_position(%Store{id: store_id}) do
    last =
      Repo.one(from s in Section, where: s.store_id == ^store_id, select: max(s.position))

    (last || 0) + 1
  end

  @doc """
  Inserts a Categorization cache row for a store. Opts: `:section_id` (default
  `nil`, i.e. the "asked, unplaced" row).
  """
  def categorization!(%Store{} = store, normalized_name, opts \\ []) do
    Repo.insert!(%Categorization{
      store_id: store.id,
      normalized_name: normalized_name,
      section_id: Keyword.get(opts, :section_id),
      source: :ai
    })
  end

  @doc """
  Inserts the canonical two-section test store: "Produce" (position 1) and
  "Dairy & Eggs" (position 2), each with AI hints. Returns
  `%{store: store, produce: produce, dairy: dairy}`.
  """
  def store_with_sections! do
    store = Repo.insert!(%Store{name: "Test Store"})

    produce =
      Repo.insert!(%Section{name: "Produce", position: 1, store_id: store.id, hints: "fruit"})

    dairy =
      Repo.insert!(%Section{
        name: "Dairy & Eggs",
        position: 2,
        store_id: store.id,
        hints: "milk"
      })

    %{store: store, produce: produce, dairy: dairy}
  end

  @doc "ExUnit setup callback: `setup :store_with_route` wraps `store_with_sections!/0`."
  def store_with_route(_context), do: store_with_sections!()
end
