defmodule PearviewWeb.ShopperController do
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, _params) do
    render(conn, :index, groups: Shopping.list_grouped_for_shopper())
  end

  def cycle(conn, %{"id" => id}) do
    item = Shopping.get_item!(id)
    {:ok, item} = Shopping.cycle_item_status(item)

    conn
    |> put_root_layout(html: false)
    |> render(:shopper_item, item: item)
  end
end
