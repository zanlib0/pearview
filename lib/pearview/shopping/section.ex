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
    |> cast(attrs, [:name, :position, :store_id])
    # `hints` casts with `empty_values: []` so a blank field is a real (blank)
    # value rather than a no-op — that is how the Operator clears a section's
    # hints. `name` keeps the default, where blank reads as missing.
    |> cast(attrs, [:hints], empty_values: [])
    |> update_change(:name, &trim_name/1)
    |> nilify_blank_hints()
    |> validate_required([:name, :position, :store_id])
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name

  defp nilify_blank_hints(changeset) do
    case get_change(changeset, :hints) do
      hints when is_binary(hints) ->
        case String.trim(hints) do
          "" -> put_change(changeset, :hints, nil)
          trimmed -> put_change(changeset, :hints, trimmed)
        end

      _ ->
        changeset
    end
  end
end
