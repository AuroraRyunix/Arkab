defmodule Arkab.Bridge.Link do
  @moduledoc """
  The line to one server: one outgoing WebSocket (`Mint.WebSocket`), kept
  up, and the queue pushed through it.

  1. Connect, say `hello` with the key. The server says `welcome` and the
     highest number it holds (`seen`) - which can be more than it
     acknowledged, when the line went before the ack came back: those are
     taken as acknowledged, not sent twice.
  2. Send what is queued after that, oldest first, in frames of up to 200,
     never more than `@window` unacknowledged. Each `ack` moves this
     server's place in the queue (`Arkab.Bridge.Store.ack/2`), and what
     every server has is deleted there.
  3. Commands come down the same socket and go to `Arkab.Bridge.Ports`,
     one at a time; each gets a `reply`.
  4. The line goes: try again after a second, then two, up to thirty.
     Nothing is lost meanwhile - it is in the file - and nothing is held
     up for the other servers.

  A ping every 25 seconds keeps a tunnel from deciding the line is idle,
  and a line that has said nothing for 75 is taken for dead.

  Removed on the server (`leave`, or a `refused` that says `revoked`), the
  server is removed here too. Any other refusal is said on the status page
  and tried again in a minute: a key the server does not know today may be
  a server restored from yesterday's backup tomorrow.
  """

  use GenServer, restart: :transient

  require Logger

  alias Arkab.Bridge.{Ports, Store}
  alias Arkab.Protocol

  @window 1_000
  @batch 200
  @ping_ms 25_000
  @dead_ms 75_000
  @max_backoff_ms 30_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def child_spec(opts),
    do: %{
      id: {__MODULE__, opts[:server_id]},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }

  def whereis(server_id) do
    case Registry.lookup(Arkab.Bridge.LinkRegistry, server_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "`%{up?, error, acked, sent}`."
  def info(pid) do
    GenServer.call(pid, :info)
  catch
    :exit, _reason -> %{up?: false, error: nil}
  end

  @doc "Tells the server this bridge is leaving it, if the line is up."
  def leave(pid) do
    GenServer.call(pid, :leave)
  catch
    :exit, _reason -> :ok
  end

  # --- the process -------------------------------------------------------------

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :server_id)
    {:ok, _} = Registry.register(Arkab.Bridge.LinkRegistry, id, nil)
    {:ok, _} = Registry.register(Arkab.Bridge.Listeners, :queued, nil)
    {:ok, _} = Registry.register(Arkab.Bridge.Listeners, :boards, nil)
    send(self(), :connect)

    {:ok,
     %{
       id: id,
       server: nil,
       conn: nil,
       ref: nil,
       websocket: nil,
       upgrade: %{},
       up?: false,
       acked: 0,
       sent: 0,
       error: nil,
       backoff: 1_000,
       heard: now(),
       boards_timer: nil
     }}
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, %{up?: state.up?, error: state.error, acked: state.acked, sent: state.sent}, state}
  end

  def handle_call(:leave, _from, %{up?: true} = state) do
    state = push(state, Protocol.leave())
    {:reply, :ok, close(state)}
  end

  def handle_call(:leave, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info(:connect, %{conn: nil} = state) do
    case Store.server(state.id) do
      nil -> {:stop, :normal, state}
      server -> {:noreply, connect(%{state | server: server, acked: server.acked})}
    end
  end

  def handle_info(:connect, state), do: {:noreply, state}

  def handle_info(:queued, %{up?: true} = state), do: {:noreply, pump(state)}
  def handle_info(:queued, state), do: {:noreply, state}

  # A few changes in a row are one message.
  def handle_info(:boards_changed, %{up?: true, boards_timer: nil} = state),
    do: {:noreply, %{state | boards_timer: Process.send_after(self(), :send_boards, 200)}}

  def handle_info(:boards_changed, state), do: {:noreply, state}

  def handle_info(:send_boards, state),
    do: {:noreply, %{send_boards(state) | boards_timer: nil}}

  def handle_info(:ping, %{up?: true} = state) do
    if now() - state.heard > @dead_ms do
      {:noreply, lost(state, :silent)}
    else
      Process.send_after(self(), :ping, @ping_ms)
      {:noreply, send_frame(state, {:ping, ""})}
    end
  end

  def handle_info(:ping, state), do: {:noreply, state}

  def handle_info(:stop, state), do: {:stop, :normal, state}

  def handle_info(message, %{conn: conn} = state) when conn != nil do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        {:noreply, Enum.reduce(responses, %{state | conn: conn}, &response/2) |> after_frames()}

      {:error, conn, reason, _responses} ->
        {:noreply, lost(%{state | conn: conn}, reason)}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.conn, do: Mint.HTTP.close(state.conn)
    :ok
  end

  # --- the socket --------------------------------------------------------------

  defp connect(state) do
    uri = URI.parse(state.server.url)
    http = if uri.scheme == "wss", do: :https, else: :http
    ws = if uri.scheme == "wss", do: :wss, else: :ws

    with {:ok, conn} <-
           Mint.HTTP.connect(http, uri.host, uri.port,
             protocols: [:http1],
             transport_opts: [timeout: 10_000]
           ),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws, conn, uri.path || "/", []) do
      %{state | conn: conn, ref: ref, upgrade: %{}, heard: now()}
    else
      {:error, reason} -> retry(state, reason)
      {:error, conn, reason} -> retry(%{state | conn: conn}, reason)
    end
  end

  defp response({:status, ref, status}, %{ref: ref} = state),
    do: %{state | upgrade: Map.put(state.upgrade, :status, status)}

  defp response({:headers, ref, headers}, %{ref: ref} = state),
    do: %{state | upgrade: Map.put(state.upgrade, :headers, headers)}

  defp response({:done, ref}, %{ref: ref, websocket: nil} = state) do
    case Mint.WebSocket.new(
           state.conn,
           ref,
           state.upgrade[:status],
           state.upgrade[:headers] || []
         ) do
      {:ok, conn, websocket} ->
        state = %{state | conn: conn, websocket: websocket}

        push(
          state,
          Protocol.hello(
            Arkab.Bridge.id(),
            state.server.key,
            Arkab.Bridge.name(),
            Arkab.Bridge.software()
          )
        )

      {:error, conn, reason} ->
        Map.put(%{state | conn: conn}, :lost, {:upgrade, reason})
    end
  end

  defp response({:data, ref, data}, %{ref: ref, websocket: websocket} = state)
       when websocket != nil do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        Enum.reduce(frames, %{state | websocket: websocket, heard: now()}, &frame/2)

      {:error, websocket, reason} ->
        Map.put(%{state | websocket: websocket}, :lost, reason)
    end
  end

  defp response(_other, state), do: state

  # What a frame decided (the line is gone, the server is gone) is acted on
  # once all of them are read.
  defp after_frames(%{removed: true} = state) do
    Logger.info("arkab: #{state.server.url} removed this bridge")
    Store.remove_server(state.id)
    send(self(), :stop)
    close(Map.delete(state, :removed)) |> Map.put(:stopping, true)
  end

  defp after_frames(%{lost: reason} = state), do: lost(Map.delete(state, :lost), reason)
  defp after_frames(state), do: state

  defp frame({:text, text}, state) do
    case Protocol.decode(text) do
      {:ok, message} -> message(message, state)
      {:error, _bad} -> state
    end
  end

  defp frame({:ping, data}, state), do: send_frame(state, {:pong, data})
  defp frame({:close, _code, _reason}, state), do: Map.put(state, :lost, :closed)
  defp frame(_other, state), do: state

  # --- the conversation --------------------------------------------------------

  defp message(%{"type" => "welcome", "seen" => seen}, state) when is_integer(seen) do
    acked = max(state.acked, seen)
    if acked > state.server.acked, do: Store.ack(state.id, acked)
    Process.send_after(self(), :ping, @ping_ms)

    %{state | up?: true, error: nil, backoff: 1_000, acked: acked, sent: acked}
    |> send_boards()
    |> pump()
  end

  defp message(%{"type" => "ack", "seq" => seq}, state) when is_integer(seq) do
    if seq > state.acked do
      Store.ack(state.id, seq)
      pump(%{state | acked: seq, sent: max(state.sent, seq)})
    else
      state
    end
  end

  defp message(%{"type" => "command", "id" => id} = frame, state) do
    reply =
      try do
        Ports.command(frame, state.server.owner?)
      catch
        :exit, _reason -> {:error, :busy}
      end

    push(state, Protocol.reply(id, reply))
  end

  defp message(%{"type" => "leave"}, state), do: Map.put(state, :removed, true)

  defp message(%{"type" => "refused", "reason" => "revoked"}, state),
    do: Map.put(state, :removed, true)

  defp message(%{"type" => "refused", "reason" => reason}, state),
    do: Map.put(%{state | error: "refused: #{reason}", backoff: 60_000}, :lost, :refused)

  defp message(_other, state), do: state

  # Everything queued after what was sent, as long as the window allows.
  defp pump(%{up?: true} = state) do
    if state.sent - state.acked >= @window do
      state
    else
      case Store.pending(state.sent, @batch) do
        [] ->
          state

        events ->
          state = push(state, Protocol.events(events))
          if state.up?, do: pump(%{state | sent: List.last(events)["s"]}), else: state
      end
    end
  end

  defp pump(state), do: state

  defp send_boards(%{up?: true} = state) do
    status =
      try do
        Ports.status()
      catch
        :exit, _reason -> %{ports: [], boards: [], recording?: false}
      end

    push(state, %{
      "type" => "boards",
      "boards" =>
        for(
          board <- status.boards,
          do: %{
            "id" => board.id,
            "port" => board.port,
            "address" => board.address,
            "connected" => board.connected?,
            "serial" => board.info[:serial]
          }
        ),
      "ports" =>
        for(
          port <- status.ports,
          do: %{"port" => port.port, "description" => port.description, "read" => port.read?}
        ),
      "recording" => status.recording?
    })
  end

  defp send_boards(state), do: state

  defp push(state, frame), do: send_frame(state, {:text, Protocol.encode(frame)})

  defp send_frame(%{websocket: nil} = state, _frame), do: state

  defp send_frame(state, frame) do
    # Two calls, two kinds of error: encode hands back the websocket, the
    # request body hands back the connection. (Not told apart by matching on
    # %Mint.WebSocket{}: that type is opaque.)
    case Mint.WebSocket.encode(state.websocket, frame) do
      {:ok, websocket, data} ->
        case Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
          {:ok, conn} -> %{state | websocket: websocket, conn: conn}
          {:error, conn, reason} -> lost(%{state | conn: conn}, reason)
        end

      {:error, websocket, reason} ->
        lost(%{state | websocket: websocket}, reason)
    end
  end

  # --- losing it ---------------------------------------------------------------

  defp close(state) do
    if state.conn, do: Mint.HTTP.close(state.conn)
    %{state | conn: nil, websocket: nil, ref: nil, up?: false}
  end

  defp lost(%{stopping: true} = state, _reason), do: state

  defp lost(state, reason) do
    state = close(state)
    retry(state, reason)
  end

  defp retry(state, reason) do
    state = close(state)
    error = if reason == :refused, do: state.error, else: describe(reason)
    Process.send_after(self(), :connect, state.backoff)
    next = if state.backoff >= 60_000, do: 1_000, else: min(state.backoff * 2, @max_backoff_ms)
    %{state | error: error, backoff: next}
  end

  defp describe(%{reason: reason}), do: describe(reason)
  defp describe(:econnrefused), do: "nobody answers at that address"
  defp describe(:nxdomain), do: "that address does not exist"
  defp describe(:timeout), do: "no answer in time"
  defp describe(:closed), do: "the server closed the line"
  defp describe(:silent), do: "the server stopped answering"
  defp describe(other), do: inspect(other)

  defp now, do: System.monotonic_time(:millisecond)
end
