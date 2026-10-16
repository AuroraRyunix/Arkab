defmodule Arkab.Bridge.Board do
  @moduledoc """
  One board the bridge reads: its driver, and the owner that driver reports
  to. Alnasl's `BoardServer` is the same idea with a tracker in it; this one
  has a queue instead.

  Everything the driver delivers goes into the queue (`Arkab.Bridge.Store`)
  with the time it happened, in the order it came, except:

  - **raw bytes** never travel. They are the capture file's business, and
    the capture is written here, on the bridge, while recording is on;
  - **"answered"** (`{:poll, :ok}`) travels once a second, and always the
    first one after a miss. A loop answers sixty times a second; the
    server wants to know the line is alive and when a run of misses ended,
    not every heartbeat. Every miss travels: a run of them is what makes
    the tracker stop believing the clock.

  It also remembers the board as it stands - connected or not, what it said
  about itself, the position, the clock - for "send the whole board again"
  (`resend/1`): a server that has just come up, or a board process on it
  that has just restarted, starts from that.

  A driver that dies is started again after three seconds, as in Alnasl.
  """

  use GenServer, restart: :transient

  alias Arkab.Bridge.Store

  @poll_every_ms 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :id)))
  end

  def child_spec(opts),
    do: %{
      id: {__MODULE__, opts[:id]},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }

  def via(id), do: {:via, Registry, {Arkab.Bridge.BoardRegistry, id}}

  def whereis(id) do
    case Registry.lookup(Arkab.Bridge.BoardRegistry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Every board's name, sorted."
  def ids do
    Arkab.Bridge.BoardRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  @doc "Queues the board as it stands, whole."
  def resend(id) do
    case whereis(id) do
      nil -> {:error, :no_such_board}
      pid -> GenServer.call(pid, :resend)
    end
  end

  @doc "`%{id, port, address, connected?, info, position?}` for the status page and the server."
  def status(pid), do: GenServer.call(pid, :status)

  # --- the process -------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      id: Keyword.fetch!(opts, :id),
      port: Keyword.fetch!(opts, :port),
      address: Keyword.get(opts, :address),
      driver: Keyword.fetch!(opts, :driver),
      driver_opts: Keyword.get(opts, :driver_opts, []),
      ports: Keyword.get(opts, :ports, Arkab.Bridge.Ports),
      store: Keyword.get(opts, :store, Store),
      recorder: Keyword.get(opts, :recorder, Arkab.Bridge.Recorder),
      pid: nil,
      connected?: false,
      info: %{},
      position: nil,
      clock: nil,
      # The last {t, speed, next} of a played board: what "now" is for it.
      played: nil,
      poll: nil
    }

    {:ok, start_driver(state)}
  end

  defp start_driver(state) do
    opts =
      [owner: self(), id: state.id, port: state.port, address: state.address] ++
        state.driver_opts

    case state.driver.start_link(opts) do
      {:ok, pid} ->
        %{state | pid: pid}

      _error ->
        Process.send_after(self(), :restart_driver, 3_000)
        state
    end
  rescue
    _error ->
      Process.send_after(self(), :restart_driver, 3_000)
      state
  end

  @impl true
  def handle_info({:driver, _id, {:at, t, speed, next, event}}, state) do
    state = %{state | played: {t, speed, next}}
    {:noreply, take(state, event, t, {speed, next})}
  end

  def handle_info({:driver, _id, event}, state),
    do: {:noreply, take(state, event, System.os_time(:millisecond), nil)}

  def handle_info(:restart_driver, %{pid: nil} = state), do: {:noreply, start_driver(state)}
  def handle_info(:restart_driver, state), do: {:noreply, state}

  def handle_info({:EXIT, pid, _reason}, %{pid: pid} = state) do
    Process.send_after(self(), :restart_driver, 3_000)
    {:noreply, %{state | pid: nil}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_call(:resend, _from, state) do
    {t, at} =
      case state.played do
        {t, speed, next} -> {t, {speed, next}}
        nil -> {System.os_time(:millisecond), nil}
      end

    events =
      [if(state.connected?, do: :connected, else: :disconnected)] ++
        if(state.info == %{}, do: [], else: [{:info, state.info}]) ++
        if(state.position, do: [{:position, state.position}], else: []) ++
        if(state.clock, do: [{:clock, state.clock}], else: [])

    for event <- events, do: Store.append(state.store, state.id, t, at, event)
    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       id: state.id,
       port: state.port,
       address: state.address,
       connected?: state.connected?,
       info: state.info,
       position?: state.position != nil
     }, state}
  end

  @impl true
  def terminate(_reason, %{pid: pid}) when is_pid(pid) do
    Process.exit(pid, :shutdown)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # --- what the driver said ----------------------------------------------------

  defp take(state, {:raw, _direction, _bytes} = event, _t, _at) do
    record(state, event)
    state
  end

  defp take(state, {:poll, :ok} = event, t, at) do
    now = System.monotonic_time(:millisecond)

    case state.poll do
      {:ok, last} when now - last < @poll_every_ms ->
        state

      _missed_or_first ->
        queue(state, t, at, event)
        %{state | poll: {:ok, now}}
    end
  end

  defp take(state, {:poll, :missed} = event, t, at) do
    queue(state, t, at, event)
    %{state | poll: :missed}
  end

  defp take(state, event, t, at) do
    record(state, capture_event(event))
    queue(state, t, at, event)
    remember(state, event)
  end

  defp remember(state, {:position, board}), do: %{state | position: board}
  defp remember(state, {:clock, reading}), do: %{state | clock: reading}
  defp remember(state, :connected), do: notify(%{state | connected?: true})
  defp remember(state, :disconnected), do: notify(%{state | connected?: false})

  # A clock switched off: its last reading is not to be believed, nor resent.
  defp remember(state, {:info, %{clock: false} = info}),
    do: %{state | clock: nil, info: Map.merge(state.info, info)}

  defp remember(state, {:info, info}) do
    # A single-board port that turns out to be a loop: the ports decide.
    case info do
      %{loop: [_, _ | _] = addresses} ->
        send(whereis_ports(state), {:loop, state.port, addresses})

      _other ->
        :ok
    end

    info = Map.drop(info, [:loop, :error])
    changed? = Map.take(state.info, Map.keys(info)) != info
    state = %{state | info: Map.merge(state.info, info)}
    if changed?, do: notify(state), else: state
  end

  defp remember(state, _event), do: state

  defp whereis_ports(%{ports: ports}) when is_pid(ports), do: ports
  defp whereis_ports(%{ports: name}), do: Process.whereis(name) || self()

  # The servers' picture of the bridge (which boards, which serials) is
  # sent again when it changes.
  defp notify(state) do
    case whereis_ports(state) do
      pid when pid == self() -> :ok
      pid -> send(pid, :boards_changed)
    end

    state
  end

  defp queue(state, t, at, event), do: Store.append(state.store, state.id, t, at, event)

  defp capture_event(:connected), do: {:status, :connected}
  defp capture_event(:disconnected), do: {:status, :disconnected}
  defp capture_event({:info, %{clock: false}}), do: {:clock, :off}
  defp capture_event(event), do: event

  defp record(state, event) do
    if Arkab.Bridge.recording?() do
      Arkab.Recorder.record(state.recorder, state.id, event)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end
end
