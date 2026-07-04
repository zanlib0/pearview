defmodule Pearview.AITest do
  use ExUnit.Case, async: true

  import Pearview.AIStubs, only: [tool_call_response: 1]

  alias Pearview.AI

  # Sections as the context passes them: anything with name/hints/position.
  defp sections do
    [
      %{name: "Produce", hints: "fruit, veg", position: 1},
      %{name: "Dairy & Eggs", hints: "milk, cheese", position: 2}
    ]
  end

  describe "categorize/2 request shape" do
    test "posts to the chat-completions endpoint with bearer auth, model, and a section-name enum" do
      test_pid = self()

      Req.Test.stub(AI, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:request, conn.method, conn.request_path,
           Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(raw)}
        )

        Req.Test.json(conn, tool_call_response([]))
      end)

      assert {:ok, _} = AI.categorize(["bananas"], sections())

      assert_received {:request, "POST", path, auth, body}
      assert path == "/api/v1/chat/completions"
      assert auth == ["Bearer test-openrouter-key"]
      assert body["model"] == "deepseek/deepseek-v4-flash"
      assert body["tool_choice"]["function"]["name"] == "categorize_items"

      [tool] = body["tools"]
      assert tool["function"]["name"] == "categorize_items"

      enum =
        tool["function"]["parameters"]["properties"]["assignments"]["items"]["properties"][
          "section"
        ]["enum"]

      assert enum == ["Produce", "Dairy & Eggs"]
    end
  end

  describe "categorize/2 response parsing" do
    test "parses a well-formed tool call into name -> section mappings" do
      Req.Test.stub(AI, fn conn ->
        Req.Test.json(
          conn,
          tool_call_response([
            %{"item" => "bananas", "section" => "Produce"},
            %{"item" => "milk", "section" => "Dairy & Eggs"}
          ])
        )
      end)

      assert {:ok, mappings} = AI.categorize(["bananas", "milk"], sections())
      assert mappings == %{"bananas" => "Produce", "milk" => "Dairy & Eggs"}
    end

    test "drops assignments whose section is not a real store section" do
      Req.Test.stub(AI, fn conn ->
        Req.Test.json(
          conn,
          tool_call_response([
            %{"item" => "bananas", "section" => "Produce"},
            %{"item" => "sunscreen", "section" => "Pharmacy"}
          ])
        )
      end)

      assert {:ok, %{"bananas" => "Produce"}} =
               AI.categorize(["bananas", "sunscreen"], sections())
    end

    test "ignores assignments for items that were not requested" do
      Req.Test.stub(AI, fn conn ->
        Req.Test.json(
          conn,
          tool_call_response([
            %{"item" => "bananas", "section" => "Produce"},
            %{"item" => "caviar", "section" => "Produce"}
          ])
        )
      end)

      assert {:ok, %{"bananas" => "Produce"}} = AI.categorize(["bananas"], sections())
    end

    test "an item the model omits is simply absent from the mappings" do
      Req.Test.stub(AI, fn conn ->
        Req.Test.json(conn, tool_call_response([%{"item" => "bananas", "section" => "Produce"}]))
      end)

      assert {:ok, mappings} = AI.categorize(["bananas", "obscure widget"], sections())
      assert mappings == %{"bananas" => "Produce"}
    end
  end

  describe "categorize/2 error handling" do
    test "returns an error (without raising) on a non-200 response" do
      Req.Test.stub(AI, fn conn -> Plug.Conn.send_resp(conn, 500, "upstream boom") end)

      assert {:error, {:http_status, 500, _}} = AI.categorize(["bananas"], sections())
    end

    test "returns an error on a transport failure" do
      Req.Test.stub(AI, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, {:transport, _}} = AI.categorize(["bananas"], sections())
    end

    test "returns an error on a 200 with no tool call" do
      Req.Test.stub(AI, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "no tools here"}}]})
      end)

      assert {:error, :malformed_body} = AI.categorize(["bananas"], sections())
    end

    test "returns an error on a 200 whose tool arguments are not valid JSON" do
      Req.Test.stub(AI, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{
              "message" => %{
                "tool_calls" => [%{"function" => %{"arguments" => "{not json"}}]
              }
            }
          ]
        })
      end)

      assert {:error, :malformed_body} = AI.categorize(["bananas"], sections())
    end
  end

  describe "categorize/2 short-circuits" do
    test "returns an empty map for no names without calling the API" do
      Req.Test.stub(AI, fn _conn -> raise "API should not be called for an empty name list" end)

      assert {:ok, %{}} = AI.categorize([], sections())
    end
  end
end
