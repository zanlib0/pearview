defmodule Pearview.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  @doc """
  The app-wide settings singleton. Its only column for now is the Selected
  store — the one Store the Shopper is currently walking, shared across both
  phones (no per-device selection, no Trip/session table).

  `id` is a plain integer key defaulting to 1 rather than a serial: the row is
  always written as an upsert on id 1, so "the settings" is always `settings#1`.
  (A `CHECK (id = 1)` would say so in the schema, but SQLite cannot add a
  constraint to a table, and the singleton is never written by anything but
  `Pearview.Shopping.select_store/1`.) `selected_store_id` nilifies when its
  Store is deleted, which is how deleting the selected store clears the
  selection.
  """
  def change do
    create table(:settings, primary_key: false) do
      add :id, :integer, primary_key: true, default: 1
      add :selected_store_id, references(:stores, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:settings, [:selected_store_id])
  end
end
