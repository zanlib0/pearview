defmodule Pearview.Shopping.Store do
  @moduledoc """
  A physical shop the Shopper visits. Has a name and an ordered set of Sections
  (its Route). See `CONTEXT.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Pearview.Shopping.Section

  schema "stores" do
    field :name, :string

    has_many :sections, Section

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(store, attrs) do
    store
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
