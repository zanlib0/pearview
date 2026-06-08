defmodule PearviewWeb.ItemController do
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, _params) do
    render(conn, :index, items: Shopping.list_items())
  end

  @doc """
  Creates an item from the Operator's add form and returns just the new list
  row as an HTML fragment, which HTMX appends to the list (no full reload).
  """
  def create(conn, %{"item" => item_params}) do
    case Shopping.add_item(item_params) do
      {:ok, item} ->
        conn
        |> put_root_layout(html: false)
        |> render(:item_row, item: item)

      {:error, _changeset} ->
        send_resp(conn, :unprocessable_entity, "")
    end
  end
end
