defmodule Arkab.BridgeTest do
  @moduledoc """
  The bridge end to end, against stand-in servers on real sockets: boards
  played back and on an emulated serial line, two servers with one of them
  down, a line cut, the bridge restarted, commands down, and Remove from
  either side.
  """

  use ExUnit.Case, async: false

  alias Arkab.{Board, Bridge, FakeServer}
  alias Arkab.Bridge.Store
  alias Arkab.Dgt.Emulator
  alias Arkab.Transport.Fake

  @moves [
    "rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR",
    "rnbqkbnrpppppppp....................P...........PPPP.PPPRNBQKBNR",
    "rnbqkbnrpppp.ppp............p.......P...........PPPP.PPPRNBQKBNR",
    "rnbqkbnrpppp.ppp............p.......P........N..PPPP.PPPRNBQKB.R",
    "r.bqkbnrpppp.ppp..n.........p.......P........N..PPPP.PPPRNBQKB.R",
    "r.bqkbnrpppp.ppp..n.........p......BP........N..PPPP.PPPRNBQK..R"
  ]

  setup do
    dir = Path.join(System.tmp_dir!(), "arkab-bridge-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, capture: capture(dir)}
  end

  # A game as a capture file: a position every 400 ms, clock readings between.
  defp capture(dir) do
    path = Path.join(dir, "game.jsonl")

    lines =
      ([%{"k" => "st", "v" => "connected", "t" => 1_000}] ++
         for {text, i} <- Enum.with_index(@moves) do
           [
             %{"k" => "pos", "b" => text, "t" => 1_000 + i * 400},
             %{
               "k" => "clk",
               "w" => 60_000 - i * 400,
               "b" => 60_000,
               "r" => "white",
               "t" => 1_200 + i * 400
             }
           ]
         end)
      |> List.flatten()

    File.write!(path, Enum.map_join(lines, "\n", &Jason.encode!/1))
    path
  end

  defp start_bridge(dir, sources) do
    start_supervised!({Bridge, data_dir: dir, name: "hall", sources: sources}, id: Bridge)
  end

  defp eventually(fun, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait(fun, deadline)
  end

  defp wait(fun, deadline) do
    case fun.() do
      falsy when falsy in [nil, false] ->
        if System.monotonic_time(:millisecond) > deadline do
          flunk("it did not happen in time")
        else
          Process.sleep(20)
          wait(fun, deadline)
        end

      value ->
        value
    end
  end

  defp positions(server, id \\ "game") do
    for %{id: ^id, event: {:position, board}} <- FakeServer.events(server),
        do: Board.to_text(board)
  end

  defp replay(capture, speed \\ 4),
    do: %{"replay" => capture, "name" => "game", "speed" => speed}

  test "two servers, one of them down: the other gets everything, the queue keeps the rest",
       %{dir: dir, capture: capture} do
    a = FakeServer.start(codes: ["A"])
    b = FakeServer.start(codes: ["B"])
    start_bridge(dir, [])
    {:ok, _} = Bridge.join(FakeServer.link(a, "A"))
    {:ok, _} = Bridge.join(FakeServer.link(b, "B"))
    eventually(fn -> FakeServer.get(a, :sockets) != [] and FakeServer.get(b, :sockets) != [] end)

    FakeServer.down(b)
    :ok = Arkab.Bridge.Ports.add(replay(capture))

    eventually(fn -> positions(a) == @moves end)
    seqs = FakeServer.seqs(a)
    assert seqs == Enum.to_list(hd(seqs)..List.last(seqs))
    # Kept for the one that is down; nothing held up for the one that is up.
    assert Store.waiting() == length(seqs)

    FakeServer.up(b)
    eventually(fn -> positions(b) == @moves end, 40_000)
    eventually(fn -> Store.waiting() == 0 end)
    assert FakeServer.seqs(b) == FakeServer.seqs(a)
  end

  test "a line cut mid-game and a bridge restarted: nothing lost, nothing twice",
       %{dir: dir, capture: capture} do
    a = FakeServer.start(codes: ["A"])
    start_bridge(dir, [])
    {:ok, _} = Bridge.join(FakeServer.link(a, "A"))
    eventually(fn -> FakeServer.get(a, :sockets) != [] end)

    # The server takes events and never says so: all of it stays queued.
    FakeServer.set(a, :ack?, false)
    :ok = Arkab.Bridge.Ports.add(replay(capture, 2))
    eventually(fn -> length(positions(a)) >= 2 end)

    # The line goes mid-game; the game goes on into the queue.
    FakeServer.down(a)
    Process.sleep(500)
    waiting = Store.waiting()
    assert waiting > 0

    # The bridge restarts with all of it unacknowledged; the replay begins
    # again from its start, as a board would be read again from what it shows.
    stop_supervised!(Bridge)
    start_bridge(dir, [])
    assert Store.waiting() >= waiting

    FakeServer.set(a, :ack?, true)
    FakeServer.up(a)
    eventually(fn -> Store.waiting() == 0 end, 30_000)

    seqs = FakeServer.seqs(a)
    assert seqs == Enum.uniq(seqs)
    assert seqs == Enum.sort(seqs)
    assert seqs == Enum.to_list(hd(seqs)..List.last(seqs))
  end

  test "an old and a new board on one adapter are two rows, before and after a rescan", %{
    dir: dir
  } do
    boards = [
      Emulator.new(address: 6310, serial: "06310", version: "1.9", bus?: true),
      Emulator.new(address: 12_799, serial: "00730", version: "4.0", bus?: true)
    ]

    start_supervised!({Fake, port: "FAKE-BR2", device: {Emulator, boards}})
    start_bridge(dir, [%{"port" => "FAKE-BR2"}])

    ids = fn -> Bridge.status().boards |> Enum.map(& &1.id) |> Enum.sort() end
    both = ["FAKE-BR2#12799", "FAKE-BR2#6310"]

    eventually(fn -> ids.() == both end, 15_000)

    # Read again: the loop is found again, nothing is left of the first
    # reading and no third row (the single-board one) turns up.
    :ok = Arkab.Bridge.Ports.command(%{"cmd" => "rescan"}, true)
    eventually(fn -> ids.() == both end, 15_000)
    eventually(fn -> Enum.all?(Bridge.status().boards, & &1.connected?) end, 15_000)
    assert ids.() == both

    old = Enum.find(Bridge.status().boards, &(&1.id == "FAKE-BR2#6310"))
    assert old.info.serial == "06310"
    assert old.address == 6310
  end

  test "an emulated board on a serial line: read, named, sent, and sent again on request",
       %{dir: dir} do
    start_supervised!({Fake, port: "FAKE-BR1", device: {Emulator, Emulator.new()}})
    a = FakeServer.start(codes: ["A"])
    start_bridge(dir, [%{"port" => "FAKE-BR1"}])
    {:ok, _} = Bridge.join(FakeServer.link(a, "A"))

    start = Board.to_text(Board.start())
    eventually(fn -> start in positions(a, "FAKE-BR1") end, 10_000)

    eventually(fn ->
      match?(
        %{"boards" => [%{"id" => "FAKE-BR1", "serial" => "12345", "connected" => true}]},
        FakeServer.get(a, :boards)
      )
    end)

    {:ok, after_e4} = Board.from_text(Enum.at(@moves, 1))
    Fake.update("FAKE-BR1", &Emulator.set_board(&1, after_e4))
    eventually(fn -> Enum.at(@moves, 1) in positions(a, "FAKE-BR1") end)

    count = length(positions(a, "FAKE-BR1"))
    FakeServer.push(a, Arkab.Protocol.command("c1", "resend", board: "FAKE-BR1"))
    eventually(fn -> Enum.any?(FakeServer.get(a, :replies), &(&1["id"] == "c1" and &1["ok"])) end)
    eventually(fn -> length(positions(a, "FAKE-BR1")) == count + 1 end)
    assert List.last(positions(a, "FAKE-BR1")) == Enum.at(@moves, 1)

    status = Bridge.status()
    assert [%{port: "FAKE-BR1", read?: true} | _] = status.ports
    assert [%{id: "FAKE-BR1", connected?: true}] = status.boards
  end

  test "only an owner may make the bridge forget", %{dir: dir} do
    a = FakeServer.start(codes: ["A"], owner: false)
    start_bridge(dir, [%{"port" => "FAKE-NOBODY"}])
    {:ok, _} = Bridge.join(FakeServer.link(a, "A"))
    eventually(fn -> FakeServer.get(a, :sockets) != [] end)

    FakeServer.push(a, Arkab.Protocol.command("c2", "forget_port", port: "FAKE-NOBODY"))

    eventually(fn ->
      Enum.any?(FakeServer.get(a, :replies), &(&1["id"] == "c2" and &1["error"] == "not_owner"))
    end)

    assert Store.get("ports") == [%{"port" => "FAKE-NOBODY"}]
  end

  test "Remove on the bridge tells the server; Remove on the server ends it here", %{dir: dir} do
    a = FakeServer.start(codes: ["A"])
    b = FakeServer.start(codes: ["B"])
    start_bridge(dir, [])
    {:ok, id_a} = Bridge.join(FakeServer.link(a, "A"))
    {:ok, _id_b} = Bridge.join(FakeServer.link(b, "B"))
    eventually(fn -> FakeServer.get(a, :sockets) != [] and FakeServer.get(b, :sockets) != [] end)
    eventually(fn -> Enum.all?(Bridge.status().servers, & &1.up?) end)

    Bridge.remove(id_a)
    eventually(fn -> FakeServer.get(a, :left?) == true end)
    assert [%{name: "fake"}] = Store.servers()

    FakeServer.push(b, Arkab.Protocol.leave())
    eventually(fn -> Store.servers() == [] end)
  end

  test "a key the server revoked while the bridge was away ends it here too", %{dir: dir} do
    a = FakeServer.start(codes: ["A"])
    start_bridge(dir, [])
    {:ok, _} = Bridge.join(FakeServer.link(a, "A"))
    eventually(fn -> FakeServer.get(a, :sockets) != [] end)

    FakeServer.down(a)
    FakeServer.set(a, :revoked, true)
    FakeServer.up(a)
    eventually(fn -> Store.servers() == [] end, 10_000)
  end
end
