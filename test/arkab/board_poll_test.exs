defmodule Arkab.BoardPollTest do
  @moduledoc """
  What a bridge board says about answered and missed polls: the answers it
  does not send are still counted, and the count reaches the server.
  """

  use ExUnit.Case, async: false

  alias Arkab.Bridge.{Board, Store}

  defmodule IdleDriver do
    def start_link(_opts), do: Agent.start_link(fn -> nil end)
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "arkab-poll-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    start_supervised!({Registry, keys: :unique, name: Arkab.Bridge.BoardRegistry})
    store = :"poll_store_#{System.unique_integer([:positive])}"
    start_supervised!({Store, path: Path.join(dir, "arkab.db"), name: store}, id: store)
    {:ok, _} = Store.add_server(store, %{url: "ws://a", key: "k", name: "a", owner?: true})

    pid =
      start_supervised!(
        {Board, id: "COM3#6310", port: "COM3", address: 6310, driver: IdleDriver, store: store}
      )

    %{pid: pid, store: store}
  end

  defp say(pid, event), do: send(pid, {:driver, "COM3#6310", event})

  # The board first: what it was told is still in its mailbox otherwise, and
  # the store is asked before anything reached it.
  defp polls(pid, store) do
    _ = :sys.get_state(pid)
    Store.sync(store)

    for %{"e" => %{"k" => "poll"} = e} <- Store.pending(store, 0, 1_000),
        do: {e["v"], e["n"]}
  end

  test "the answer that travels says how many answers it stands for", %{pid: pid, store: store} do
    for _ <- 1..60, do: say(pid, {:poll, :ok})
    say(pid, {:poll, :missed})
    # The first answer went at once, the other fifty-nine are owed.
    assert polls(pid, store) == [{"ok", nil}, {"ok", 59}, {"missed", nil}]
  end

  test "misses travel one by one, and the first answer after them is one answer", %{
    pid: pid,
    store: store
  } do
    say(pid, {:poll, :missed})
    say(pid, {:poll, :missed})
    say(pid, {:poll, :ok})
    say(pid, {:poll, :ok})
    say(pid, {:poll, :missed})

    assert polls(pid, store) ==
             [{"missed", nil}, {"missed", nil}, {"ok", nil}, {"ok", nil}, {"missed", nil}]
  end

  test "a resend does not count anything twice", %{pid: pid, store: store} do
    for _ <- 1..10, do: say(pid, {:poll, :ok})
    say(pid, :connected)
    :ok = Board.resend("COM3#6310")
    say(pid, {:poll, :missed})
    assert polls(pid, store) == [{"ok", nil}, {"ok", 9}, {"missed", nil}]
  end
end
