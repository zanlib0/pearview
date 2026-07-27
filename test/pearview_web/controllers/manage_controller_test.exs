defmodule PearviewWeb.ManageControllerTest do
  use PearviewWeb.ConnCase

  import Pearview.ShoppingFixtures

  alias Pearview.Repo
  alias Pearview.Shopping.{Categorization, Item, Section, Store}

  # The section rows in the order they are printed — the route as the Shopper
  # would walk it. Each row carries its name in an inline-edit field.
  defp route_order(body) do
    ~r/id="section_name_\d+"[^>]*value="([^"]*)"/
    |> Regex.scan(body)
    |> Enum.map(fn [_match, name] -> name end)
  end

  test "GET /manage lists every store", %{conn: conn} do
    store!("Aldi")
    store!("Lidl")

    conn = get(conn, ~p"/manage")
    body = html_response(conn, 200)

    assert body =~ "pearview"
    assert body =~ ~s(value="Aldi")
    assert body =~ ~s(value="Lidl")
  end

  test "GET /manage renders the add-store form", %{conn: conn} do
    conn = get(conn, ~p"/manage")
    body = html_response(conn, 200)

    assert body =~ ~s(hx-post="/manage/stores")
    assert body =~ ~s(name="store[name]")
  end

  describe "navigation between the three surfaces" do
    test "the Manage view links to the Operator and Shopper views", %{conn: conn} do
      conn = get(conn, ~p"/manage")
      body = html_response(conn, 200)

      assert body =~ ~s(href="/")
      assert body =~ ~s(href="/shopper")
      assert body =~ ~s(href="/manage" aria-current="page")
    end

    test "the Operator view links to Manage", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert html_response(conn, 200) =~ ~s(href="/manage")
    end

    test "the Shopper view links to Manage", %{conn: conn} do
      conn = get(conn, ~p"/shopper")

      assert html_response(conn, 200) =~ ~s(href="/manage")
    end
  end

  test "POST /manage/stores creates the store and returns its row fragment", %{conn: conn} do
    conn = post(conn, ~p"/manage/stores", store: %{name: "Lidl"})
    body = html_response(conn, 200)

    # the response is just the new row, not the whole page
    assert body =~ ~s(class="item-row store-row")
    assert body =~ ~s(value="Lidl")
    refute body =~ "pearview"

    assert [%Store{name: "Lidl"}] = Repo.all(Store)
  end

  test "POST /manage/stores with a blank name creates nothing (422)", %{conn: conn} do
    conn = post(conn, ~p"/manage/stores", store: %{name: "   "})

    assert response(conn, 422) == ""
    assert Repo.all(Store) == []
  end

  test "PATCH /manage/stores/:id renames the store and returns its updated row", %{conn: conn} do
    store = store!("Lidl")

    conn = patch(conn, ~p"/manage/stores/#{store.id}", store: %{name: "Lidl Anděl"})
    body = html_response(conn, 200)

    assert body =~ ~s(class="item-row store-row")
    assert body =~ ~s(value="Lidl Anděl")
    refute body =~ "pearview"

    assert Repo.get!(Store, store.id).name == "Lidl Anděl"
  end

  test "PATCH /manage/stores/:id with a blank name leaves the store unchanged (422)", %{
    conn: conn
  } do
    store = store!("Lidl")

    conn = patch(conn, ~p"/manage/stores/#{store.id}", store: %{name: "   "})
    body = html_response(conn, 422)

    # the unchanged row comes back; HTMX leaves the existing row in place
    assert body =~ ~s(value="Lidl")
    assert Repo.get!(Store, store.id).name == "Lidl"
  end

  test "DELETE /manage/stores/:id deletes the store and returns an empty fragment", %{conn: conn} do
    store = store!("Lidl")

    conn = delete(conn, ~p"/manage/stores/#{store.id}")

    assert response(conn, 200) == ""
    assert Repo.get(Store, store.id) == nil
  end

  test "DELETE /manage/stores/:id discards that store's cached categorizations", %{conn: conn} do
    %{store: store, produce: produce} = store_with_sections!()
    categorization!(store, "bananas", section_id: produce.id)
    other = store!("Lidl")
    kept = categorization!(other, "bananas")

    delete(conn, ~p"/manage/stores/#{store.id}")

    assert Repo.all(Categorization) |> Enum.map(& &1.id) == [kept.id]
  end

  describe "the Route panel" do
    test "GET /manage renders a store's sections in route order", %{conn: conn} do
      store = store!("Lidl")
      section!(store, "Bakery", position: 2)
      section!(store, "Produce", position: 1)

      conn = get(conn, ~p"/manage")

      assert route_order(html_response(conn, 200)) == ["Produce", "Bakery"]
    end

    test "GET /manage renders each section's hints beside its name", %{conn: conn} do
      store = store!("Lidl")
      section!(store, "Dairy", hints: "milk, butter")

      conn = get(conn, ~p"/manage")
      body = html_response(conn, 200)

      assert body =~ ~s(name="section[hints]")
      assert body =~ ~s(value="milk, butter")
    end

    test "GET /manage offers a picker over every store, the shown one pressed", %{conn: conn} do
      shown = store!("Aldi")
      other = store!("Lidl")

      conn = get(conn, ~p"/manage")
      body = html_response(conn, 200)

      assert body =~ ~s(hx-get="/manage/sections?store_id=#{shown.id}")
      assert body =~ ~s(hx-get="/manage/sections?store_id=#{other.id}")
      assert body =~ ~s(aria-pressed="true")
    end

    test "GET /manage asks for a store first when there are none", %{conn: conn} do
      conn = get(conn, ~p"/manage")

      assert html_response(conn, 200) =~ "Add a store first"
    end

    test "GET /manage/sections returns the requested store's route as a fragment", %{conn: conn} do
      store!("Aldi")
      lidl = store!("Lidl")
      section!(lidl, "Frozen")

      conn = get(conn, ~p"/manage/sections?store_id=#{lidl.id}")
      body = html_response(conn, 200)

      assert route_order(body) == ["Frozen"]
      # the response is just the panel, not the whole page
      refute body =~ "pearview"
    end

    test "GET /manage/sections falls back to the first store when the asked-for one is gone", %{
      conn: conn
    } do
      aldi = store!("Aldi")
      section!(aldi, "Produce")

      conn = get(conn, ~p"/manage/sections?store_id=999999")

      assert route_order(html_response(conn, 200)) == ["Produce"]
    end

    test "store mutations tell the Route panel to refetch itself", %{conn: conn} do
      store = store!("Lidl")

      created = post(conn, ~p"/manage/stores", store: %{name: "Aldi"})
      assert get_resp_header(created, "hx-trigger") == ["stores-changed"]

      renamed = patch(conn, ~p"/manage/stores/#{store.id}", store: %{name: "Lidl Anděl"})
      assert get_resp_header(renamed, "hx-trigger") == ["stores-changed"]

      deleted = delete(conn, ~p"/manage/stores/#{store.id}")
      assert get_resp_header(deleted, "hx-trigger") == ["stores-changed"]
    end
  end

  describe "adding a section" do
    test "POST /manage/stores/:store_id/sections creates it and returns the section list", %{
      conn: conn
    } do
      store = store!("Lidl")

      conn =
        post(conn, ~p"/manage/stores/#{store.id}/sections",
          section: %{name: "Produce", hints: "apples"}
        )

      body = html_response(conn, 200)

      assert route_order(body) == ["Produce"]
      refute body =~ "pearview"

      assert [%Section{name: "Produce", hints: "apples"}] = Repo.all(Section)
    end

    test "POST /manage/stores/:store_id/sections appends the new stop to the route", %{conn: conn} do
      store = store!("Lidl")
      section!(store, "Produce", position: 1)

      conn = post(conn, ~p"/manage/stores/#{store.id}/sections", section: %{name: "Bakery"})

      assert route_order(html_response(conn, 200)) == ["Produce", "Bakery"]
    end

    test "POST /manage/stores/:store_id/sections with a blank name creates nothing (422)", %{
      conn: conn
    } do
      store = store!("Lidl")

      conn = post(conn, ~p"/manage/stores/#{store.id}/sections", section: %{name: "   "})

      assert response(conn, 422) == ""
      assert Repo.all(Section) == []
    end
  end

  describe "editing a section" do
    test "PATCH /manage/sections/:id renames it and returns its updated row", %{conn: conn} do
      section = section!(store!("Lidl"), "Diary")

      conn = patch(conn, ~p"/manage/sections/#{section.id}", section: %{name: "Dairy"})
      body = html_response(conn, 200)

      assert body =~ ~s(class="item-row section-row")
      assert route_order(body) == ["Dairy"]
      refute body =~ "pearview"

      assert Repo.get!(Section, section.id).name == "Dairy"
    end

    test "PATCH /manage/sections/:id rewrites its hints", %{conn: conn} do
      section = section!(store!("Lidl"), "Dairy", hints: "milk")

      conn =
        patch(conn, ~p"/manage/sections/#{section.id}", section: %{hints: "milk, sour cream"})

      body = html_response(conn, 200)

      assert body =~ ~s(value="milk, sour cream")
      assert Repo.get!(Section, section.id).hints == "milk, sour cream"
      # the name field is untouched by a hints edit
      assert route_order(body) == ["Dairy"]
    end

    test "PATCH /manage/sections/:id with a blank name leaves the section unchanged (422)", %{
      conn: conn
    } do
      section = section!(store!("Lidl"), "Dairy")

      conn = patch(conn, ~p"/manage/sections/#{section.id}", section: %{name: "   "})
      body = html_response(conn, 422)

      # the unchanged row comes back; HTMX leaves the existing row in place
      assert route_order(body) == ["Dairy"]
      assert Repo.get!(Section, section.id).name == "Dairy"
    end
  end

  describe "reordering the route" do
    setup do
      store = store!("Lidl")

      %{
        store: store,
        produce: section!(store, "Produce", position: 1),
        dairy: section!(store, "Dairy", position: 2),
        bakery: section!(store, "Bakery", position: 3)
      }
    end

    test "PATCH /manage/sections/:id/move up returns the sections in the new order", %{
      conn: conn,
      dairy: dairy,
      produce: produce
    } do
      conn = patch(conn, ~p"/manage/sections/#{dairy.id}/move?direction=up")
      body = html_response(conn, 200)

      assert route_order(body) == ["Dairy", "Produce", "Bakery"]
      refute body =~ "pearview"

      assert Repo.get!(Section, dairy.id).position == 1
      assert Repo.get!(Section, produce.id).position == 2
    end

    test "PATCH /manage/sections/:id/move down returns the sections in the new order", %{
      conn: conn,
      dairy: dairy
    } do
      conn = patch(conn, ~p"/manage/sections/#{dairy.id}/move?direction=down")

      assert route_order(html_response(conn, 200)) == ["Produce", "Bakery", "Dairy"]
    end

    test "moving the first stop up returns the route unchanged", %{conn: conn, produce: produce} do
      conn = patch(conn, ~p"/manage/sections/#{produce.id}/move?direction=up")

      assert route_order(html_response(conn, 200)) == ["Produce", "Dairy", "Bakery"]
    end

    test "moving the last stop down returns the route unchanged", %{conn: conn, bakery: bakery} do
      conn = patch(conn, ~p"/manage/sections/#{bakery.id}/move?direction=down")

      assert route_order(html_response(conn, 200)) == ["Produce", "Dairy", "Bakery"]
    end
  end

  describe "deleting a section" do
    test "DELETE /manage/sections/:id deletes it and returns an empty fragment", %{conn: conn} do
      section = section!(store!("Lidl"), "Dairy")

      conn = delete(conn, ~p"/manage/sections/#{section.id}")

      assert response(conn, 200) == ""
      assert Repo.get(Section, section.id) == nil
    end

    test "DELETE /manage/sections/:id leaves its items on the list, uncategorised", %{conn: conn} do
      section = section!(store!("Lidl"), "Dairy")
      milk = item!("Milk", section_id: section.id)

      delete(conn, ~p"/manage/sections/#{section.id}")

      assert Repo.get!(Item, milk.id).section_id == nil
    end

    test "DELETE /manage/sections/:id drops that section's cached categorizations", %{conn: conn} do
      store = store!("Lidl")
      section = section!(store, "Dairy")
      categorization!(store, "milk", section_id: section.id)
      unplaced = categorization!(store, "capers")

      delete(conn, ~p"/manage/sections/#{section.id}")

      assert Repo.all(Categorization) |> Enum.map(& &1.id) == [unplaced.id]
    end
  end

  describe "the Categorization cache panel" do
    test "GET /manage lists a store's cached names and where they are filed", %{conn: conn} do
      store = store!("Lidl")
      dairy = section!(store, "Dairy")
      categorization!(store, "sour cream", section_id: dairy.id)

      conn = get(conn, ~p"/manage")
      body = html_response(conn, 200)

      assert body =~ "Categorisation cache"
      assert body =~ "sour cream"
      assert body =~ ~s(class="cache-placement t-meta">Dairy</span>)
    end

    test "GET /manage shows rows the AI could not place as unplaced", %{conn: conn} do
      store = store!("Lidl")
      categorization!(store, "capers")

      conn = get(conn, ~p"/manage")
      body = html_response(conn, 200)

      assert body =~ "capers"
      assert body =~ "-unplaced"
      assert body =~ "Unplaced"
    end

    test "GET /manage offers each cached name a forget control", %{conn: conn} do
      store = store!("Lidl")
      row = categorization!(store, "capers")

      conn = get(conn, ~p"/manage")

      assert html_response(conn, 200) =~ ~s(hx-delete="/manage/categorizations/#{row.id}")
    end

    test "GET /manage shows only the picked store's cache", %{conn: conn} do
      aldi = store!("Aldi")
      lidl = store!("Lidl")
      categorization!(aldi, "bananas")
      categorization!(lidl, "sour cream")

      conn = get(conn, ~p"/manage")
      body = html_response(conn, 200)

      # the panel defaults to the first store by name
      assert body =~ "bananas"
      refute body =~ "sour cream"
    end

    test "GET /manage/categorizations returns the requested store's cache as a fragment", %{
      conn: conn
    } do
      aldi = store!("Aldi")
      lidl = store!("Lidl")
      categorization!(aldi, "bananas")
      categorization!(lidl, "sour cream")

      conn = get(conn, ~p"/manage/categorizations?store_id=#{lidl.id}")
      body = html_response(conn, 200)

      assert body =~ "sour cream"
      refute body =~ "bananas"
      # the response is just the panel, not the whole page
      refute body =~ "pearview"
    end

    test "GET /manage/categorizations offers a picker over every store, the shown one pressed", %{
      conn: conn
    } do
      shown = store!("Aldi")
      other = store!("Lidl")

      conn = get(conn, ~p"/manage/categorizations")
      body = html_response(conn, 200)

      assert body =~ ~s(hx-get="/manage/categorizations?store_id=#{shown.id}")
      assert body =~ ~s(hx-get="/manage/categorizations?store_id=#{other.id}")
      assert body =~ ~s(aria-pressed="true")
    end

    test "GET /manage/categorizations falls back to the first store when the asked-for one is gone",
         %{conn: conn} do
      aldi = store!("Aldi")
      categorization!(aldi, "bananas")

      conn = get(conn, ~p"/manage/categorizations?store_id=999999")

      assert html_response(conn, 200) =~ "bananas"
    end

    test "GET /manage asks for a store first when there are none", %{conn: conn} do
      conn = get(conn, ~p"/manage")

      assert html_response(conn, 200) =~ "Add a store first — its cache fills"
    end

    test "the cache panel refetches itself when stores or sections change", %{conn: conn} do
      store!("Lidl")

      conn = get(conn, ~p"/manage")
      body = html_response(conn, 200)

      assert body =~ ~s(id="cache-panel")
      assert body =~ ~s(hx-trigger="stores-changed from:body, sections-changed from:body")
    end

    test "renaming or deleting a section tells the cache panel to refetch itself", %{conn: conn} do
      section = section!(store!("Lidl"), "Diary")

      renamed = patch(conn, ~p"/manage/sections/#{section.id}", section: %{name: "Dairy"})
      assert get_resp_header(renamed, "hx-trigger") == ["sections-changed"]

      deleted = delete(conn, ~p"/manage/sections/#{section.id}")
      assert get_resp_header(deleted, "hx-trigger") == ["sections-changed"]
    end
  end

  describe "pruning the cache" do
    test "DELETE /manage/categorizations/:id deletes the row and returns an empty fragment", %{
      conn: conn
    } do
      row = categorization!(store!("Lidl"), "capers")

      conn = delete(conn, ~p"/manage/categorizations/#{row.id}")

      assert response(conn, 200) == ""
      assert Repo.get(Categorization, row.id) == nil
    end

    test "DELETE /manage/categorizations/:id leaves items on the list untouched", %{conn: conn} do
      store = store!("Lidl")
      dairy = section!(store, "Dairy")
      milk = item!("Milk", section_id: dairy.id)
      row = categorization!(store, "milk", section_id: dairy.id)

      delete(conn, ~p"/manage/categorizations/#{row.id}")

      assert Repo.get!(Item, milk.id).section_id == dairy.id
      assert Repo.get!(Section, dairy.id)
    end

    test "DELETE /manage/categorizations/:id leaves the store's other cache rows alone", %{
      conn: conn
    } do
      store = store!("Lidl")
      row = categorization!(store, "capers")
      kept = categorization!(store, "bananas")

      delete(conn, ~p"/manage/categorizations/#{row.id}")

      assert Repo.all(Categorization) |> Enum.map(& &1.id) == [kept.id]
    end
  end
end
