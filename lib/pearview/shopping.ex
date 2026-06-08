defmodule Pearview.Shopping do
  @moduledoc """
  The Shopping context: all data access for the shared shopping list — Stores,
  their route Sections, and the Items on the list.

  Later phases extend this context with item add/edit/delete and the AI
  categorisation orchestration (see `docs/prd/00-minimal-ai-shopping-loop.md`).
  For Phase 1 the read path is enough.
  """

  import Ecto.Query, warn: false

  alias Pearview.Repo
  alias Pearview.Shopping.Item

  @doc """
  Returns every Item on the shared list, in insertion order.
  """
  def list_items do
    Item
    |> order_by(asc: :inserted_at, asc: :id)
    |> Repo.all()
  end
end
