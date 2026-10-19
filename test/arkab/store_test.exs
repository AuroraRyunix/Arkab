defmodule Arkab.StoreTest do
  @moduledoc """
  The queue: numbered in order, a place per server, deleted only when every
  server has it, and all of it still there after a restart.
  """

  use ExUnit.Case, async: true

  alias Arkab.Board
  alias Arkab.Bridge.Store

  setup do
    dir = Path.join(System.tmp_dir!(), "arkab-store-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{path: Path.join(dir, "arkab.db")}
  end

  defp start(path) do
    name = :"store_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Store, path: path, name: name}, id: name)
    {name, pid}
  end

  defp join(store, url) do
    {:ok, id} = Store.add_server(store, %{url: url, key: "k", name: url, owner?: true})
    id
  end

  test "a bridge joined to nobody keeps nothing", %{path: path} do
    {store, _pid} = start(path)
    Store.append(store, "COM3", 1, nil, {:position, Board.start()})
    Store.sync(store)
    assert Store.waiting(store) == 0
    assert Store.last_seq(store) == 0
  end

  test "events are numbered in the order they came, with their time", %{path: path} do
    {store, _pid} = start(path)
    join(store, "ws://a")

    Store.append(store, "COM3", 100, nil, :connected)
    Store.append(store, "COM3#5", 101, nil, {:position, Board.start()})

    Store.append(
      store,
      "COM3",
      102,
      {20, 140},
      {:clock, %{white_ms: 1, black_ms: 2, running: :white}}
    )

    # Raw bytes are the capture file's, not the queue's.
    Store.append(store, "COM3", 103, nil, {:raw, :rx, <<1, 2>>})
    Store.sync(store)

    events = Store.pending(store, 0, 10)
    assert Enum.map(events, & &1["s"]) == [1, 2, 3, 4]
    assert Enum.map(events, & &1["t"]) == [100, 101, 102, 103]
    assert Enum.map(events, & &1["id"]) == ["COM3", "COM3#5", "COM3", "COM3"]
    assert Enum.at(events, 2)["at"] == [20, 140]
    refute Map.has_key?(hd(events), "at")
    assert Store.pending(store, 2, 1) |> Enum.map(& &1["s"]) == [3]
  end

  test "an event goes when every server has it, and not before", %{path: path} do
    {store, _pid} = start(path)
    a = join(store, "ws://a")
    b = join(store, "ws://b")

    for t <- 1..5, do: Store.append(store, "COM3", t, nil, {:poll, :missed})
    Store.sync(store)
    assert Store.waiting(store) == 5

    # One server far ahead, the other down: the down one holds its rows.
    Store.ack(store, a, 5)
    assert Store.waiting(store) == 5
    assert Store.pending(store, 0, 10) |> length() == 5

    Store.ack(store, b, 3)
    assert Store.pending(store, 0, 10) |> Enum.map(& &1["s"]) == [4, 5]

    # An ack that comes late changes nothing.
    Store.ack(store, b, 2)
    assert Enum.find(Store.servers(store), &(&1.id == b)).acked == 3

    Store.ack(store, b, 5)
    assert Store.waiting(store) == 0
  end

  test "a server that joins later starts at the newest event", %{path: path} do
    {store, _pid} = start(path)
    a = join(store, "ws://a")
    for t <- 1..3, do: Store.append(store, "COM3", t, nil, :connected)
    Store.sync(store)

    b = join(store, "ws://b")
    assert Enum.find(Store.servers(store), &(&1.id == b)).acked == 3
    # It does not hold the first server's rows hostage either.
    Store.ack(store, a, 3)
    assert Store.waiting(store) == 0
  end

  test "joining the same server again changes the key and keeps the place", %{path: path} do
    {store, _pid} = start(path)
    a = join(store, "ws://a")
    Store.append(store, "COM3", 1, nil, :connected)
    Store.sync(store)

    {:ok, again} = Store.add_server(store, %{url: "ws://a", key: "new", name: "a", owner?: false})
    assert again == a
    assert [%{key: "new", acked: 0, owner?: false}] = Store.servers(store)
  end

  test "removing the last server empties the queue", %{path: path} do
    {store, _pid} = start(path)
    a = join(store, "ws://a")
    Store.append(store, "COM3", 1, nil, :connected)
    Store.sync(store)
    Store.remove_server(store, a)
    assert Store.waiting(store) == 0
  end

  test "everything survives a restart, and no number is given out twice", %{path: path} do
    {store, _pid} = start(path)
    a = join(store, "ws://a")
    for t <- 1..4, do: Store.append(store, "COM3", t, nil, {:position, Board.start()})
    Store.ack(store, a, 2)
    # Stopped with rows in its mailbox: they are written on the way out.
    Store.append(store, "COM3", 5, nil, :disconnected)
    stop_supervised!(store)

    {store, _pid} = start(path)
    assert [%{id: ^a, acked: 2}] = Store.servers(store)
    assert Store.pending(store, 2, 10) |> Enum.map(& &1["s"]) == [3, 4, 5]

    Store.ack(store, a, 5)
    assert Store.waiting(store) == 0
    Store.append(store, "COM3", 6, nil, :connected)
    Store.sync(store)
    assert Store.pending(store, 5, 10) |> Enum.map(& &1["s"]) == [6]
  end

  describe "when the queue cannot be kept" do
    import ExUnit.CaptureLog

    defp start_capped(path, opts) do
      name = :"store_#{System.unique_integer([:positive])}"
      pid = start_supervised!({Store, [path: path, name: name] ++ opts}, id: name)
      {name, pid}
    end

    defp clock(store, t),
      do:
        Store.append(
          store,
          "COM3",
          t,
          nil,
          {:clock, %{white_ms: t, black_ms: t, running: :white}}
        )

    defp kinds(store), do: store |> Store.pending(0, 1_000) |> Enum.map(& &1["e"]["k"])

    test "a server that never comes back does not fill the disk: clocks go first", %{path: path} do
      {store, _pid} = start_capped(path, soft_cap: 20, hard_cap: 100)
      join(store, "ws://gone")

      log =
        capture_log(fn ->
          for t <- 1..10, do: Store.append(store, "COM3", t, nil, {:position, Board.start()})
          for t <- 11..60, do: clock(store, t)
          Store.sync(store)
        end)

      kinds = kinds(store)
      assert Enum.count(kinds, &(&1 == "pos")) == 10
      assert length(kinds) <= 21
      assert Store.waiting(store) == length(kinds)
      assert %{dropped: dropped, error: nil} = Store.health(store)
      assert dropped >= 29
      assert log =~ "thrown away"
      # The newest clock reading is the one that stays.
      assert store |> Store.pending(0, 1_000) |> List.last() |> Map.fetch!("t") == 60
    end

    test "only past the hard cap do positions go, the oldest first", %{path: path} do
      {store, _pid} = start_capped(path, soft_cap: 5, hard_cap: 8)
      join(store, "ws://gone")

      capture_log(fn ->
        for t <- 1..30, do: Store.append(store, "COM3", t, nil, {:position, Board.start()})
        Store.sync(store)
      end)

      times = store |> Store.pending(0, 1_000) |> Enum.map(& &1["t"])
      assert length(times) <= 9
      assert List.last(times) == 30
      refute 1 in times
      assert Store.health(store).dropped >= 21
    end

    test "a write the disk refuses is counted and shown, and the store lives", %{path: path} do
      {store, pid} = start_capped(path, [])
      join(store, "ws://a")
      Store.append(store, "COM3", 1, nil, :connected)
      Store.sync(store)

      # Take the table away under it: every insert now fails.
      {:ok, other} = Exqlite.Sqlite3.open(path)
      :ok = Exqlite.Sqlite3.execute(other, "DROP TABLE events")
      Exqlite.Sqlite3.close(other)

      log =
        capture_log(fn ->
          Store.append(store, "COM3", 2, nil, :connected)
          Store.append(store, "COM3", 3, nil, :disconnected)
          Store.sync(store)
        end)

      assert Process.alive?(pid)
      assert %{dropped: dropped, error: error} = Store.health(store)
      assert dropped >= 1
      assert is_binary(error)
      assert log =~ "the write failed"
    end

    test "a file that is not a database is moved aside and the bridge starts fresh", %{path: path} do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, String.duplicate("this is not sqlite ", 500))

      log =
        capture_log(fn ->
          {store, _pid} = start(path)
          assert Store.servers(store) == []
          join(store, "ws://a")
          Store.append(store, "COM3", 1, nil, :connected)
          Store.sync(store)
          assert Store.waiting(store) == 1
        end)

      assert log =~ "moved to"
      dir = Path.dirname(path)
      assert [aside] = dir |> File.ls!() |> Enum.filter(&String.contains?(&1, ".corrupt-"))
      assert File.read!(Path.join(dir, aside)) =~ "this is not sqlite"
    end
  end
end
