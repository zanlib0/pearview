defmodule Pearview.ShoppingTest do
  use Pearview.DataCase, async: true

  import Pearview.AIStubs, only: [tool_call_response: 1, stub_ai: 1, refute_ai_called: 0]
  import Pearview.ShoppingFixtures

  alias Pearview.Shopping
  alias Pearview.Shopping.{Categorization, CategorizeUncategorized, Item, Section, Store}

  describe "list_stores/0" do
    test "returns every store in name order" do
      store!("Lidl")
      store!("Aldi")

      assert Shopping.list_stores() |> Enum.map(& &1.name) == ["Aldi", "Lidl"]
    end

    test "returns an empty list when there are no stores" do
      assert Shopping.list_stores() == []
    end
  end

  describe "create_store/1" do
    test "creates a store from the given name" do
      assert {:ok, %Store{} = store} = Shopping.create_store(%{"name" => "Lidl"})

      assert store.name == "Lidl"
      assert Repo.get!(Store, store.id).name == "Lidl"
    end

    test "creates the store with no sections — its route is built separately" do
      assert {:ok, store} = Shopping.create_store(%{"name" => "Lidl"})

      assert Repo.all(from(s in Section, where: s.store_id == ^store.id)) == []
    end

    test "rejects a blank name" do
      assert {:error, changeset} = Shopping.create_store(%{"name" => "   "})
      refute changeset.valid?
      assert Repo.all(Store) == []
    end
  end

  describe "update_store/2" do
    test "renames the store" do
      store = store!("Lidl")

      assert {:ok, updated} = Shopping.update_store(store, %{"name" => "Lidl Nové Butovice"})

      assert updated.id == store.id
      assert Repo.get!(Store, store.id).name == "Lidl Nové Butovice"
    end

    test "rejects a blank name and leaves the store unchanged" do
      store = store!("Lidl")

      assert {:error, changeset} = Shopping.update_store(store, %{"name" => "   "})
      refute changeset.valid?
      assert Repo.get!(Store, store.id).name == "Lidl"
    end
  end

  describe "delete_store/1" do
    test "deletes the store" do
      store = store!("Lidl")

      assert {:ok, _deleted} = Shopping.delete_store(store)
      assert Repo.get(Store, store.id) == nil
    end

    test "discards that store's cached categorizations" do
      %{store: store, produce: produce} = store_with_sections!()
      placed = categorization!(store, "bananas", section_id: produce.id)
      unplaced = categorization!(store, "capers")

      assert {:ok, _deleted} = Shopping.delete_store(store)

      assert Repo.get(Categorization, placed.id) == nil
      assert Repo.get(Categorization, unplaced.id) == nil
    end

    test "leaves another store's cache untouched" do
      %{store: store} = store_with_sections!()
      other = store!("Lidl")
      kept = categorization!(other, "bananas")
      categorization!(store, "bananas")

      assert {:ok, _deleted} = Shopping.delete_store(store)

      assert Repo.get(Categorization, kept.id)
    end

    test "deletes the store's sections but keeps its items, uncategorised" do
      %{store: store, produce: produce} = store_with_sections!()
      item = item!("Bananas", section_id: produce.id)

      assert {:ok, _deleted} = Shopping.delete_store(store)

      assert Repo.get(Section, produce.id) == nil
      assert Repo.get!(Item, item.id).section_id == nil
    end
  end

  describe "list_items/0" do
    test "returns the persisted items in insertion order" do
      item!("Bananas")
      item!("Oat milk")

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

    test "leaves status untouched but resets section_id so the item re-resolves" do
      store = Repo.insert!(%Store{name: "Test Store"})
      dairy = Repo.insert!(%Section{name: "Dairy", position: 1, store_id: store.id})
      item = item!("milk", status: :checked, section_id: dairy.id)

      assert {:ok, updated} = Shopping.update_item(item, %{"name" => "oat milk"})

      assert updated.status == :checked
      assert updated.section_id == nil
      assert Repo.get!(Item, item.id).section_id == nil
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
    setup :store_with_route

    test "returns sections in route (position) order with Other pinned last", %{
      dairy: dairy,
      produce: produce
    } do
      item!("Milk", section_id: dairy.id)
      item!("Bananas", section_id: produce.id)
      item!("Lightbulbs")

      groups = Shopping.list_grouped_for_shopper()

      # Match by id — pinning the full struct would fail because the query
      # returns structs with preloaded items, which differ from the setup stubs.
      assert [{%{id: p_id}, _}, {%{id: d_id}, _}, {:other, _}] = groups
      assert p_id == produce.id
      assert d_id == dairy.id
    end

    test "items within each section are ordered by insertion time", %{dairy: dairy} do
      %{id: first_id} = item!("Milk", section_id: dairy.id)
      %{id: second_id} = item!("Cheese", section_id: dairy.id)

      [{%{id: s_id}, items}] = Shopping.list_grouped_for_shopper()

      assert s_id == dairy.id
      assert [^first_id, ^second_id] = Enum.map(items, & &1.id)
    end

    test "items with nil section_id appear in the Other bucket, not in any section", %{
      produce: produce
    } do
      item!("Bananas", section_id: produce.id)
      item!("Capers")

      groups = Shopping.list_grouped_for_shopper()

      assert [{%{id: p_id}, produce_items}, {:other, other_items}] = groups
      assert p_id == produce.id
      assert Enum.map(produce_items, & &1.name) == ["Bananas"]
      assert Enum.map(other_items, & &1.name) == ["Capers"]
    end

    test "sections with no items are omitted from the result", %{dairy: dairy} do
      item!("Milk", section_id: dairy.id)

      groups = Shopping.list_grouped_for_shopper()

      names =
        Enum.map(groups, fn {head, _} -> if head == :other, do: "Other", else: head.name end)

      refute "Produce" in names
      assert "Dairy & Eggs" in names
    end

    test "returns an empty list when there are no items" do
      assert Shopping.list_grouped_for_shopper() == []
    end

    test "omits the Other bucket when all items have a section", %{produce: produce} do
      item!("Bananas", section_id: produce.id)

      groups = Shopping.list_grouped_for_shopper()

      refute Enum.any?(groups, fn {head, _} -> head == :other end)
    end
  end

  describe "categorize_uncategorized/0" do
    setup :store_with_route

    test "stamps items from a placed cache hit synchronously, reporting :idle", %{
      store: store,
      produce: produce
    } do
      Repo.insert!(%Categorization{
        store_id: store.id,
        normalized_name: "bananas",
        section_id: produce.id,
        source: :ai
      })

      {:ok, item} = Shopping.add_item(%{"name" => "Bananas"})
      refute_ai_called()

      assert Shopping.categorize_uncategorized() == :idle
      assert Repo.get!(Item, item.id).section_id == produce.id
    end

    test "leaves items in Other for an unplaced cache hit, reporting :idle", %{
      store: store
    } do
      Repo.insert!(%Categorization{
        store_id: store.id,
        normalized_name: "capers",
        section_id: nil,
        source: :ai
      })

      {:ok, item} = Shopping.add_item(%{"name" => "Capers"})
      refute_ai_called()

      assert Shopping.categorize_uncategorized() == :idle
      assert Repo.get!(Item, item.id).section_id == nil
    end

    test "stamps cached names synchronously and reports :categorising when names need the LLM",
         %{store: store, produce: produce} do
      Repo.insert!(%Categorization{
        store_id: store.id,
        normalized_name: "bananas",
        section_id: produce.id,
        source: :ai
      })

      {:ok, bananas} = Shopping.add_item(%{"name" => "Bananas"})
      {:ok, milk} = Shopping.add_item(%{"name" => "Milk"})
      stub_ai([])

      assert Shopping.categorize_uncategorized() == :categorising

      # The cache hit is resolved before the call returns; the never-seen name
      # is handed to the background task and is still in Other synchronously.
      assert Repo.get!(Item, bananas.id).section_id == produce.id
      assert Repo.get!(Item, milk.id).section_id == nil

      await_background_tasks()
    end

    test "re-adding a previously-known name resolves from cache, reporting :idle", %{
      store: store,
      dairy: dairy
    } do
      # The cache row survives even though the original item was deleted (End trip).
      Repo.insert!(%Categorization{
        store_id: store.id,
        normalized_name: "milk",
        section_id: dairy.id,
        source: :ai
      })

      {:ok, item} = Shopping.add_item(%{"name" => "Milk"})
      refute_ai_called()

      assert Shopping.categorize_uncategorized() == :idle
      assert Repo.get!(Item, item.id).section_id == dairy.id
    end

    test "is a no-op reporting :idle when there are no uncategorised items" do
      refute_ai_called()
      assert Shopping.categorize_uncategorized() == :idle
    end
  end

  describe "resolve_missed/2" do
    setup :store_with_route

    test "sends the given names to the LLM", %{store: store, dairy: dairy} do
      {:ok, _milk} = Shopping.add_item(%{"name" => "Milk"})
      test_pid = self()

      Req.Test.stub(Pearview.AI, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:ai_request, Jason.decode!(raw)})
        Req.Test.json(conn, tool_call_response([%{"item" => "milk", "section" => dairy.name}]))
      end)

      assert CategorizeUncategorized.resolve_missed(store, ["milk"]) == :ok

      assert_received {:ai_request, body}
      prompt = body["messages"] |> List.last() |> Map.get("content")
      assert prompt =~ "milk"
    end

    test "writes through placed LLM answers to the cache and stamps the items", %{
      store: store,
      dairy: dairy
    } do
      {:ok, milk} = Shopping.add_item(%{"name" => "Milk"})
      stub_ai([%{"item" => "milk", "section" => dairy.name}])

      assert CategorizeUncategorized.resolve_missed(store, ["milk"]) == :ok

      assert Repo.get!(Item, milk.id).section_id == dairy.id

      row = Repo.get_by!(Categorization, store_id: store.id, normalized_name: "milk")
      assert row.section_id == dairy.id
      assert row.source == :ai
    end

    test "writes an unplaced cache row for names the model omits, leaving them in Other", %{
      store: store
    } do
      {:ok, widget} = Shopping.add_item(%{"name" => "Obscure Widget"})
      stub_ai([])

      assert CategorizeUncategorized.resolve_missed(store, ["obscure widget"]) == :ok

      assert Repo.get!(Item, widget.id).section_id == nil

      row = Repo.get_by!(Categorization, store_id: store.id, normalized_name: "obscure widget")
      assert row.section_id == nil
      assert row.source == :ai
    end

    @tag :capture_log
    test "writes no cache rows and leaves items uncategorised on an LLM error", %{store: store} do
      {:ok, milk} = Shopping.add_item(%{"name" => "Milk"})
      Req.Test.stub(Pearview.AI, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert CategorizeUncategorized.resolve_missed(store, ["milk"]) == :ok

      assert Repo.get!(Item, milk.id).section_id == nil
      assert Repo.all(Categorization) == []
    end
  end

  describe "cycle_item_status/1" do
    test "advances pending to checked" do
      {:ok, item} = Shopping.add_item(%{"name" => "milk"})

      assert {:ok, %{status: :checked}} = Shopping.cycle_item_status(item)
    end

    test "advances checked to not_available" do
      item = item!("milk", status: :checked)

      assert {:ok, %{status: :not_available}} = Shopping.cycle_item_status(item)
    end

    test "advances not_available back to pending" do
      item = item!("milk", status: :not_available)

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
      item!("Milk", status: :checked)
      item!("Eggs", status: :checked)
      {:ok, pending} = Shopping.add_item(%{"name" => "Bread"})

      Shopping.end_trip()

      remaining = Shopping.list_items() |> Enum.map(& &1.id)
      assert pending.id in remaining
      assert length(remaining) == 1
    end

    test "resets not_available items to pending" do
      item = item!("Milk", status: :not_available)

      Shopping.end_trip()

      assert Repo.get!(Item, item.id).status == :pending
    end

    test "leaves pending items untouched" do
      {:ok, item} = Shopping.add_item(%{"name" => "Bread"})

      Shopping.end_trip()

      assert Repo.get!(Item, item.id).status == :pending
    end

    test "handles a mix: deletes checked, resets not_available, preserves pending" do
      checked = item!("A", status: :checked)
      na = item!("B", status: :not_available)
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
