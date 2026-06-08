defmodule PearviewWeb.ItemController do
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, _params) do
    render(conn, :index, items: Shopping.list_items())
  end
end
