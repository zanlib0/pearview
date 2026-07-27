defmodule Pearview.Repo.Migrations.CascadeCategorizationsOnSectionDelete do
  use Ecto.Migration

  # Deleting a Section must *drop* that section's cache rows, not turn them into
  # "asked, unplaced" rows — an unplaced row is never re-asked, so nilifying
  # would freeze every name that lived in the deleted section into Other for
  # good (PRD 01, story #22).
  #
  # SQLite cannot alter a foreign key in place, so both directions rebuild the
  # table: create it alongside with the wanted FK, copy the rows over, drop the
  # old one, rename, and re-create the indexes under their canonical names.

  def up, do: rebuild_categorizations(:delete_all)

  def down, do: rebuild_categorizations(:nilify_all)

  defp rebuild_categorizations(on_section_delete) do
    create table(:categorizations_rebuild) do
      add :store_id,
          references(:stores, on_delete: :delete_all, name: "categorizations_store_id_fkey"),
          null: false

      add :normalized_name, :string, null: false

      add :section_id,
          references(:sections,
            on_delete: on_section_delete,
            name: "categorizations_section_id_fkey"
          )

      add :source, :string, null: false, default: "ai"

      timestamps(type: :utc_datetime)
    end

    execute """
    INSERT INTO categorizations_rebuild
      (id, store_id, normalized_name, section_id, source, inserted_at, updated_at)
    SELECT id, store_id, normalized_name, section_id, source, inserted_at, updated_at
    FROM categorizations
    """

    drop table(:categorizations)
    rename table(:categorizations_rebuild), to: table(:categorizations)

    create unique_index(:categorizations, [:store_id, :normalized_name])
    create index(:categorizations, [:section_id])
  end
end
