defmodule Pearview.Shopping.Item do
  @moduledoc """
  One thing to buy, as typed by the Operator. Carries the raw `name`, a
  `normalized_name` (the cache key), an assigned Section once categorised
  (`section_id`, nullable), and a `status`. See `CONTEXT.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Pearview.Shopping.Section

  @statuses [:pending, :checked, :not_available]

  schema "items" do
    field :name, :string
    field :normalized_name, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    belongs_to :section, Section

    timestamps(type: :utc_datetime)
  end

  @doc """
  The recognised `status` values: #{inspect(@statuses)}.
  """
  def statuses, do: @statuses

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :normalized_name, :status, :section_id])
    |> validate_required([:name, :normalized_name, :status])
  end
end
