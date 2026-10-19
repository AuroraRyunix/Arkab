defmodule Arkab.FakeServer.Plug do
  @moduledoc false
  @behaviour Elixir.Plug

  import Elixir.Plug.Conn

  def init(agent), do: agent

  def call(%{method: "POST", path_info: ["join", code]} = conn, agent) do
    {:ok, body, conn} = read_body(conn)
    identity = Jason.decode!(body)

    reply =
      Agent.get_and_update(agent, fn state ->
        cond do
          # A code of another hall, for a bridge still in this one.
          code == "ELS-WHR" ->
            {:elsewhere, state}

          MapSet.member?(state.codes, code) ->
            {{:ok, state.key, state.owner},
             %{state | codes: MapSet.delete(state.codes, code)} |> Map.put(:bridge, identity)}

          true ->
            {:gone, state}
        end
      end)

    case reply do
      {:ok, key, owner} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            "key" => key,
            "socket" => "/bridge/link",
            "server" => "fake",
            "owner" => owner
          })
        )

      :elsewhere ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{"error" => "elsewhere"}))

      :gone ->
        send_resp(conn, 410, "gone")
    end
  end

  def call(%{path_info: ["bridge", "link"]} = conn, agent) do
    conn
    |> WebSockAdapter.upgrade(Arkab.FakeServer.Socket, agent, timeout: 120_000)
    |> halt()
  end

  def call(conn, _agent), do: send_resp(conn, 404, "")
end
