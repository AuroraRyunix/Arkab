defmodule Arkab.FakeServer do
  @moduledoc """
  An Alnasl that is only the link: `POST /join/:code` and the socket at
  `/bridge/link`, speaking `Arkab.Protocol`, on a port of its own. It keeps
  every event it accepted, in order, ignores numbers it has seen, and can
  be told to stop answering, refuse, or remove the bridge.

  Started per test (`start/1`); `down/1` and `up/1` take its listener away
  and bring it back on the same port, with what it held.
  """

  use Agent

  alias Arkab.Protocol

  def start(opts \\ []) do
    {:ok, agent} =
      Agent.start_link(fn ->
        %{
          codes: MapSet.new(Keyword.get(opts, :codes, ["K7Q-4MD"])),
          key: "fake-key-" <> Integer.to_string(System.unique_integer([:positive])),
          events: [],
          seen: 0,
          sockets: [],
          replies: [],
          boards: nil,
          owner: Keyword.get(opts, :owner, true),
          ack?: true
        }
      end)

    {:ok, port} = listen(agent, Keyword.get(opts, :port, 0))
    %{agent: agent, port: port, listener: Process.get({__MODULE__, agent})}
  end

  defp listen(agent, port) do
    {:ok, pid} =
      Bandit.start_link(
        plug: {__MODULE__.Plug, agent},
        port: port,
        ip: :loopback,
        startup_log: false
      )

    # Not linked: taking it down is a server going away, not the test.
    Process.unlink(pid)
    Process.put({__MODULE__, agent}, pid)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    {:ok, port}
  end

  def link(server, code \\ "K7Q-4MD"), do: "http://127.0.0.1:#{server.port}/join/#{code}"

  @doc "Takes the listener and every open socket away."
  def down(server) do
    Supervisor.stop(Process.get({__MODULE__, server.agent}))
    Agent.update(server.agent, &%{&1 | sockets: []})
    server
  end

  def up(server) do
    {:ok, _port} = listen(server.agent, server.port)
    server
  end

  def events(server), do: get(server, :events) |> Enum.reverse()
  def seqs(server), do: Enum.map(events(server), & &1.seq)
  def get(server, key), do: Agent.get(server.agent, &Map.fetch!(&1, key))
  def set(server, key, value), do: Agent.update(server.agent, &Map.put(&1, key, value))

  @doc "Sends a frame down every open socket."
  def push(server, frame), do: for(pid <- get(server, :sockets), do: send(pid, {:push, frame}))

  defmodule Plug do
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

  defmodule Socket do
    @moduledoc false
    @behaviour WebSock

    def init(agent) do
      me = self()
      Agent.update(agent, &%{&1 | sockets: [me | &1.sockets]})
      {:ok, %{agent: agent, hello?: false}}
    end

    def handle_in({text, opcode: :text}, state) do
      {:ok, frame} = Protocol.decode(text)
      handle(frame, state)
    end

    def handle_in(_other, state), do: {:ok, state}

    def handle_info({:push, frame}, state),
      do: {:push, {:text, Protocol.encode(frame)}, state}

    def handle_info(_other, state), do: {:ok, state}

    defp handle(%{"type" => "hello", "key" => key, "v" => v}, state) do
      server = Agent.get(state.agent, & &1)

      cond do
        not Protocol.accepts?(v) ->
          {:stop, :normal, {1000, "version"},
           [{:text, Protocol.encode(Protocol.refused("version"))}], state}

        key != server.key or Map.get(server, :revoked, false) ->
          reason = if Map.get(server, :revoked, false), do: "revoked", else: "key"
          {:push, {:text, Protocol.encode(Protocol.refused(reason))}, state}

        true ->
          {:push, {:text, Protocol.encode(Protocol.welcome(server.seen, "fake"))},
           %{state | hello?: true}}
      end
    end

    defp handle(%{"type" => "events", "events" => events}, %{hello?: true} = state) do
      last =
        Agent.get_and_update(state.agent, fn server ->
          fresh =
            for map <- events,
                {:ok, event} <- [Protocol.decode_event(map)],
                event.seq > server.seen,
                do: event

          server = %{
            server
            | events: Enum.reverse(fresh) ++ server.events,
              seen: Enum.max([server.seen | Enum.map(fresh, & &1.seq)])
          }

          {{server.seen, server.ack?}, server}
        end)

      case last do
        {seen, true} -> {:push, {:text, Protocol.encode(Protocol.ack(seen))}, state}
        {_seen, false} -> {:ok, state}
      end
    end

    defp handle(%{"type" => "boards"} = frame, state) do
      Agent.update(state.agent, &%{&1 | boards: frame})
      {:ok, state}
    end

    defp handle(%{"type" => "reply"} = frame, state) do
      Agent.update(state.agent, &%{&1 | replies: [frame | &1.replies]})
      {:ok, state}
    end

    defp handle(%{"type" => "leave"}, state) do
      Agent.update(state.agent, &Map.put(&1, :left?, true))
      {:ok, state}
    end

    defp handle(_frame, state), do: {:ok, state}

    def terminate(_reason, state) do
      me = self()
      Agent.update(state.agent, &%{&1 | sockets: List.delete(&1.sockets, me)})
      :ok
    catch
      :exit, _reason -> :ok
    end
  end
end
