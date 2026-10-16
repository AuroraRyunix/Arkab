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
        if MapSet.member?(state.codes, code) do
          {{:ok, state.key, state.owner},
           %{state | codes: MapSet.delete(state.codes, code)} |> Map.put(:bridge, identity)}
        else
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
