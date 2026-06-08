defmodule PearviewWeb.ItemControllerTest do
  use PearviewWeb.ConnCase

  alias Pearview.Repo
  alias Pearview.Shopping.Item

  test "GET / renders every item on the list", %{conn: conn} do
    Repo.insert!(%Item{name: "Bananas", normalized_name: "bananas", status: :pending})
    Repo.insert!(%Item{name: "Oat milk", normalized_name: "oat milk", status: :pending})

    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "Shopping list"
    assert body =~ "Bananas"
    assert body =~ "Oat milk"
  end
end
