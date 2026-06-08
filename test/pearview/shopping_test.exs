defmodule Pearview.ShoppingTest do
  use Pearview.DataCase, async: true

  alias Pearview.Shopping
  alias Pearview.Shopping.Item

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

  describe "normalize_name/1" do
    test "lowercases, trims, and collapses internal whitespace" do
      assert Shopping.normalize_name("  Oat   MILK ") == "oat milk"
      assert Shopping.normalize_name("Bananas") == "bananas"
    end
  end
end
