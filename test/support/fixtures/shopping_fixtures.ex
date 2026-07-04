defmodule Pearview.ShoppingFixtures do
  @moduledoc """
  Shared arrange-phase helpers for `Pearview.Shopping` tests: inserting Items
  directly (bypassing `Shopping.add_item/1`) and standing up the canonical
  two-section test store.
  """

  alias Pearview.Repo
  alias Pearview.Shopping
  alias Pearview.Shopping.{Item, Section, Store}

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
