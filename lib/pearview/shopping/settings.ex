defmodule Pearview.Shopping.Settings do
  @moduledoc """
  The app-wide settings singleton — one row, id 1, upserted. It holds the
  **Selected store**: the one Store the Shopper is currently walking, shared
  across both phones rather than kept per device (see `CONTEXT.md`).

  `selected_store_id` is nullable: no row, or a row pointing nowhere, both mean
  "no store selected yet" and the Shopper is asked to pick. Deleting the
  selected Store nilifies it (FK `:nilify_all`), so the selection can never
  point at a store that no longer exists.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Pearview.Shopping.Store

  @singleton_id 1

  @primary_key {:id, :integer, autogenerate: false}
  schema "settings" do
    belongs_to :store, Store, foreign_key: :selected_store_id

    timestamps(type: :utc_datetime)
  end

  @doc "The fixed primary key of the one settings row."
  def singleton_id, do: @singleton_id

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:selected_store_id])
    |> put_change(:id, @singleton_id)
    |> foreign_key_constraint(:selected_store_id)
  end
end
