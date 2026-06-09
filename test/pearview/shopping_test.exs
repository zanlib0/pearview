defmodule Pearview.ShoppingTest do
  use Pearview.DataCase, async: true

  alias Pearview.Shopping
  alias Pearview.Shopping.{Item, Section, Store}

  describe "list_items/0" do
    test "returns the persisted items in insertion order" do
      %Item{name: "Bananas", normalized_name: "bananas", status: :pending}
      |> Repo.insert!()

      %Item{name: "Oat milk", normalized_name: "oat milk", status: :pending}
      |> Repo.insert!()

      names = Shopping.list_items() |> Enum.map(& &1.name)

      assert names == ["Bananas", "Oat milk"]
    end

    test "returns an empty list when there are no items" do
      assert Shopping.list_items() == []
    end
  end

  describe "add_item/1" do
    test "creates a pending, uncategorised item from the raw name" do
      assert {:ok, %Item{} = item} = Shopping.add_item(%{"name" => "Oat milk"})

      assert item.name == "Oat milk"
      assert item.status == :pending
      assert item.section_id == nil
      assert Repo.get(Item, item.id)
    end

    test "derives normalized_name: lowercased, trimmed, internal whitespace collapsed" do
      assert {:ok, item} = Shopping.add_item(%{"name" => "  Oat   MILK\tcarton "})

      assert item.name == "  Oat   MILK\tcarton "
      assert item.normalized_name == "oat milk carton"
    end

    test "rejects a blank name" do
      assert {:error, changeset} = Shopping.add_item(%{"name" => "   "})
      refute changeset.valid?
    end
  end

  describe "update_item/2" do
    test "renames the item and re-derives normalized_name from the new name" do
      {:ok, item} = Shopping.add_item(%{"name" => "milk"})

      assert {:ok, updated} = Shopping.update_item(item, %{"name" => "  Oat   MILK "})

      assert updated.id == item.id
      assert updated.name == "  Oat   MILK "
      assert updated.normalized_name == "oat milk"
      assert Repo.get(Item, item.id).normalized_name == "oat milk"
    end

    test "leaves status and section untouched when renaming" do
      item = Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :checked})

      assert {:ok, updated} = Shopping.update_item(item, %{"name" => "oat milk"})

      assert updated.status == :checked
      assert updated.section_id == nil
    end

    test "rejects a blank name and leaves the item unchanged" do
      {:ok, item} = Shopping.add_item(%{"name" => "milk"})

      assert {:error, changeset} = Shopping.update_item(item, %{"name" => "   "})
      refute changeset.valid?
      assert Repo.get(Item, item.id).name == "milk"
    end
  end

  describe "delete_item/1" do
    test "hard-deletes the item from the database" do
      {:ok, item} = Shopping.add_item(%{"name" => "milk"})

      assert {:ok, _deleted} = Shopping.delete_item(item)
      assert Repo.get(Item, item.id) == nil
    end
  end

  describe "list_grouped_for_shopper/0" do
    setup do
      store = Repo.insert!(%Store{name: "Test Store"})
      dairy = Repo.insert!(%Section{name: "Dairy", position: 2, store_id: store.id})
      produce = Repo.insert!(%Section{name: "Produce", position: 1, store_id: store.id})
      %{store: store, dairy: dairy, produce: produce}
    end

    test "returns sections in route (position) order with Other pinned last", %{
      dairy: dairy,
      produce: produce
    } do
      Repo.insert!(%Item{
        name: "Milk",
        normalized_name: "milk",
        status: :pending,
        section_id: dairy.id
      })

      Repo.insert!(%Item{
        name: "Bananas",
        normalized_name: "bananas",
        status: :pending,
        section_id: produce.id
      })

      Repo.insert!(%Item{name: "Lightbulbs", normalized_name: "lightbulbs", status: :pending})

      groups = Shopping.list_grouped_for_shopper()

      # Match by id — pinning the full struct would fail because the query
      # returns structs with preloaded items, which differ from the setup stubs.
      assert [{%{id: p_id}, _}, {%{id: d_id}, _}, {:other, _}] = groups
      assert p_id == produce.id
      assert d_id == dairy.id
    end

    test "items within each section are ordered by insertion time", %{dairy: dairy} do
      %{id: first_id} =
        Repo.insert!(%Item{
          name: "Milk",
          normalized_name: "milk",
          status: :pending,
          section_id: dairy.id
        })

      %{id: second_id} =
        Repo.insert!(%Item{
          name: "Cheese",
          normalized_name: "cheese",
          status: :pending,
          section_id: dairy.id
        })

      [{%{id: s_id}, items}] = Shopping.list_grouped_for_shopper()

      assert s_id == dairy.id
      assert [^first_id, ^second_id] = Enum.map(items, & &1.id)
    end

    test "items with nil section_id appear in the Other bucket, not in any section", %{
      produce: produce
    } do
      Repo.insert!(%Item{
        name: "Bananas",
        normalized_name: "bananas",
        status: :pending,
        section_id: produce.id
      })

      Repo.insert!(%Item{name: "Capers", normalized_name: "capers", status: :pending})

      groups = Shopping.list_grouped_for_shopper()

      assert [{%{id: p_id}, produce_items}, {:other, other_items}] = groups
      assert p_id == produce.id
      assert Enum.map(produce_items, & &1.name) == ["Bananas"]
      assert Enum.map(other_items, & &1.name) == ["Capers"]
    end

    test "sections with no items are omitted from the result", %{dairy: dairy} do
      Repo.insert!(%Item{
        name: "Milk",
        normalized_name: "milk",
        status: :pending,
        section_id: dairy.id
      })

      groups = Shopping.list_grouped_for_shopper()

      names =
        Enum.map(groups, fn {head, _} -> if head == :other, do: "Other", else: head.name end)

      refute "Produce" in names
      assert "Dairy" in names
    end

    test "returns an empty list when there are no items" do
      assert Shopping.list_grouped_for_shopper() == []
    end

    test "omits the Other bucket when all items have a section", %{produce: produce} do
      Repo.insert!(%Item{
        name: "Bananas",
        normalized_name: "bananas",
        status: :pending,
        section_id: produce.id
      })

      groups = Shopping.list_grouped_for_shopper()

      refute Enum.any?(groups, fn {head, _} -> head == :other end)
    end
  end

  describe "cycle_item_status/1" do
    test "advances pending to checked" do
      {:ok, item} = Shopping.add_item(%{"name" => "milk"})

      assert {:ok, %{status: :checked}} = Shopping.cycle_item_status(item)
    end

    test "advances checked to not_available" do
      item = Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :checked})

      assert {:ok, %{status: :not_available}} = Shopping.cycle_item_status(item)
    end

    test "advances not_available back to pending" do
      item = Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :not_available})

      assert {:ok, %{status: :pending}} = Shopping.cycle_item_status(item)
    end

    test "persists the new status to the database" do
      {:ok, item} = Shopping.add_item(%{"name" => "milk"})
      {:ok, _} = Shopping.cycle_item_status(item)

      assert Repo.get!(Item, item.id).status == :checked
    end
  end

  describe "end_trip/0" do
    test "hard-deletes all checked items" do
      Repo.insert!(%Item{name: "Milk", normalized_name: "milk", status: :checked})
      Repo.insert!(%Item{name: "Eggs", normalized_name: "eggs", status: :checked})
      {:ok, pending} = Shopping.add_item(%{"name" => "Bread"})

      Shopping.end_trip()

      remaining = Shopping.list_items() |> Enum.map(& &1.id)
      assert pending.id in remaining
      assert length(remaining) == 1
    end

    test "resets not_available items to pending" do
      item = Repo.insert!(%Item{name: "Milk", normalized_name: "milk", status: :not_available})

      Shopping.end_trip()

      assert Repo.get!(Item, item.id).status == :pending
    end

    test "leaves pending items untouched" do
      {:ok, item} = Shopping.add_item(%{"name" => "Bread"})

      Shopping.end_trip()

      assert Repo.get!(Item, item.id).status == :pending
    end

    test "handles a mix: deletes checked, resets not_available, preserves pending" do
      checked = Repo.insert!(%Item{name: "A", normalized_name: "a", status: :checked})
      na = Repo.insert!(%Item{name: "B", normalized_name: "b", status: :not_available})
      {:ok, pending} = Shopping.add_item(%{"name" => "C"})

      Shopping.end_trip()

      assert Repo.get(Item, checked.id) == nil
      assert Repo.get!(Item, na.id).status == :pending
      assert Repo.get!(Item, pending.id).status == :pending
    end

    test "returns :ok" do
      assert Shopping.end_trip() == :ok
    end
  end

  describe "normalize_name/1" do
    test "lowercases, trims, and collapses internal whitespace" do
      assert Shopping.normalize_name("  Oat   MILK ") == "oat milk"
      assert Shopping.normalize_name("Bananas") == "bananas"
    end
  end
end
