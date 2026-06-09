defmodule Pearview.AI do
  @moduledoc """
  The OpenRouter boundary: one synchronous, batched call that sorts grocery item
  names into a store's route Sections.

  Provider is OpenRouter's OpenAI-compatible chat-completions endpoint, called
  via `Req`. The API key is read from `OPENROUTER_API_KEY`; the model defaults to
  `deepseek/deepseek-v4-flash` and can be overridden with `OPENROUTER_MODEL`.
  Output is forced through an OpenAI-style **tool call** whose `section` field is
  an enum constrained to the seeded section names — the model's only way to say
  "I can't place this" is to omit the item.

  `categorize/2` never raises: transport failures, non-200 responses, and
  unparseable bodies all come back as `{:error, _}` so the caller can leave items
  uncategorised and retry on the next view-open (see ADR-0002).
  """

  @tool_name "categorize_items"
  @default_base_url "https://openrouter.ai/api/v1"
  @default_model "deepseek/deepseek-v4-flash"

  @doc """
  Categorise `names` (normalized item names) against `sections` (the store's
  Route — each a struct/map with `:name`, `:hints`, and `:position`).

  Returns `{:ok, mappings}` where `mappings` is a map of
  `normalized_name => section_name`, holding only names the model placed in a
  **real** section. Names the model omitted, or placed in a section that isn't in
  `sections`, are simply absent — the caller treats those as "unplaced".

  Returns `{:error, reason}` on any transport error, non-200 status, or malformed
  body. The caller must write no cache rows in that case.
  """
  def categorize([], _sections), do: {:ok, %{}}

  def categorize(names, sections) when is_list(names) and is_list(sections) do
    section_names = Enum.map(sections, & &1.name)

    case Req.post(req(),
           url: "/chat/completions",
           json: request_body(names, sections, section_names)
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse(body, names, section_names)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  # --- request building -----------------------------------------------------

  defp request_body(names, sections, section_names) do
    %{
      model: model(),
      messages: [
        %{role: "system", content: system_prompt()},
        %{role: "user", content: user_prompt(names, sections)}
      ],
      tools: [tool_schema(section_names)],
      tool_choice: %{type: "function", function: %{name: @tool_name}}
    }
  end

  defp tool_schema(section_names) do
    %{
      type: "function",
      function: %{
        name: @tool_name,
        description: "Assign each shopping-list item to the store section it belongs in.",
        parameters: %{
          type: "object",
          properties: %{
            assignments: %{
              type: "array",
              description:
                "One entry per item you can confidently place. Omit items that fit no section.",
              items: %{
                type: "object",
                properties: %{
                  item: %{type: "string", description: "the item name, exactly as given"},
                  section: %{type: "string", enum: section_names}
                },
                required: ["item", "section"]
              }
            }
          },
          required: ["assignments"]
        }
      }
    }
  end

  defp system_prompt do
    "You sort grocery shopping-list items into the sections of a specific store, " <>
      "following that store's aisle layout. Use only the sections provided. If an " <>
      "item does not clearly belong to any section, omit it rather than guessing. " <>
      "Call the #{@tool_name} function with your assignments."
  end

  defp user_prompt(names, sections) do
    section_lines =
      sections
      |> Enum.sort_by(& &1.position)
      |> Enum.map_join("\n", fn s ->
        case s.hints do
          h when h in [nil, ""] -> "- #{s.name}"
          h -> "- #{s.name} (e.g. #{h})"
        end
      end)

    item_lines = Enum.map_join(names, "\n", &"- #{&1}")

    """
    Store sections, in the order the shopper walks the store:
    #{section_lines}

    Items to categorise:
    #{item_lines}
    """
  end

  # --- response parsing -----------------------------------------------------

  defp parse(%{"choices" => [%{"message" => message} | _]}, names, section_names) do
    with {:ok, args_json} <- tool_arguments(message),
         {:ok, %{"assignments" => assignments}} when is_list(assignments) <-
           Jason.decode(args_json) do
      valid_sections = MapSet.new(section_names)
      requested = MapSet.new(names)

      mappings =
        assignments
        |> Enum.flat_map(fn
          %{"item" => item, "section" => section}
          when is_binary(item) and is_binary(section) ->
            if MapSet.member?(requested, item) and MapSet.member?(valid_sections, section) do
              [{item, section}]
            else
              []
            end

          _ ->
            []
        end)
        |> Map.new()

      {:ok, mappings}
    else
      _ -> {:error, :malformed_body}
    end
  end

  defp parse(_body, _names, _section_names), do: {:error, :malformed_body}

  defp tool_arguments(%{"tool_calls" => [%{"function" => %{"arguments" => args}} | _]})
       when is_binary(args),
       do: {:ok, args}

  defp tool_arguments(_message), do: :error

  # --- configuration --------------------------------------------------------

  defp req do
    base = [
      base_url: config(:base_url, @default_base_url),
      auth: {:bearer, api_key()},
      retry: false
    ]

    Req.new(Keyword.merge(base, config(:req_options, [])))
  end

  defp model do
    System.get_env("OPENROUTER_MODEL") || config(:model, @default_model)
  end

  defp api_key do
    config(:api_key, nil) || System.get_env("OPENROUTER_API_KEY") || ""
  end

  defp config(key, default) do
    :pearview
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
