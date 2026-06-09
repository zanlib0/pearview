defmodule Pearview.Shopping do
  @moduledoc """
  The Shopping context: all data access for the shared shopping list — Stores,
  their route Sections, and the Items on the list.

  Later phases extend this context with item add/edit/delete and the AI
  categorisation orchestration (see `docs/prd/00-minimal-ai-shopping-loop.md`).
  For Phase 1 the read path is enough.
  """

  import Ecto.Query, warn: false

  alias Pearview.Repo
  alias Pearview.Shopping.{CategorizeUncategorized, Item, Section}

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
  open — cache first, LLM second. Delegates to
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
