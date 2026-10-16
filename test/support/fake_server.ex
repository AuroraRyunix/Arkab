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
end
