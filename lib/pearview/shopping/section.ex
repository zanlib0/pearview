defmodule Pearview.Shopping.Section do
  @moduledoc """
  One stop on a Store's walk (e.g. produce, dairy). Has a name, a `position` in
  the route, and optional `hints` (example products that belong there, used as AI
  context). Belongs to exactly one Store. See `CONTEXT.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Pearview.Shopping.{Item, Store}

  schema "sections" do
    field :name, :string
    field :position, :integer
    field :hints, :string

    belongs_to :store, Store
    has_many :items, Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:name, :position, :hints, :store_id])
    |> validate_required([:name, :position, :store_id])
  end
end
