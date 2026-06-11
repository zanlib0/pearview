defmodule PearviewWeb.ShopperController do
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, _params) do
    # Cache-hit names resolve synchronously here; never-seen names move to a
    # background LLM task and stay in Other until the next request. We render
    # immediately either way, showing a "Categorising" note while that task runs.
    categorising? = Shopping.categorize_uncategorized() == :categorising

    render(conn, :index,
      groups: Shopping.list_grouped_for_shopper(),
      categorising?: categorising?
    )
  end

  def cycle(conn, %{"id" => id}) do
    item = Shopping.get_item!(id)
    {:ok, item} = Shopping.cycle_item_status(item)

    conn
    |> put_root_layout(html: false)
    |> render(:shopper_item, item: item)
  end

  def end_trip(conn, _params) do
    Shopping.end_trip()

    conn
    |> put_root_layout(html: false)
    |> render(:shopper_list, groups: Shopping.list_grouped_for_shopper())
  end
end
