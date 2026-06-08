defmodule Pearview.Repo.Migrations.CreateSections do
  use Ecto.Migration

  def change do
    create table(:sections) do
      add :name, :string, null: false
      add :position, :integer, null: false
      add :hints, :text
      add :store_id, references(:stores, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sections, [:store_id])
  end
end
