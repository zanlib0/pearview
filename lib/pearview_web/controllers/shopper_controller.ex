defmodule PearviewWeb.ShopperController do
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, _params) do
    # Resolve any uncategorised items (cache first, LLM second) before rendering,
    # so the list opens already grouped into the store's route. The categorise
    # call is a no-op once everything is placed, so repeat opens are cheap.
    Shopping.categorize_uncategorized()

    render(conn, :index, groups: Shopping.list_grouped_for_shopper())
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
