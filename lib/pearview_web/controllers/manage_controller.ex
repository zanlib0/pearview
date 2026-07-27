defmodule PearviewWeb.ManageController do
  @moduledoc """
  The Manage surface: the "at home, maintaining the app" area, distinct from the
  Operator and Shopper views (see `CONTEXT.md`). It is not a third persona and
  is not access-controlled — roles are a soft UI split.

  This slice covers Store maintenance and, within one Store at a time, its Route
  — the Sections the Shopper walks, in position order. Every mutation answers
  with an HTML fragment for an HTMX swap, never a redirect, so the page never
  reloads.

  Store mutations also send an `HX-Trigger: stores-changed` header, which the
  Route panel listens for: adding, renaming or deleting a store changes what the
  panel's store picker should read, so it refetches itself.
  """
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, params) do
    render(conn, :index, route_assigns(params))
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
        |> stores_changed()
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
        |> stores_changed()
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

    conn
    |> stores_changed()
    |> send_resp(:ok, "")
  end

  @doc """
  Renders the whole Route panel for one Store — the store picker, the add form
  and the store's Sections in route order. This is what the picker swaps in, and
  what the panel refetches when the set of stores changes.
  """
  def sections(conn, params) do
    conn
    |> put_root_layout(html: false)
    |> render(:route_panel, route_assigns(params))
  end

  @doc """
  Adds a Section to the end of a Store's Route and returns the store's whole
  section list, so the new stop arrives already in route order.
  """
  def create_section(conn, %{"store_id" => store_id, "section" => section_params}) do
    store = Shopping.get_store!(store_id)

    case Shopping.create_section(Map.put(section_params, "store_id", store.id)) do
      {:ok, _section} ->
        render_section_list(conn, store)

      {:error, _changeset} ->
        send_resp(conn, :unprocessable_entity, "")
    end
  end

  @doc """
  Renames a Section or rewrites its hints — the two inline fields on a section
  row post here — and returns the updated row. On invalid input the unchanged
  row comes back with a 422.
  """
  def update_section(conn, %{"id" => id, "section" => section_params}) do
    section = Shopping.get_section!(id)

    case Shopping.update_section(section, section_params) do
      {:ok, section} ->
        conn
        |> put_root_layout(html: false)
        |> render(:section_row, section: section)

      {:error, _changeset} ->
        conn
        |> put_root_layout(html: false)
        |> put_status(:unprocessable_entity)
        |> render(:section_row, section: section)
    end
  end

  @doc """
  Moves a Section one stop earlier or later in its Store's Route (the up/down
  controls swap adjacent positions) and returns the section list in its new
  order. At either end of the walk the move is a no-op and the list comes back
  unchanged.
  """
  def move_section(conn, %{"id" => id, "direction" => direction})
      when direction in ~w(up down) do
    section = Shopping.get_section!(id)
    {:ok, sections} = Shopping.move_section(section, String.to_existing_atom(direction))

    conn
    |> put_root_layout(html: false)
    |> render(:section_list, sections: sections)
  end

  @doc """
  Removes a stop from a Store's Route and returns an empty body so HTMX removes
  its row. Its items stay on the list (uncategorised) and its cache rows go.
  """
  def delete_section(conn, %{"id" => id}) do
    section = Shopping.get_section!(id)
    {:ok, _section} = Shopping.delete_section(section)

    send_resp(conn, :ok, "")
  end

  # The Route panel shows one store at a time. Which one is a view concern for
  # now: the requested store if it still exists, else the first store by name.
  # (The Shopper's Selected store is a separate, later slice.)
  defp route_assigns(params) do
    stores = Shopping.list_stores()
    store = pick_store(stores, params["store_id"])

    [stores: stores, store: store, sections: sections_for(store)]
  end

  defp pick_store(stores, nil), do: List.first(stores)

  defp pick_store(stores, store_id) do
    Enum.find(stores, &(to_string(&1.id) == store_id)) || List.first(stores)
  end

  defp sections_for(nil), do: []
  defp sections_for(store), do: Shopping.list_sections(store)

  defp render_section_list(conn, store) do
    conn
    |> put_root_layout(html: false)
    |> render(:section_list, sections: Shopping.list_sections(store))
  end

  defp stores_changed(conn), do: put_resp_header(conn, "hx-trigger", "stores-changed")
end
