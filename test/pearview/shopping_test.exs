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
end
