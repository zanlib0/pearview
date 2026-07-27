defmodule PearviewWeb.ManageController do
  @moduledoc """
  The Manage surface: the "at home, maintaining the app" area, distinct from the
  Operator and Shopper views (see `CONTEXT.md`). It is not a third persona and
  is not access-controlled — roles are a soft UI split.

  This slice covers Store maintenance and, within one Store at a time, its Route
  — the Sections the Shopper walks, in position order — and its Categorization
  cache. Every mutation answers with an HTML fragment for an HTMX swap, never a
  redirect, so the page never reloads.

  Store mutations also send an `HX-Trigger: stores-changed` header, which the
  store-scoped panels listen for: adding, renaming or deleting a store changes
  what their store pickers should read, so they refetch themselves. Section
  renames and deletes send `sections-changed` for the same reason — they change
  what the cache panel prints, or which rows it has at all.
  """
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, params) do
    render(conn, :index, index_assigns(params))
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
        |> sections_changed()
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

    conn
    |> sections_changed()
    |> send_resp(:ok, "")
  end

  @doc """
  Renders the whole Categorization cache panel for one Store — the store picker
  and every name that store has an answer for, unplaced rows included. This is
  what the picker swaps in, and what the panel refetches when the set of stores
  changes.
  """
  def categorizations(conn, params) do
    conn
    |> put_root_layout(html: false)
    |> render(:cache_panel, cache_assigns(params))
  end

  @doc """
  Prunes one row from a Store's categorisation cache and returns an empty body
  so HTMX removes its row. Items on the list keep the Section they already
  carry (ADR-0004); the name re-resolves the next time it is added.
  """
  def delete_categorization(conn, %{"id" => id}) do
    categorization = Shopping.get_categorization!(id)
    {:ok, _categorization} = Shopping.delete_categorization(categorization)

    send_resp(conn, :ok, "")
  end

  # The store-scoped panels each show one store at a time. Which one is a view
  # concern for now: the requested store if it still exists, else the first
  # store by name. (The Shopper's Selected store is a separate, later slice.)
  defp index_assigns(params) do
    {stores, store} = scoped_store(params)

    [
      stores: stores,
      store: store,
      sections: sections_for(store),
      categorizations: categorizations_for(store)
    ]
  end

  defp route_assigns(params) do
    {stores, store} = scoped_store(params)

    [stores: stores, store: store, sections: sections_for(store)]
  end

  defp cache_assigns(params) do
    {stores, store} = scoped_store(params)

    [stores: stores, store: store, categorizations: categorizations_for(store)]
  end

  defp scoped_store(params) do
    stores = Shopping.list_stores()

    {stores, pick_store(stores, params["store_id"])}
  end

  defp pick_store(stores, nil), do: List.first(stores)

  defp pick_store(stores, store_id) do
    Enum.find(stores, &(to_string(&1.id) == store_id)) || List.first(stores)
  end

  defp sections_for(nil), do: []
  defp sections_for(store), do: Shopping.list_sections(store)

  defp categorizations_for(nil), do: []
  defp categorizations_for(store), do: Shopping.list_categorizations(store)

  defp render_section_list(conn, store) do
    conn
    |> put_root_layout(html: false)
    |> render(:section_list, sections: Shopping.list_sections(store))
  end

  defp stores_changed(conn), do: put_resp_header(conn, "hx-trigger", "stores-changed")

  # Renaming a Section changes the name the cache panel prints beside every name
  # filed there, and deleting one takes those cache rows with it (FK cascade), so
  # both leave the cache panel stale on the same page. It refetches on this.
  defp sections_changed(conn), do: put_resp_header(conn, "hx-trigger", "sections-changed")
end
