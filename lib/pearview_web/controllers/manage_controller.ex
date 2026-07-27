defmodule PearviewWeb.ManageController do
  @moduledoc """
  The Manage surface: the "at home, maintaining the app" area, distinct from the
  Operator and Shopper views (see `CONTEXT.md`). It is not a third persona and
  is not access-controlled — roles are a soft UI split.

  This slice covers Store maintenance. Every mutation answers with an HTML
  fragment for an HTMX swap, never a redirect, so the page never reloads.
  """
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, _params) do
    render(conn, :index, stores: Shopping.list_stores())
  end

  @doc """
  Creates a Store from the Manage add form and returns just its row, which HTMX
  appends to the store list.
  """
  def create_store(conn, %{"store" => store_params}) do
    case Shopping.create_store(store_params) do
      {:ok, store} ->
        conn
        |> put_root_layout(html: false)
        |> render(:store_row, store: store)

      {:error, _changeset} ->
        send_resp(conn, :unprocessable_entity, "")
    end
  end

  @doc """
  Renames a Store from its inline name field and returns its updated row. On
  invalid input the unchanged row comes back with a 422, so HTMX leaves what is
  on screen alone.
  """
  def update_store(conn, %{"id" => id, "store" => store_params}) do
    store = Shopping.get_store!(id)

    case Shopping.update_store(store, store_params) do
      {:ok, store} ->
        conn
        |> put_root_layout(html: false)
        |> render(:store_row, store: store)

      {:error, _changeset} ->
        conn
        |> put_root_layout(html: false)
        |> put_status(:unprocessable_entity)
        |> render(:store_row, store: store)
    end
  end

  @doc """
  Deletes a Store — along with its Route and its cached Categorizations — and
  returns an empty body so HTMX removes its row.
  """
  def delete_store(conn, %{"id" => id}) do
    store = Shopping.get_store!(id)
    {:ok, _store} = Shopping.delete_store(store)

    send_resp(conn, :ok, "")
  end
end
