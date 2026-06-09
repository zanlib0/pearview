defmodule Pearview.Repo.Migrations.CreateCategorizations do
  use Ecto.Migration

  def change do
    create table(:categorizations) do
      add :store_id, references(:stores, on_delete: :delete_all), null: false
      add :normalized_name, :string, null: false
      add :section_id, references(:sections, on_delete: :nilify_all)
      add :source, :string, null: false, default: "ai"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categorizations, [:store_id, :normalized_name])
    create index(:categorizations, [:section_id])
  end
end
