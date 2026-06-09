defmodule PearviewWeb.ShopperControllerTest do
  use PearviewWeb.ConnCase

  alias Pearview.Repo
  alias Pearview.Shopping
  alias Pearview.Shopping.{Item, Section, Store}

  setup do
    store = Repo.insert!(%Store{name: "Test Store"})
    produce = Repo.insert!(%Section{name: "Produce", position: 1, store_id: store.id})
    dairy = Repo.insert!(%Section{name: "Dairy & Eggs", position: 2, store_id: store.id})
    %{store: store, produce: produce, dairy: dairy}
  end

  test "GET /shopper renders section headings in route order", %{
    conn: conn,
    produce: produce,
    dairy: dairy
  } do
    Repo.insert!(%Item{
      name: "Bananas",
      normalized_name: "bananas",
      status: :pending,
      section_id: produce.id
    })

    Repo.insert!(%Item{
      name: "Milk",
      normalized_name: "milk",
      status: :pending,
      section_id: dairy.id
    })

    conn = get(conn, ~p"/shopper")
    body = html_response(conn, 200)

    assert body =~ "pearview"
    assert body =~ "Produce"
    assert body =~ "Dairy &amp; Eggs"

    produce_pos = :binary.match(body, "Produce") |> elem(0)
    dairy_pos = :binary.match(body, "Dairy") |> elem(0)
    assert produce_pos < dairy_pos
  end

  test "GET /shopper renders items under their section", %{
    conn: conn,
    produce: produce,
    dairy: dairy
  } do
    Repo.insert!(%Item{
      name: "Bananas",
      normalized_name: "bananas",
      status: :pending,
      section_id: produce.id
    })

    Repo.insert!(%Item{
      name: "Milk",
      normalized_name: "milk",
      status: :pending,
      section_id: dairy.id
    })

    conn = get(conn, ~p"/shopper")
    body = html_response(conn, 200)

    assert body =~ "Bananas"
    assert body =~ "Milk"
  end

  test "GET /shopper renders nil-section items in an Other group pinned last", %{
    conn: conn,
    produce: produce
  } do
    Repo.insert!(%Item{
      name: "Bananas",
      normalized_name: "bananas",
      status: :pending,
      section_id: produce.id
    })

    Repo.insert!(%Item{name: "Lightbulbs", normalized_name: "lightbulbs", status: :pending})

    conn = get(conn, ~p"/shopper")
    body = html_response(conn, 200)

    assert body =~ "Other"
    assert body =~ "Lightbulbs"

    produce_pos = :binary.match(body, "Produce") |> elem(0)
    other_pos = :binary.match(body, "Other") |> elem(0)
    assert produce_pos < other_pos
  end

  test "GET /shopper shows empty note when there are no items", %{conn: conn} do
    conn = get(conn, ~p"/shopper")
    body = html_response(conn, 200)

    assert body =~ "Nothing on the list yet."
  end

  test "GET /shopper does not render an Other heading when all items have sections", %{
    conn: conn,
    produce: produce
  } do
    Repo.insert!(%Item{
      name: "Bananas",
      normalized_name: "bananas",
      status: :pending,
      section_id: produce.id
    })

    conn = get(conn, ~p"/shopper")
    body = html_response(conn, 200)

    refute body =~ ">Other<"
  end

  describe "PATCH /shopper/items/:id/cycle" do
    test "cycles a pending item to checked and returns its fragment", %{conn: conn} do
      {:ok, item} = Shopping.add_item(%{"name" => "Milk"})

      conn = patch(conn, ~p"/shopper/items/#{item.id}/cycle")
      body = html_response(conn, 200)

      assert body =~ ~s(id="shopper-item-#{item.id}")
      assert body =~ "checked"
      assert body =~ "Milk"
    end

    test "cycles a checked item to not_available", %{conn: conn} do
      item = Repo.insert!(%Item{name: "Milk", normalized_name: "milk", status: :checked})

      conn = patch(conn, ~p"/shopper/items/#{item.id}/cycle")
      body = html_response(conn, 200)

      assert body =~ ~s(data-status="not_available")
    end

    test "cycles a not_available item back to pending", %{conn: conn} do
      item =
        Repo.insert!(%Item{name: "Milk", normalized_name: "milk", status: :not_available})

      conn = patch(conn, ~p"/shopper/items/#{item.id}/cycle")
      body = html_response(conn, 200)

      assert body =~ ~s(data-status="pending")
    end

    test "returns only the item fragment, not the full page", %{conn: conn} do
      {:ok, item} = Shopping.add_item(%{"name" => "Milk"})

      conn = patch(conn, ~p"/shopper/items/#{item.id}/cycle")
      body = html_response(conn, 200)

      refute body =~ "<html"
      refute body =~ "pearview"
    end
  end
end
