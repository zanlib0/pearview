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

  @doc """
  Renames an item from the inline name field and returns its updated row, which
  HTMX swaps in place (no full reload). On invalid input the row is re-rendered
  unchanged with a 422, so HTMX leaves the existing row in place.
  """
  def update(conn, %{"id" => id, "item" => item_params}) do
    item = Shopping.get_item!(id)

    case Shopping.update_item(item, item_params) do
      {:ok, item} ->
        conn
        |> put_root_layout(html: false)
        |> render(:item_row, item: item)

      {:error, _changeset} ->
        conn
        |> put_root_layout(html: false)
        |> put_status(:unprocessable_entity)
        |> render(:item_row, item: item)
    end
  end

  @doc """
  Hard-deletes an item and returns an empty body; HTMX removes its row from the
  list (no full reload).
  """
  def delete(conn, %{"id" => id}) do
    item = Shopping.get_item!(id)
    {:ok, _item} = Shopping.delete_item(item)

    send_resp(conn, :ok, "")
  end
end
