defmodule Pearview.ShoppingTest do
  use Pearview.DataCase, async: true

  import Pearview.AIStubs, only: [tool_call_response: 1, stub_ai: 1, refute_ai_called: 0]
  import Pearview.ShoppingFixtures

  alias Pearview.Shopping

  alias Pearview.Shopping.{
    Categorization,
    CategorizeUncategorized,
    Item,
    Section,
    Settings,
    Store
  }

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

    test "clears the selection when the deleted store was the selected one" do
      %{store: store} = store_with_sections!()
      assert Shopping.get_selected_store().id == store.id

      assert {:ok, _deleted} = Shopping.delete_store(store)

      assert Shopping.get_selected_store() == nil
    end

    test "leaves the selection alone when some other store is deleted" do
      %{store: selected} = store_with_sections!()
      other = store!("Lidl")

      assert {:ok, _deleted} = Shopping.delete_store(other)

      assert Shopping.get_selected_store().id == selected.id
    end
  end

  describe "get_selected_store/0" do
    test "returns nil when no store has been selected yet" do
      store!("Lidl")

      assert Shopping.get_selected_store() == nil
    end

    test "returns the store the singleton points at" do
      store!("Aldi")
      lidl = store!("Lidl")

      refute_ai_called()
      Shopping.select_store(lidl)

      assert Shopping.get_selected_store().id == lidl.id
    end
  end

  describe "select_store/1" do
    setup :store_with_route

    test "makes the given store the selected one", %{store: store} do
      lidl = store!("Lidl")
      refute_ai_called()

      Shopping.select_store(lidl)

      assert Shopping.get_selected_store().id == lidl.id
      refute Shopping.get_selected_store().id == store.id
    end

    test "switching back and forth keeps one selection, never a second row", %{store: store} do
      lidl = store!("Lidl")
      refute_ai_called()

      Shopping.select_store(lidl)
      Shopping.select_store(store)

      assert Shopping.get_selected_store().id == store.id
      assert Repo.aggregate(Settings, :count) == 1
    end

    test "nulls every item's section so nothing keeps the old store's placement", %{
      produce: produce,
      dairy: dairy
    } do
      bananas = item!("Bananas", section_id: produce.id)
      milk = item!("Milk", section_id: dairy.id)
      lidl = store!("Lidl")
      stub_ai([])

      Shopping.select_store(lidl)

      assert Repo.get!(Item, bananas.id).section_id == nil
      assert Repo.get!(Item, milk.id).section_id == nil

      await_background_tasks()
    end

    test "re-stamps the list from the new store's cache without calling the LLM", %{
      produce: produce
    } do
      bananas = item!("Bananas", section_id: produce.id)

      lidl = store!("Lidl")
      lidl_fruit = section!(lidl, "Fruit & Veg")
      categorization!(lidl, "bananas", section_id: lidl_fruit.id)
      refute_ai_called()

      assert Shopping.select_store(lidl) == :idle

      assert Repo.get!(Item, bananas.id).section_id == lidl_fruit.id
    end

    test "groups the re-stamped list under the new store's route", %{produce: produce} do
      item!("Bananas", section_id: produce.id)

      lidl = store!("Lidl")
      lidl_fruit = section!(lidl, "Fruit & Veg")
      categorization!(lidl, "bananas", section_id: lidl_fruit.id)
      refute_ai_called()

      Shopping.select_store(lidl)

      assert [{%{id: section_id}, [%{name: "Bananas"}]}] = Shopping.list_grouped_for_shopper()
      assert section_id == lidl_fruit.id
    end

    test "leaves a name the new store has cached as unplaced in Other", %{produce: produce} do
      capers = item!("Capers", section_id: produce.id)

      lidl = store!("Lidl")
      section!(lidl, "Fruit & Veg")
      categorization!(lidl, "capers")
      refute_ai_called()

      assert Shopping.select_store(lidl) == :idle

      assert Repo.get!(Item, capers.id).section_id == nil
      assert [{:other, [%{name: "Capers"}]}] = Shopping.list_grouped_for_shopper()
    end

    test "hands names the new store has never seen to the background run, reporting :categorising",
         %{produce: produce} do
      item!("Bananas", section_id: produce.id)

      lidl = store!("Lidl")
      section!(lidl, "Fruit & Veg")
      stub_ai([])

      assert Shopping.select_store(lidl) == :categorising

      await_background_tasks()
    end
  end

  describe "list_sections/1" do
    test "returns a store's sections in route (position) order" do
      store = store!("Lidl")
      section!(store, "Dairy", position: 2)
      section!(store, "Produce", position: 1)
      section!(store, "Bakery", position: 3)

      assert Shopping.list_sections(store) |> Enum.map(& &1.name) ==
               ["Produce", "Dairy", "Bakery"]
    end

    test "accepts a store id as well as a store" do
      store = store!("Lidl")
      section!(store, "Produce")

      assert Shopping.list_sections(store.id) |> Enum.map(& &1.name) == ["Produce"]
    end

    test "returns only that store's sections" do
      store = store!("Lidl")
      other = store!("Aldi")
      section!(store, "Produce")
      section!(other, "Frozen")

      assert Shopping.list_sections(store) |> Enum.map(& &1.name) == ["Produce"]
    end

    test "returns an empty list for a store with no route yet" do
      assert Shopping.list_sections(store!("Lidl")) == []
    end
  end

  describe "create_section/1" do
    test "adds a section with the given name and hints" do
      store = store!("Lidl")

      assert {:ok, %Section{} = section} =
               Shopping.create_section(%{
                 "store_id" => store.id,
                 "name" => "Produce",
                 "hints" => "apples, bananas"
               })

      assert section.name == "Produce"
      assert section.hints == "apples, bananas"
      assert Repo.get!(Section, section.id).store_id == store.id
    end

    test "appends the section to the end of the store's route" do
      store = store!("Lidl")
      section!(store, "Produce", position: 1)
      section!(store, "Dairy", position: 2)

      assert {:ok, bakery} =
               Shopping.create_section(%{"store_id" => store.id, "name" => "Bakery"})

      assert bakery.position == 3

      assert Shopping.list_sections(store) |> Enum.map(& &1.name) == [
               "Produce",
               "Dairy",
               "Bakery"
             ]
    end

    test "gives the first section of a store position 1" do
      store = store!("Lidl")

      assert {:ok, section} =
               Shopping.create_section(%{"store_id" => store.id, "name" => "Produce"})

      assert section.position == 1
    end

    test "positions are per store, so a new store starts its route at 1" do
      other = store!("Aldi")
      section!(other, "Frozen", position: 7)
      store = store!("Lidl")

      assert {:ok, section} =
               Shopping.create_section(%{"store_id" => store.id, "name" => "Produce"})

      assert section.position == 1
    end

    test "stores blank hints as nil" do
      store = store!("Lidl")

      assert {:ok, section} =
               Shopping.create_section(%{
                 "store_id" => store.id,
                 "name" => "Produce",
                 "hints" => "  "
               })

      assert section.hints == nil
    end

    test "rejects a blank name" do
      store = store!("Lidl")

      assert {:error, changeset} =
               Shopping.create_section(%{"store_id" => store.id, "name" => "  "})

      refute changeset.valid?
      assert Shopping.list_sections(store) == []
    end
  end

  describe "update_section/2" do
    test "renames the section" do
      store = store!("Lidl")
      section = section!(store, "Diary")

      assert {:ok, updated} = Shopping.update_section(section, %{"name" => "Dairy"})

      assert updated.name == "Dairy"
      assert Repo.get!(Section, section.id).name == "Dairy"
    end

    test "rewrites the section's hints" do
      store = store!("Lidl")
      section = section!(store, "Dairy", hints: "milk")

      assert {:ok, updated} = Shopping.update_section(section, %{"hints" => "milk, sour cream"})

      assert updated.hints == "milk, sour cream"
      assert Repo.get!(Section, section.id).hints == "milk, sour cream"
    end

    test "clears the hints when the field is emptied" do
      store = store!("Lidl")
      section = section!(store, "Dairy", hints: "milk")

      assert {:ok, updated} = Shopping.update_section(section, %{"hints" => ""})

      assert updated.hints == nil
      assert Repo.get!(Section, section.id).hints == nil
    end

    test "editing hints leaves the name and the route position alone" do
      store = store!("Lidl")
      section = section!(store, "Dairy", position: 2)

      assert {:ok, updated} = Shopping.update_section(section, %{"hints" => "milk"})

      assert updated.name == "Dairy"
      assert updated.position == 2
    end

    test "rejects a blank name and leaves the section unchanged" do
      store = store!("Lidl")
      section = section!(store, "Dairy")

      assert {:error, changeset} = Shopping.update_section(section, %{"name" => "   "})
      refute changeset.valid?
      assert Repo.get!(Section, section.id).name == "Dairy"
    end
  end

  describe "move_section/2" do
    setup do
      # Selected, so the grouped-list assertion below reads this store's route.
      store = store!("Lidl") |> select!()

      %{
        store: store,
        produce: section!(store, "Produce", position: 1),
        dairy: section!(store, "Dairy", position: 2),
        bakery: section!(store, "Bakery", position: 3)
      }
    end

    test "moving a section up swaps positions with the stop before it", %{
      dairy: dairy,
      produce: produce
    } do
      assert {:ok, sections} = Shopping.move_section(dairy, :up)

      assert Enum.map(sections, & &1.name) == ["Dairy", "Produce", "Bakery"]
      assert Repo.get!(Section, dairy.id).position == 1
      assert Repo.get!(Section, produce.id).position == 2
    end

    test "moving a section down swaps positions with the stop after it", %{
      dairy: dairy,
      bakery: bakery
    } do
      assert {:ok, sections} = Shopping.move_section(dairy, :down)

      assert Enum.map(sections, & &1.name) == ["Produce", "Bakery", "Dairy"]
      assert Repo.get!(Section, dairy.id).position == 3
      assert Repo.get!(Section, bakery.id).position == 2
    end

    test "moving the first section up is a no-op", %{produce: produce} do
      assert {:ok, sections} = Shopping.move_section(produce, :up)

      assert Enum.map(sections, & &1.name) == ["Produce", "Dairy", "Bakery"]
      assert Repo.get!(Section, produce.id).position == 1
    end

    test "moving the last section down is a no-op", %{bakery: bakery} do
      assert {:ok, sections} = Shopping.move_section(bakery, :down)

      assert Enum.map(sections, & &1.name) == ["Produce", "Dairy", "Bakery"]
      assert Repo.get!(Section, bakery.id).position == 3
    end

    test "never reaches across into another store's route", %{dairy: dairy} do
      other = store!("Aldi")
      frozen = section!(other, "Frozen", position: 1)

      assert {:ok, _sections} = Shopping.move_section(dairy, :up)

      assert Repo.get!(Section, frozen.id).position == 1
    end

    test "the shopper's grouped list follows the new order", %{dairy: dairy, produce: produce} do
      item!("Milk", section_id: dairy.id)
      item!("Bananas", section_id: produce.id)

      {:ok, _} = Shopping.move_section(dairy, :up)

      assert Shopping.list_grouped_for_shopper() |> Enum.map(fn {section, _} -> section.name end) ==
               ["Dairy", "Produce"]
    end
  end

  describe "delete_section/1" do
    test "removes the stop from the store's route" do
      store = store!("Lidl")
      produce = section!(store, "Produce", position: 1)
      dairy = section!(store, "Dairy", position: 2)

      assert {:ok, _deleted} = Shopping.delete_section(dairy)

      assert Repo.get(Section, dairy.id) == nil
      assert Shopping.list_sections(store) |> Enum.map(& &1.id) == [produce.id]
    end

    test "leaves its items on the list, uncategorised, rather than deleting them" do
      store = store!("Lidl")
      dairy = section!(store, "Dairy")
      milk = item!("Milk", section_id: dairy.id, status: :checked)

      assert {:ok, _deleted} = Shopping.delete_section(dairy)

      kept = Repo.get!(Item, milk.id)
      assert kept.section_id == nil
      assert kept.status == :checked
    end

    test "deletes that section's cached categorizations instead of freezing them as unplaced" do
      store = store!("Lidl")
      dairy = section!(store, "Dairy")
      row = categorization!(store, "milk", section_id: dairy.id)

      assert {:ok, _deleted} = Shopping.delete_section(dairy)

      assert Repo.get(Categorization, row.id) == nil
    end

    test "leaves the store's other cache rows untouched" do
      store = store!("Lidl")
      produce = section!(store, "Produce", position: 1)
      dairy = section!(store, "Dairy", position: 2)
      kept = categorization!(store, "bananas", section_id: produce.id)
      unplaced = categorization!(store, "capers")
      categorization!(store, "milk", section_id: dairy.id)

      assert {:ok, _deleted} = Shopping.delete_section(dairy)

      assert Repo.all(Categorization) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([kept.id, unplaced.id])
    end

    test "leaves the store itself and its other sections in place" do
      store = store!("Lidl")
      produce = section!(store, "Produce", position: 1)
      dairy = section!(store, "Dairy", position: 2)

      assert {:ok, _deleted} = Shopping.delete_section(dairy)

      assert Repo.get!(Store, store.id)
      assert Repo.get!(Section, produce.id)
    end
  end

  describe "list_categorizations/1" do
    test "returns a store's cached names in name order" do
      store = store!("Lidl")
      categorization!(store, "milk")
      categorization!(store, "bananas")

      names = Shopping.list_categorizations(store) |> Enum.map(& &1.normalized_name)

      assert names == ["bananas", "milk"]
    end

    test "includes unplaced rows the AI could not file" do
      store = store!("Lidl")
      dairy = section!(store, "Dairy")
      categorization!(store, "milk", section_id: dairy.id)
      categorization!(store, "capers")

      rows = Shopping.list_categorizations(store)

      assert Enum.map(rows, &{&1.normalized_name, &1.section_id}) ==
               [{"capers", nil}, {"milk", dairy.id}]
    end

    test "preloads the section each name is filed under" do
      store = store!("Lidl")
      dairy = section!(store, "Dairy")
      categorization!(store, "milk", section_id: dairy.id)
      categorization!(store, "capers")

      assert [capers, milk] = Shopping.list_categorizations(store)

      assert milk.section.name == "Dairy"
      assert capers.section == nil
    end

    test "accepts a store id as well as a store" do
      store = store!("Lidl")
      categorization!(store, "milk")

      assert Shopping.list_categorizations(store.id) |> Enum.map(& &1.normalized_name) == ["milk"]
    end

    test "returns only that store's rows" do
      lidl = store!("Lidl")
      aldi = store!("Aldi")
      categorization!(lidl, "milk")
      categorization!(aldi, "bananas")

      assert Shopping.list_categorizations(lidl) |> Enum.map(& &1.normalized_name) == ["milk"]
    end

    test "returns an empty list for a store with nothing cached yet" do
      assert Shopping.list_categorizations(store!("Lidl")) == []
    end
  end

  describe "delete_categorization/1" do
    test "removes the row so the name is asked again next time it appears" do
      store = store!("Lidl")
      row = categorization!(store, "milk")

      assert {:ok, _deleted} = Shopping.delete_categorization(row)

      assert Repo.get(Categorization, row.id) == nil
      assert Shopping.list_categorizations(store) == []
    end

    test "removes an unplaced row too" do
      store = store!("Lidl")
      row = categorization!(store, "capers")

      assert {:ok, _deleted} = Shopping.delete_categorization(row)

      assert Repo.get(Categorization, row.id) == nil
    end

    test "leaves items already stamped with that section untouched (no cascade)" do
      store = store!("Lidl")
      dairy = section!(store, "Dairy")
      milk = item!("Milk", section_id: dairy.id, status: :checked)
      row = categorization!(store, "milk", section_id: dairy.id)

      assert {:ok, _deleted} = Shopping.delete_categorization(row)

      kept = Repo.get!(Item, milk.id)
      assert kept.section_id == dairy.id
      assert kept.status == :checked
    end

    test "leaves the store's other cache rows untouched" do
      store = store!("Lidl")
      other = store!("Aldi")
      row = categorization!(store, "milk")
      kept = categorization!(store, "bananas")
      elsewhere = categorization!(other, "milk")

      assert {:ok, _deleted} = Shopping.delete_categorization(row)

      assert Repo.all(Categorization) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([kept.id, elsewhere.id])
    end

    test "leaves the section it pointed at and its store in place" do
      store = store!("Lidl")
      dairy = section!(store, "Dairy")
      row = categorization!(store, "milk", section_id: dairy.id)

      assert {:ok, _deleted} = Shopping.delete_categorization(row)

      assert Repo.get!(Section, dairy.id)
      assert Repo.get!(Store, store.id)
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

    test "shows only the selected store's route, with another store's sections nowhere", %{
      produce: produce
    } do
      lidl = store!("Lidl")
      item!("Frozen peas", section_id: section!(lidl, "Frozen").id)
      item!("Bananas", section_id: produce.id)

      groups = Shopping.list_grouped_for_shopper()

      names =
        Enum.map(groups, fn {head, _} -> if head == :other, do: "Other", else: head.name end)

      refute "Frozen" in names
      assert names == ["Produce", "Other"]
    end

    test "keeps an item stamped for another store on the list, in Other" do
      lidl = store!("Lidl")
      item!("Frozen peas", section_id: section!(lidl, "Frozen").id)

      assert [{:other, [%{name: "Frozen peas"}]}] = Shopping.list_grouped_for_shopper()
    end

    test "puts the whole list in Other when no store is selected", %{produce: produce} do
      item!("Bananas", section_id: produce.id)
      Repo.delete_all(Settings)

      assert [{:other, [%{name: "Bananas"}]}] = Shopping.list_grouped_for_shopper()
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

    test "resolves against the selected store's cache, not another store's", %{produce: produce} do
      # Same name, filed differently at each store: the answer must come from the
      # store being shopped.
      lidl = store!("Lidl") |> select!()
      lidl_fruit = section!(lidl, "Fruit & Veg")
      categorization!(lidl, "bananas", section_id: lidl_fruit.id)
      categorization!(Repo.get!(Store, produce.store_id), "bananas", section_id: produce.id)

      {:ok, item} = Shopping.add_item(%{"name" => "Bananas"})
      refute_ai_called()

      assert Shopping.categorize_uncategorized() == :idle
      assert Repo.get!(Item, item.id).section_id == lidl_fruit.id
    end

    test "is a no-op reporting :idle while no store is selected" do
      Repo.delete_all(Settings)
      {:ok, item} = Shopping.add_item(%{"name" => "Bananas"})
      refute_ai_called()

      assert Shopping.categorize_uncategorized() == :idle
      assert Repo.get!(Item, item.id).section_id == nil
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
