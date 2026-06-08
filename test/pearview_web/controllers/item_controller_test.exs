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

    assert body =~ "Shopping list"
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
    refute body =~ "Shopping list"

    assert [%Item{} = item] = Repo.all(Item)
    assert item.name == "  Oat   milk "
    assert item.normalized_name == "oat milk"
    assert item.status == :pending
    assert item.section_id == nil
  end
end
