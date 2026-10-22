defmodule Arkab.FakeServer.Socket do
  @moduledoc false
  @behaviour WebSock

  alias Arkab.Protocol

  def init(agent) do
    me = self()
    Agent.update(agent, &%{&1 | sockets: [me | &1.sockets]})
    {:ok, %{agent: agent, hello?: false}}
  end

  def handle_in({text, opcode: :text}, state) do
    Agent.update(state.agent, &%{&1 | frames: [text | &1.frames]})
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
