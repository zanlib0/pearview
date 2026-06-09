defmodule Pearview.Shopping.Categorization do
  @moduledoc """
  The durable record of "where does this name go in this store" — the
  categorisation cache, keyed on `(store_id, normalized_name)`. A row's
  `section_id` is **nullable**: `nil` means "asked, unplaced" (the AI could not
  place the name; it stays in Other and is never re-sent). `source` is `:ai` for
  cache rows written from the LLM and `:user` for a manual correction (Phase 2);
  a user correction always wins and is never overwritten by AI.

  An Item's `section_id` is just a projection stamped from this cache, so items
  can be deleted (End trip) without losing knowledge. See
  `docs/adr/0002-categorization-cache-not-items.md` and `CONTEXT.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Pearview.Shopping.{Section, Store}

  @sources [:ai, :user]

  schema "categorizations" do
    field :normalized_name, :string
    field :source, Ecto.Enum, values: @sources, default: :ai

    belongs_to :store, Store
    belongs_to :section, Section

    timestamps(type: :utc_datetime)
  end

  @doc """
  The recognised `source` values: #{inspect(@sources)}.
  """
  def sources, do: @sources

  @doc false
  def changeset(categorization, attrs) do
    categorization
    |> cast(attrs, [:normalized_name, :source, :store_id, :section_id])
    |> validate_required([:normalized_name, :source, :store_id])
    |> unique_constraint([:store_id, :normalized_name])
    |> assoc_constraint(:store)
  end
end
