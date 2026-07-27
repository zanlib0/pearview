defmodule Pearview.Shopping do
  @moduledoc """
  The Shopping context: all data access for the shared shopping list — Stores,
  their route Sections, and the Items on the list.

  It covers the Operator's list editing, the Shopper's route-ordered read path,
  the AI categorisation orchestration (see
  `docs/prd/00-minimal-ai-shopping-loop.md`) and the Manage surface's Store,
  Route and categorisation-cache maintenance (see
  `docs/prd/01-multi-store-and-manage.md`).
  """

  import Ecto.Query, warn: false

  alias Pearview.Repo
  alias Pearview.Shopping.{Categorization, CategorizeUncategorized, Item, Section, Store}

  @doc """
  Returns every Store, in name order — the Manage view's store list and (later)
  the Shopper's store picker.
  """
  def list_stores do
    Store
    |> order_by(asc: :name, asc: :id)
    |> Repo.all()
  end

  @doc """
  Fetches a single Store by id, raising `Ecto.NoResultsError` if it is missing.
  """
  def get_store!(id), do: Repo.get!(Store, id)

  @doc """
  Creates a Store from a name typed by the Operator in Manage. The new Store has
  no Sections yet — its Route is built separately.
  """
  def create_store(attrs) when is_map(attrs) do
    %Store{}
    |> Store.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Renames a Store.
  """
  def update_store(%Store{} = store, attrs) when is_map(attrs) do
    store
    |> Store.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Store. Its Sections and its cached Categorizations go with it (both
  FKs cascade), so no stale knowledge lingers for a store we no longer shop.
  Items keep their place on the list with `section_id` nilified, so they
  re-resolve against whichever store is shopped next.
  """
  def delete_store(%Store{} = store), do: Repo.delete(store)

  @doc """
  Returns a Store's Sections in route (position) order — the Route as the
  Shopper walks it. Accepts the Store or its id.
  """
  def list_sections(%Store{id: store_id}), do: list_sections(store_id)

  def list_sections(store_id) do
    Section
    |> where([s], s.store_id == ^store_id)
    |> order_by(asc: :position, asc: :id)
    |> Repo.all()
  end

  @doc """
  Fetches a single Section by id, raising `Ecto.NoResultsError` if it is missing.
  """
  def get_section!(id), do: Repo.get!(Section, id)

  @doc """
  Adds a Section to the end of a Store's Route. `position` is derived — the new
  stop is appended after the store's current last one — so the caller only
  supplies `store_id`, `name` and (optionally) `hints`.
  """
  def create_section(attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    %Section{}
    |> Section.changeset(Map.put(attrs, "position", next_position(attrs["store_id"])))
    |> Repo.insert()
  end

  defp next_position(nil), do: 1

  defp next_position(store_id) do
    last = Repo.one(from s in Section, where: s.store_id == ^store_id, select: max(s.position))

    (last || 0) + 1
  end

  @doc """
  Renames a Section and/or rewrites its `hints` — the example products the AI is
  given as context for that stop (ADR-0004: corrections are hint edits, never
  per-item overrides). Emptying the hints field clears them.
  """
  def update_section(%Section{} = section, attrs) when is_map(attrs) do
    section
    |> Section.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves a Section one stop earlier (`:up`) or later (`:down`) in its Store's
  Route by swapping `position` values with its neighbour. Moving the first stop
  up (or the last one down) is a no-op. Returns `{:ok, sections}` with the
  store's whole Route in its new order.
  """
  def move_section(%Section{} = section, direction) when direction in [:up, :down] do
    case neighbour(section, direction) do
      nil ->
        {:ok, list_sections(section.store_id)}

      %Section{} = neighbour ->
        {:ok, _} =
          Repo.transaction(fn ->
            # Positions are only ever read in order, so a transient collision
            # inside the transaction is harmless — no unique index to dodge.
            Repo.update!(Ecto.Changeset.change(section, position: neighbour.position))
            Repo.update!(Ecto.Changeset.change(neighbour, position: section.position))
          end)

        {:ok, list_sections(section.store_id)}
    end
  end

  # The adjacent stop on the Route: the nearest section before (`:up`) or after
  # (`:down`) this one in position order, or nil at either end of the walk.
  defp neighbour(%Section{store_id: store_id, position: position}, :up) do
    Section
    |> where([s], s.store_id == ^store_id and s.position < ^position)
    |> order_by(desc: :position, desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  defp neighbour(%Section{store_id: store_id, position: position}, :down) do
    Section
    |> where([s], s.store_id == ^store_id and s.position > ^position)
    |> order_by(asc: :position, asc: :id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Removes a stop from a Store's Route.

  Its Items stay on the list with `section_id` nilified, so they re-resolve on
  the next Shopper-view open instead of vanishing with the section. Its cached
  Categorizations are **deleted** (FK cascade) rather than left as "unplaced",
  so those names get re-asked against the shortened Route. Both behaviours come
  from the foreign keys; see the migrations.
  """
  def delete_section(%Section{} = section), do: Repo.delete(section)

  @doc """
  Returns a Store's categorisation cache — every name the app has an answer for
  at that store — in name order, each row's Section preloaded. Accepts the Store
  or its id.

  **Unplaced** rows (`section_id` nil: the AI was asked and could not file the
  name, so it falls through to Other and is never re-asked) are included. They
  are precisely what the Operator comes here to find.
  """
  def list_categorizations(%Store{id: store_id}), do: list_categorizations(store_id)

  def list_categorizations(store_id) do
    Categorization
    |> where([c], c.store_id == ^store_id)
    |> order_by(asc: :normalized_name, asc: :id)
    |> preload(:section)
    |> Repo.all()
  end

  @doc """
  Fetches a single Categorization by id, raising `Ecto.NoResultsError` if it is
  missing.
  """
  def get_categorization!(id), do: Repo.get!(Categorization, id)

  @doc """
  Prunes one row from the categorisation cache, so the name is resolved afresh —
  against the store's current hints — the next time it appears.

  The delete stops at the row: Items already stamped with that Section keep it
  (ADR-0004 rule 4, no cascade). The cache outlives the items, so the correction
  lands on the next trip, when the name is re-added uncategorised.
  """
  def delete_categorization(%Categorization{} = categorization),
    do: Repo.delete(categorization)

  @doc """
  Returns the shopping list grouped for the Shopper view: a list of
  `{%Section{}, items}` tuples in route (position) order, each containing that
  section's items ordered by insertion time, followed by a single
  `{:other, items}` tuple (pinned last) for items that have no section yet.
  Empty sections and an empty Other bucket are omitted.
  """
  def list_grouped_for_shopper do
    item_query = from(i in Item, order_by: [asc: i.inserted_at, asc: i.id])

    sections =
      Section
      |> order_by(asc: :position)
      |> preload(items: ^item_query)
      |> Repo.all()

    other_items =
      Item
      |> where([i], is_nil(i.section_id))
      |> order_by(asc: :inserted_at, asc: :id)
      |> Repo.all()

    section_groups =
      sections
      |> Enum.map(&{&1, &1.items})
      |> Enum.reject(fn {_s, items} -> items == [] end)

    if other_items == [] do
      section_groups
    else
      section_groups ++ [{:other, other_items}]
    end
  end

  @doc """
  Resolves every uncategorised Item against the store's Route on Shopper-view
  open — cache pass synchronous, LLM pass in a background task. Returns
  `:categorising` when a background run was started (so the view shows the
  "Categorising" note) or `:idle` otherwise. Delegates to
  `Pearview.Shopping.CategorizeUncategorized`; see that module for the rules.
  """
  defdelegate categorize_uncategorized, to: CategorizeUncategorized, as: :call

  @doc """
  Returns every Item on the shared list, in insertion order.
  """
  def list_items do
    Item
    |> order_by(asc: :inserted_at, asc: :id)
    |> Repo.all()
  end

  @doc """
  Fetches a single Item by id, raising `Ecto.NoResultsError` if it is missing.
  """
  def get_item!(id), do: Repo.get!(Item, id)

  @doc """
  Adds an item to the shared list from a raw name typed by the Operator.

  The `name` is stored verbatim; `normalized_name` is derived from it (see
  `normalize_name/1`). New items start `pending` and uncategorised
  (`section_id` nil) — the Shopper view assigns a Section in a later slice.
  """
  def add_item(attrs) when is_map(attrs) do
    name = Map.get(attrs, "name", "")

    %Item{}
    |> Item.changeset(%{name: name, normalized_name: normalize_name(name)})
    |> Repo.insert()
  end

  @doc """
  Renames an existing item from a raw name typed by the Operator, re-deriving
  `normalized_name` from the new text (see `normalize_name/1`) and **resetting
  `section_id` to nil** so the item re-resolves on the next Shopper-view open.

  Renaming is the retry button: an item's placement is always the placement of
  its current normalized name (ADR-0002 rule 5). Status is untouched.
  """
  def update_item(%Item{} = item, attrs) when is_map(attrs) do
    name = Map.get(attrs, "name", item.name)

    item
    |> Item.changeset(%{name: name, normalized_name: normalize_name(name), section_id: nil})
    |> Repo.update()
  end

  @doc """
  Removes an item from the shared list. This is a hard delete (`Repo.delete`)
  """
  def delete_item(%Item{} = item), do: Repo.delete(item)

  @next_status %{pending: :checked, checked: :not_available, not_available: :pending}

  @doc """
  Advances an Item's status one step around the tri-state cycle:
  pending → checked → not_available → pending.
  """
  def cycle_item_status(%Item{} = item) do
    next = Map.fetch!(@next_status, item.status)

    item
    |> Item.changeset(%{status: next})
    |> Repo.update()
  end

  @doc """
  Ends the current trip:
  - Hard-deletes all checked items (they were bought).
  - Resets not_available items to pending (carryover — the mark is stale).
  - Leaves pending items untouched (still wanted).
  """
  def end_trip do
    Repo.delete_all(from(i in Item, where: i.status == :checked))
    Repo.update_all(from(i in Item, where: i.status == :not_available), set: [status: :pending])
    :ok
  end

  @doc """
  Derives an Item's `normalized_name` (the categorisation cache key) from raw
  text: lowercased, with internal whitespace collapsed to single spaces and the
  ends trimmed.
  """
  def normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
