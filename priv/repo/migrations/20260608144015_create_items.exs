defmodule Pearview.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add :name, :string, null: false
      add :normalized_name, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :section_id, references(:sections, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:items, [:section_id])
  end
end
