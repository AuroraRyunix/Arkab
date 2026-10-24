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

  @doc "Seconds left of the lockout for `key`, or 0."
  @spec locked_for(term()) :: non_neg_integer()
  def locked_for(key) do
    case lookup(key) do
      {_wrong, until} when is_integer(until) -> max(until - now(), 0)
      _ -> 0
    end
  end

  @doc "Counts a wrong guess; the fifth starts the lockout."
  def fail(key) do
    {wrong, until} = lookup(key) || {0, nil}
    expired? = is_integer(until) and until <= now()
    wrong = if expired?, do: 1, else: wrong + 1
    until = if wrong >= @max_wrong, do: now() + @lockout
    insert(key, {wrong, until})
    :ok
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
