defmodule PearviewWeb.ShopperController do
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, _params) do
    render(conn, :index, groups: Shopping.list_grouped_for_shopper())
  end
end
