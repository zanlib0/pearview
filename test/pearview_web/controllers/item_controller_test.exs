defmodule PearviewWeb.ItemControllerTest do
  use PearviewWeb.ConnCase

  alias Pearview.Repo
  alias Pearview.Shopping.Item

  test "GET / renders every item on the list as a tick-box", %{conn: conn} do
    Repo.insert!(%Item{name: "Bananas", normalized_name: "bananas", status: :pending})
    Repo.insert!(%Item{name: "Oat milk", normalized_name: "oat milk", status: :checked})
    Repo.insert!(%Item{name: "Capers", normalized_name: "capers", status: :not_available})

    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "pearview"
    assert body =~ "Bananas"
    assert body =~ "Oat milk"
    assert body =~ ~s(class="tick-box")
    # the checked item renders a checked box
    assert body =~ "checked"
    # the not-available item renders struck through with no checkbox
    assert body =~ "-struck"
  end

  test "GET / renders the add-item form", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ ~s(hx-post="/items")
    assert body =~ ~s(name="item[name]")
  end

  test "POST /items creates a pending item and returns its row fragment", %{conn: conn} do
    conn = post(conn, ~p"/items", item: %{name: "  Oat   milk "})
    body = html_response(conn, 200)

    # the response is just the new row, not the whole page
    assert body =~ ~s(class="item-row")
    assert body =~ "Oat   milk"
    refute body =~ "pearview"

    assert [%Item{} = item] = Repo.all(Item)
    assert item.name == "  Oat   milk "
    assert item.normalized_name == "oat milk"
    assert item.status == :pending
    assert item.section_id == nil
  end

  test "PATCH /items/:id renames the item and returns its updated row", %{conn: conn} do
    item = Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :pending})

    conn = patch(conn, ~p"/items/#{item.id}", item: %{name: "  Oat   milk "})
    body = html_response(conn, 200)

    # the response is just the row fragment, carrying the new name in its field
    assert body =~ ~s(class="item-row")
    assert body =~ ~s(value="  Oat   milk ")
    refute body =~ "pearview"

    reloaded = Repo.get!(Item, item.id)
    assert reloaded.name == "  Oat   milk "
    assert reloaded.normalized_name == "oat milk"
  end

  test "PATCH /items/:id with a blank name leaves the item unchanged (422)", %{conn: conn} do
    item = Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :pending})

    conn = patch(conn, ~p"/items/#{item.id}", item: %{name: "   "})
    body = html_response(conn, 422)

    # the unchanged row comes back; HTMX leaves the existing row in place
    assert body =~ ~s(value="milk")
    assert Repo.get!(Item, item.id).name == "milk"
  end

  test "DELETE /items/:id hard-deletes the item and returns an empty fragment", %{conn: conn} do
    item = Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :pending})

    conn = delete(conn, ~p"/items/#{item.id}")

    assert response(conn, 200) == ""
    assert Repo.get(Item, item.id) == nil
  end

  describe "PATCH /items/:id/cycle" do
    test "cycles a pending item to checked and returns its row fragment", %{conn: conn} do
      item = Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :pending})

      conn = patch(conn, ~p"/items/#{item.id}/cycle")
      body = html_response(conn, 200)

      assert body =~ ~s(class="item-row")
      assert body =~ "checked"
      refute body =~ "pearview"
      assert Repo.get!(Item, item.id).status == :checked
    end

    test "cycles a checked item to not_available", %{conn: conn} do
      item = Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :checked})

      conn = patch(conn, ~p"/items/#{item.id}/cycle")
      body = html_response(conn, 200)

      assert body =~ "-struck"
      assert Repo.get!(Item, item.id).status == :not_available
    end

    test "cycles a not_available item back to pending", %{conn: conn} do
      item =
        Repo.insert!(%Item{name: "milk", normalized_name: "milk", status: :not_available})

      conn = patch(conn, ~p"/items/#{item.id}/cycle")
      body = html_response(conn, 200)

      refute body =~ "checked"
      assert Repo.get!(Item, item.id).status == :pending
    end
  end

  test "GET / renders each item's inline name field and delete control", %{conn: conn} do
    item = Repo.insert!(%Item{name: "Bananas", normalized_name: "bananas", status: :pending})

    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    # the name is an always-editable field that PATCHes on change
    assert body =~ ~s(hx-patch="/items/#{item.id}")
    assert body =~ ~s(name="item[name]")
    assert body =~ ~s(value="Bananas")
    # delete is a bare control, not a labelled button
    assert body =~ ~s(hx-delete="/items/#{item.id}")
    refute body =~ "Delete</button>"
  end
end
