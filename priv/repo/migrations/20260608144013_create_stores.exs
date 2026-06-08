defmodule Pearview.Repo.Migrations.CreateStores do
  use Ecto.Migration

  def change do
    create table(:stores) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
