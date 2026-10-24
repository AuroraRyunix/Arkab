defmodule ArkabWeb.Pin.Throttle do
  @moduledoc """
  Wrong guesses at the remote PIN, counted per peer address in an ETS table
  that this process owns (it is there to keep the table alive and does
  nothing else). Five wrong guesses lock the address out for five minutes;
  a right one clears the count. The peer is the socket's address and never
  a header, so behind a reverse proxy every visitor shares the proxy's
  address and its lockout: a hall lock, not a per-person one.
  """

  use GenServer

  @table :arkab_pin_throttle
  @max_wrong 5
  @lockout 300

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, nil}
  end

  @doc """
  Takes one guess for `key` before the PIN is hashed: `:ok`, or
  `{:locked, seconds}`. Counted up front and one at a time through this
  process, because the hash takes a while and a count made after it let a
  burst of simultaneous guesses all walk past a lockout none of them had
  recorded yet. The fifth guess starts the lockout; a right one is
  `clear/1`ed afterwards. If the counter is not there to ask, nobody guesses.
  """
  @spec claim(term()) :: :ok | {:locked, pos_integer()}
  def claim(key) do
    GenServer.call(__MODULE__, {:claim, key})
  catch
    :exit, _reason -> {:locked, @lockout}
  end

  @impl true
  def handle_call({:claim, key}, _from, state) do
    {wrong, until} = lookup(key) || {0, nil}

    reply =
      cond do
        is_integer(until) and until > now() ->
          {:locked, until - now()}

        true ->
          wrong = if is_integer(until), do: 1, else: wrong + 1
          insert(key, {wrong, if(wrong >= @max_wrong, do: now() + @lockout)})
          :ok
      end

    {:reply, reply, state}
  end

  @doc "A right guess, or the lockout's end: the slate is clean."
  def clear(key) do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table, key)
    :ok
  end

  @doc "Every count, gone (tests)."
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  def lockout_seconds, do: @lockout

  defp lookup(key) do
    if :ets.whereis(@table) == :undefined do
      nil
    else
      case :ets.lookup(@table, key) do
        [{^key, wrong, until}] -> {wrong, until}
        [] -> nil
      end
    end
  end

  defp insert(key, {wrong, until}) do
    if :ets.whereis(@table) != :undefined, do: :ets.insert(@table, {key, wrong, until})
  end

  defp now, do: System.monotonic_time(:second)
end
