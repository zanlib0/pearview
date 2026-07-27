defmodule PearviewWeb.ManageControllerTest do
  use PearviewWeb.ConnCase

  import Pearview.ShoppingFixtures

  alias Pearview.Repo
  alias Pearview.Shopping.{Categorization, Store}

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
end
