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
  Returns a single item's display row — used by HTMX to cancel an in-progress
  edit and swap the read-only row back in.
  """
  def show(conn, %{"id" => id}) do
    item = Shopping.get_item!(id)

    conn
    |> put_root_layout(html: false)
    |> render(:item_row, item: item)
  end

  @doc """
  Returns the inline edit form for an item as an HTML fragment, which HTMX swaps
  in place of the read-only row.
  """
  def edit(conn, %{"id" => id}) do
    item = Shopping.get_item!(id)

    conn
    |> put_root_layout(html: false)
    |> render(:item_edit_row, item: item)
  end

  @doc """
  Renames an item and returns its updated display row, which HTMX swaps back in
  place of the edit form (no full reload). On invalid input the edit form is
  re-rendered so the Operator can correct it.
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
        |> render(:item_edit_row, item: item)
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
