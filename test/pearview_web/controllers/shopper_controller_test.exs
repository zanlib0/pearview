defmodule PearviewWeb.ShopperControllerTest do
  use PearviewWeb.ConnCase

  alias Pearview.Repo
  alias Pearview.Shopping
  alias Pearview.Shopping.{Categorization, Item, Section, Store}

  # A well-formed OpenAI-style forced tool call wrapping the given assignments.
  defp tool_call_response(assignments) do
    %{
      "choices" => [
        %{
          "message" => %{
            "tool_calls" => [
              %{
                "function" => %{
                  "name" => "categorize_items",
                  "arguments" => Jason.encode!(%{"assignments" => assignments})
                }
              }
            ]
          }
        }
      ]
    }
  end

  setup do
    store = Repo.insert!(%Store{name: "Test Store"})
    produce = Repo.insert!(%Section{name: "Produce", position: 1, store_id: store.id})
    dairy = Repo.insert!(%Section{name: "Dairy & Eggs", position: 2, store_id: store.id})

    # Default: the LLM places nothing, so uncategorised items stay in Other.
    # Individual tests override this stub to assert placement or cache behaviour.
    Req.Test.stub(Pearview.AI, fn conn ->
      Req.Test.json(conn, tool_call_response([]))
    end)

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

  describe "GET /shopper categorisation on open" do
    test "renders immediately with the item in Other and a Categorising note, then places it on the next open",
         %{conn: conn, dairy: dairy} do
      {:ok, milk} = Shopping.add_item(%{"name" => "Milk"})
      test_pid = self()

      # Block the LLM at the call boundary so the first render deterministically
      # sees the pre-resolution state — exactly as production's slow round-trip
      # would. We release it once the first paint has been asserted.
      Req.Test.stub(Pearview.AI, fn c ->
        send(test_pid, {:ai_called, self()})
        receive do: (:proceed -> :ok), after: (2000 -> :ok)
        Req.Test.json(c, tool_call_response([%{"item" => "milk", "section" => "Dairy & Eggs"}]))
      end)

      # First open paints without waiting on the LLM: Milk is still in Other and
      # the static Categorising note stands in for the background run.
      body = conn |> get(~p"/shopper") |> html_response(200)

      assert body =~ "Categorising"
      assert body =~ "Other"
      assert body =~ "Milk"
      refute body =~ "Dairy &amp; Eggs"

      # Release the background LLM call; the next request picks up the section.
      assert_receive {:ai_called, task_pid}
      send(task_pid, :proceed)
      Pearview.DataCase.await_background_tasks()
      assert Repo.get!(Item, milk.id).section_id == dairy.id

      body = build_conn() |> get(~p"/shopper") |> html_response(200)

      assert body =~ "Dairy &amp; Eggs"
      assert body =~ "Milk"
      refute body =~ ">Other<"
      refute body =~ "Categorising"
    end

    test "leaves items the AI cannot place in Other and stops showing the note once cached", %{
      conn: conn
    } do
      Shopping.add_item(%{"name" => "Obscure Widget"})

      # default setup stub places nothing
      body = conn |> get(~p"/shopper") |> html_response(200)

      assert body =~ "Categorising"
      assert body =~ "Other"
      assert body =~ "Obscure Widget"

      # The unplaced answer is now cached, so the next open resolves from cache
      # with no background run and no note.
      Pearview.DataCase.await_background_tasks()
      body = build_conn() |> get(~p"/shopper") |> html_response(200)

      assert body =~ "Obscure Widget"
      refute body =~ "Categorising"
    end

    test "resolves an already-cached name synchronously, without the LLM or a note", %{
      conn: conn,
      store: store,
      produce: produce
    } do
      Repo.insert!(%Categorization{
        store_id: store.id,
        normalized_name: "bananas",
        section_id: produce.id,
        source: :ai
      })

      {:ok, bananas} = Shopping.add_item(%{"name" => "Bananas"})

      Req.Test.stub(Pearview.AI, fn _c ->
        raise "the LLM must not be called for a name already in the cache"
      end)

      body = conn |> get(~p"/shopper") |> html_response(200)

      assert body =~ "Produce"
      assert body =~ "Bananas"
      refute body =~ "Categorising"
      assert Repo.get!(Item, bananas.id).section_id == produce.id
    end

    test "renders without crashing when the AI call errors, retrying the note on the next open",
         %{
           conn: conn
         } do
      {:ok, milk} = Shopping.add_item(%{"name" => "Milk"})

      Req.Test.stub(Pearview.AI, fn c -> Plug.Conn.send_resp(c, 500, "boom") end)

      body = conn |> get(~p"/shopper") |> html_response(200)

      assert body =~ "Categorising"
      assert body =~ "Other"
      assert body =~ "Milk"

      # The failed call writes nothing, so the item stays in Other and the next
      # open starts a fresh run — the note shows again, no cache rows are written.
      Pearview.DataCase.await_background_tasks()
      assert Repo.get!(Item, milk.id).section_id == nil

      body = build_conn() |> get(~p"/shopper") |> html_response(200)

      assert body =~ "Categorising"
      assert body =~ "Milk"
      assert Repo.all(Categorization) == []

      Pearview.DataCase.await_background_tasks()
    end
  end

  describe "POST /shopper/trip/end" do
    test "deletes checked items from the list", %{conn: conn} do
      Repo.insert!(%Item{name: "Milk", normalized_name: "milk", status: :checked})
      Shopping.add_item(%{"name" => "Bread"})

      conn = post(conn, ~p"/shopper/trip/end")
      body = html_response(conn, 200)

      refute body =~ "Milk"
      assert body =~ "Bread"
    end

    test "resets not_available items so they appear as pending", %{conn: conn} do
      na = Repo.insert!(%Item{name: "Eggs", normalized_name: "eggs", status: :not_available})

      post(conn, ~p"/shopper/trip/end")

      assert Repo.get!(Item, na.id).status == :pending
    end

    test "returns the list fragment without a full page reload", %{conn: conn} do
      conn = post(conn, ~p"/shopper/trip/end")
      body = html_response(conn, 200)

      refute body =~ "<html"
      refute body =~ "pearview"
    end

    test "returns the empty-state note when nothing remains", %{conn: conn} do
      Repo.insert!(%Item{name: "Milk", normalized_name: "milk", status: :checked})

      conn = post(conn, ~p"/shopper/trip/end")
      body = html_response(conn, 200)

      assert body =~ "Nothing on the list yet."
    end
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
