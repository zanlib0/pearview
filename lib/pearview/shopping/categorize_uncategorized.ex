defmodule Pearview.Shopping.CategorizeUncategorized do
  @moduledoc """
  Resolves every uncategorised Item (`section_id` nil) against the store's Route,
  **cache first, LLM second**, stamping the resulting `section_id` onto the
  matching items. This is the categorisation orchestration triggered on
  Shopper-view open; `Pearview.Shopping` delegates to it.

  For each distinct uncategorised `normalized_name`:

    * A cache hit (`categorizations` row for this store) is used for free — a
      placed row stamps the items, an unplaced row (`section_id` nil) leaves them
      in Other. Neither is re-sent to the LLM.
    * Never-seen names go to `Pearview.AI` in one batched call. Every successful
      answer is written through to the cache (including **unplaced** rows for
      names the model omits or places off-route) and placed items are stamped.
    * On an AI error, **no cache rows are written** and the missed items are left
      uncategorised — the next open retries. See ADR-0002.
  """

  import Ecto.Query, warn: false

  alias Pearview.AI
  alias Pearview.Repo
  alias Pearview.Shopping.{Categorization, Item, Section, Store}

  @doc """
  Runs the resolution described in the module doc. Returns `:ok`, including the
  no-op case where there is no store or nothing left to resolve.
  """
  def call do
    with %Store{} = store <- current_store(),
         [_ | _] = names <- uncategorized_normalized_names() do
      sections = route_sections(store)
      {cached, missed} = resolve_from_cache(store, names)

      stamp_cache_hits(cached)
      resolve_missed_with_ai(store, sections, missed)

      :ok
    else
      _ -> :ok
    end
  end

  defp current_store do
    Repo.one(from s in Store, order_by: [asc: s.id], limit: 1)
  end

  defp route_sections(%Store{id: store_id}) do
    Section
    |> where([s], s.store_id == ^store_id)
    |> order_by(asc: :position)
    |> Repo.all()
  end

  defp uncategorized_normalized_names do
    Item
    |> where([i], is_nil(i.section_id))
    |> distinct(true)
    |> select([i], i.normalized_name)
    |> Repo.all()
  end

  # Splits the names into `{cache_hits, cache_misses}`, where cache_hits maps
  # normalized_name => section_id (possibly nil for an "asked, unplaced" row).
  defp resolve_from_cache(%Store{id: store_id}, names) do
    cached =
      Categorization
      |> where([c], c.store_id == ^store_id and c.normalized_name in ^names)
      |> select([c], {c.normalized_name, c.section_id})
      |> Repo.all()
      |> Map.new()

    {cached, Enum.reject(names, &Map.has_key?(cached, &1))}
  end

  defp stamp_cache_hits(cached) do
    Enum.each(cached, fn
      {_name, nil} -> :ok
      {name, section_id} -> stamp_items(name, section_id)
    end)
  end

  defp resolve_missed_with_ai(_store, _sections, []), do: :ok

  defp resolve_missed_with_ai(store, sections, missed) do
    case AI.categorize(missed, sections) do
      {:ok, mappings} ->
        section_id_by_name = Map.new(sections, &{&1.name, &1.id})

        Enum.each(missed, fn name ->
          section_id = section_id_by_name[mappings[name]]
          write_through(store, name, section_id)
          if section_id, do: stamp_items(name, section_id)
        end)

      {:error, _reason} ->
        # We never got an answer — write nothing, leave the items in Other, and
        # let the next view-open retry. (ADR-0002 rule 4.)
        :ok
    end
  end

  defp stamp_items(name, section_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Item
    |> where([i], i.normalized_name == ^name and is_nil(i.section_id))
    |> Repo.update_all(set: [section_id: section_id, updated_at: now])
  end

  defp write_through(%Store{id: store_id}, name, section_id) do
    %Categorization{}
    |> Categorization.changeset(%{
      store_id: store_id,
      normalized_name: name,
      section_id: section_id,
      source: :ai
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:store_id, :normalized_name])
  end
end
