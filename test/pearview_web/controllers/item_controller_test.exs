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
end
