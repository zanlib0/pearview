defmodule Pearview.AIStubs do
  @moduledoc """
  Shared `Pearview.AI` test doubles: the canonical OpenAI-wire-format tool-call
  builder, and the two stub shapes tests reach for most often.
  """

  @doc """
  A well-formed OpenAI-style forced tool call wrapping the given `assignments`
  (a list of `%{"item" => name, "section" => section_name}` maps).
  """
  def tool_call_response(assignments) do
    %{
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "tool_calls" => [
              %{
                "type" => "function",
                "function" => %{
                  "name" => "categorize_items",
                  "arguments" => Jason.encode!(%{"assignments" => assignments})
                }
              }
            ]
          }
        }
      ]
    }
  end

  @doc "Stubs `Pearview.AI` to return the given assignments."
  def stub_ai(assignments) do
    Req.Test.stub(Pearview.AI, fn conn ->
      Req.Test.json(conn, tool_call_response(assignments))
    end)
  end

  @doc "Fails loudly if the LLM is hit at all (used to prove cache-only resolution)."
  def refute_ai_called do
    Req.Test.stub(Pearview.AI, fn _conn ->
      raise "the LLM must not be called when every name resolves from cache"
    end)
  end
end
