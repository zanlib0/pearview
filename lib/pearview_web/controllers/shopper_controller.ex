defmodule PearviewWeb.ShopperController do
  @moduledoc """
  The Shopper view: the route-ordered list for the store being walked, plus the
  store dropdown that decides which store that is.

  A plain `GET /shopper` — the first open, a refresh, or Phase 1's refetch when
  the phone is unlocked — reads the **Selected store** and resolves only the
  items that are still uncategorised. It never re-nulls the list, so nothing
  moves under the Shopper mid-trip. Only changing the dropdown re-resolves
  everything, against the newly chosen store.
  """
  use PearviewWeb, :controller

  alias Pearview.Shopping

  def index(conn, _params) do
    # Cache-hit names resolve synchronously here; never-seen names move to a
    # background LLM task and stay in Other until the next request. We render
    # immediately either way, showing a "Categorising" note while that task runs.
    categorising? = Shopping.categorize_uncategorized() == :categorising

    render(conn, :index,
      stores: Shopping.list_stores(),
      selected_store: Shopping.get_selected_store(),
      groups: Shopping.list_grouped_for_shopper(),
      categorising?: categorising?
    )
  end

  @doc """
  Makes the store chosen in the dropdown the Selected store — for both phones,
  not just this one — and answers with the list re-grouped for its Route. The
  switch nulls every Item's section and re-resolves cache-first, so a store we
  have shopped before re-sorts without touching the LLM; genuinely new names
  land in Other with the "Categorising" note until the background run finishes.
  """
  def select_store(conn, %{"store_id" => store_id}) do
    store = Shopping.get_store!(store_id)
    categorising? = Shopping.select_store(store) == :categorising

    conn
    |> put_root_layout(html: false)
    |> render(:shopper_list,
      groups: Shopping.list_grouped_for_shopper(),
      categorising?: categorising?
    )
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
    |> render(:shopper_list, groups: Shopping.list_grouped_for_shopper(), categorising?: false)
  end
end
