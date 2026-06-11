defmodule Pearview.Shopping.CategorizeUncategorized do
  @moduledoc """
  Resolves every uncategorised Item (`section_id` nil) against the store's Route,
  **cache first, LLM second**, stamping the resulting `section_id` onto the
  matching items. This is the categorisation orchestration triggered on
  Shopper-view open; `Pearview.Shopping` delegates to it.

  The cache pass is **synchronous** so the page opens already grouped for names
  it has seen before; the LLM pass runs in an **unlinked background task** so the
  first paint never blocks on OpenRouter (issue #18). For each distinct
  uncategorised `normalized_name`:

    * A cache hit (`categorizations` row for this store) is used for free,
      synchronously — a placed row stamps the items, an unplaced row
      (`section_id` nil) leaves them in Other. Neither is re-sent to the LLM.
    * Never-seen names are handed to a supervised background task (see
      `resolve_missed/2`) that calls `Pearview.AI` in one batched call. They sit
      in Other until that task finishes and the **next** request for the view
      picks up the stamped sections; there is no in-page swap. At most **one run
      is in flight at a time** — opens that arrive while a run is working show
      the note but don't start a second, duplicate call for the same names.
    * On an AI error, **no cache rows are written** and the missed items are left
      uncategorised — the next open retries. See ADR-0002.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Pearview.AI
  alias Pearview.Repo
  alias Pearview.Shopping.{Categorization, Item, Section, Store}

  @doc """
  Runs the cache pass synchronously, then starts a background task for any
  never-seen names. Returns:

    * `:categorising` when a background LLM run was started for this request —
      the caller renders the "Categorising" note and the missed items stay in
      Other until the next request picks them up.
    * `:idle` otherwise: no store, nothing uncategorised, or every name resolved
      straight from the cache.
  """
  def call do
    with %Store{} = store <- current_store(),
         [_ | _] = names <- uncategorized_normalized_names() do
      {cached, missed} = resolve_from_cache(store, names)
      stamp_cache_hits(cached)

      case missed do
        [] ->
          :idle

        _ ->
          # Keep at most one run in flight. A refresh — or #7's refetch on every
          # unlock — that lands while the LLM is still working shows the note but
          # must not start a second, duplicate OpenRouter call for the same
          # names. (Cache-misses have no cache row yet, so without this guard
          # every open during the in-flight window re-asks the model.)
          unless run_in_flight?() do
            start_background_resolution(store, missed)
          end

          :categorising
      end
    else
      _ -> :idle
    end
  end

  # The TaskSupervisor hosts only categorisation runs (see Pearview.Application),
  # so any live child means a run is already resolving names. There is a tiny
  # check-then-start window where two simultaneous opens could both start a run;
  # for a 2-user app that's harmless — write-through and stamping are idempotent.
  defp run_in_flight? do
    Task.Supervisor.children(Pearview.TaskSupervisor) != []
  end

  @doc """
  Synchronously resolves `missed` (never-seen normalized names) for `store`
  against its Route via `Pearview.AI`, writing every answer through to the cache
  and stamping placed items. This is the unit of work the background task runs;
  it is also called directly in tests. Returns `:ok` (including the AI-error
  case, which writes nothing — see ADR-0002).
  """
  def resolve_missed(%Store{} = store, missed) when is_list(missed) do
    resolve_missed_with_ai(store, route_sections(store), missed)
  end

  defp start_background_resolution(store, missed) do
    Task.Supervisor.start_child(Pearview.TaskSupervisor, fn ->
      resolve_missed(store, missed)
    end)
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

      {:error, reason} ->
        # We never got an answer — write nothing, leave the items in Other, and
        # let the next view-open retry. (ADR-0002 rule 4.) Log the reason: a
        # silent failure here reads as "categorising forever", retrying the LLM
        # on every open with no clue why.
        Logger.warning(
          "AI categorisation failed, leaving #{length(missed)} item(s) in Other: " <>
            inspect(reason)
        )

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
