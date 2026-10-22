defmodule Arkab.ContractTest do
  @moduledoc """
  The bridge-protocol contract (`priv/contracts/bridge-protocol-v1/`) is
  what Alnasl vendors and tests against. Here it is held to the code: the
  frames the bridge really writes fit it, the frames it describes from the
  server are the ones the bridge really reads, and the bytes it pins on the
  serial line are the bytes the driver really writes. A change to any of
  these that leaves the contract behind turns this file red, which is the
  point; Alnasl's copy then turns its drift check red, which is the rest of it.
  """

  use ExUnit.Case, async: false

  alias Arkab.{Board, Bridge, Contract, FakeServer, Protocol}
  alias Arkab.Bridge.Join
  alias Arkab.Dgt.Emulator
  alias Arkab.Driver.DgtSerial
  alias Arkab.Transport.Fake

  @to_bridge ~w(welcome refused ack command leave)

  # --- the directory -------------------------------------------------------------

  describe "the directory" do
    test "index.json lists every file in it, sorted" do
      assert Contract.read!("index.json") == %{
               "contract" => "bridge-protocol",
               "version" => 1,
               "files" => Contract.files()
             }
    end

    test "every schema is draft-07 with an $id, a title and a description, and has an example" do
      examples = for {schema, _file, _data} <- Contract.examples(), uniq: true, do: schema

      for file <- Contract.files(), String.ends_with?(file, ".schema.json") do
        schema = Contract.read!(file)
        assert schema["$schema"] == "http://json-schema.org/draft-07/schema#", file

        assert schema["$id"] ==
                 "https://raw.githubusercontent.com/teapot-chess/Arkab/main/priv/contracts/bridge-protocol-v1/" <>
                   file

        assert is_binary(schema["title"]) and is_binary(schema["description"]), file
      end

      assert Enum.sort(examples) == Enum.sort(Contract.schemas())
    end

    test "every example fits its schema" do
      for {schema, file, data} <- Contract.examples() do
        assert Contract.validate(schema, data) == :ok, file
      end
    end

    test "the schemas are not a rubber stamp" do
      refute Contract.validate("hello", %{"type" => "hello", "v" => 1}) == :ok

      refute Contract.validate("events", %{
               "type" => "events",
               "events" => [
                 %{"s" => 1, "t" => 1, "id" => "COM3", "e" => %{"k" => "rx", "h" => "41"}}
               ]
             }) == :ok

      refute Contract.validate("command", %{"type" => "command", "id" => "x", "cmd" => "explode"}) ==
               :ok

      refute Contract.validate("dgt-serial-opening", %{
               Contract.read!("examples/dgt-serial-opening.json")
               | "bytes_hex" => "4a87000007870000078800000840454d424b"
             }) == :ok
    end
  end

  # --- what the encoder writes ---------------------------------------------------

  describe "bridge to server, from Arkab.Protocol" do
    test "hello, leave and every reply" do
      Contract.assert_valid!("hello", Protocol.hello("q3V9", "key", "Hall B", Bridge.software()))
      Contract.assert_valid!("leave", Protocol.leave())
      Contract.assert_valid!("reply", Protocol.reply("c1", :ok))

      for why <- [
            :not_owner,
            :unknown_command,
            :bad_command,
            :no_such_board,
            :no_such_port,
            :busy
          ] do
        Contract.assert_valid!("reply", Protocol.reply("c1", {:error, why}))
      end
    end

    test "an event of every kind a driver says, real and played back" do
      {:ok, board} =
        Board.from_text("rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR")

      events = [
        {:position, board},
        {:clock, %{white_ms: 5_400_000, black_ms: 5_390_000, running: :none, armed: :white}},
        {:clock, %{white_ms: 5_400_000, black_ms: 5_390_000, running: :black}},
        :connected,
        :disconnected,
        {:poll, :ok},
        {:poll, :missed},
        {:poll, :ok, 4},
        {:info, %{loop: nil, bus_address: nil}},
        {:info, %{loop: [6310, 12_799]}},
        {:info, %{serial: "06310", firmware: "1.9", trademark: "DGT", battery: "0A1B"}},
        {:info, %{bus_address: 6310, loop_number: 6310, error: ":enoent"}},
        {:info, %{clock: false}},
        {:info, %{clock_battery_low: true}}
      ]

      encoded =
        for {event, seq} <- Enum.with_index(events, 1) do
          Protocol.encode_event(seq, "COM3", 1_760_600_000_000 + seq, event)
        end

      played = Protocol.encode_event(99, "game", 1_200, {:at, 1_200, 4, nil, {:poll, :missed}})

      frame = Protocol.events(encoded ++ [played])
      Contract.assert_valid!("events", Protocol.encode(frame))
    end

    test "raw serial bytes do not travel" do
      assert Protocol.event_fields({:raw, :rx, <<0x41>>})
             |> then(&Contract.validate("events", events_of(&1))) !=
               :ok
    end
  end

  defp events_of(fields),
    do: %{"type" => "events", "events" => [%{"s" => 1, "t" => 1, "id" => "COM3", "e" => fields}]}

  describe "server to bridge, from Arkab.Protocol (what Alnasl calls to build them)" do
    test "welcome, refused, ack, leave and every command" do
      Contract.assert_valid!("welcome", Protocol.welcome(0, "Alnasl"))

      for why <- ~w(version key revoked),
          do: Contract.assert_valid!("refused", Protocol.refused(why))

      Contract.assert_valid!("ack", Protocol.ack(1055))
      Contract.assert_valid!("leave", Protocol.leave())

      fields = %{
        "resend" => %{},
        "rescan" => %{port: "COM3"},
        "add_port" => %{port: "COM7"},
        "forget_port" => %{port: "COM4"},
        "forget_board" => %{board: "COM4#12799"},
        "record" => %{on: true}
      }

      assert Enum.sort(Map.keys(fields)) == Enum.sort(Protocol.commands())

      for {cmd, fields} <- fields,
          do: Contract.assert_valid!("command", Protocol.command("c1", cmd, fields))
    end

    test "every example of theirs is read by the bridge's own decoder" do
      for {schema, file, data} <- Contract.examples(), schema in @to_bridge do
        assert Protocol.decode(Jason.encode!(data)) == {:ok, data}, file
      end

      commands = for {"command", _file, data} <- Contract.examples(), uniq: true, do: data["cmd"]
      assert Enum.sort(commands) == Enum.sort(Protocol.commands())
    end
  end

  describe "events, both ways" do
    test "every example event decodes and encodes back to itself" do
      for {"events", file, %{"events" => events}} <- Contract.examples(), map <- events do
        assert {:ok, %{seq: seq, id: id, t: t, at: at, event: event}} = Protocol.decode_event(map),
               "#{file}: #{inspect(map)}"

        event = if at, do: {:at, t, elem(at, 0), elem(at, 1), event}, else: event
        assert Protocol.encode_event(seq, id, t, event) == map, "#{file}: #{inspect(map)}"
      end
    end
  end

  describe "joining" do
    test "the example answer is one the bridge joins with" do
      answer = Contract.read!("examples/join-response.json")

      assert {:ok, %{url: "ws://hall.test/bridge/link", key: key, name: "Alnasl", owner?: true}} =
               Join.redeem("http://hall.test/join/K7Q-4MD", %{},
                 plug: fn conn -> Req.Test.json(conn, answer) end
               )

      assert key == answer["key"]
    end
  end

  # --- a live bridge ---------------------------------------------------------------

  describe "a live bridge" do
    setup do
      dir = Path.join(System.tmp_dir!(), "arkab-contract-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    test "every frame it sends fits, and it takes every command example", %{dir: dir} do
      clock = %{white_ms: 5_400_000, black_ms: 5_390_000, running: :none}
      start_supervised!({Fake, port: "FAKE-CT1", device: {Emulator, Emulator.new(clock: clock)}})

      server = FakeServer.start(codes: ["A"])

      start_supervised!(
        {Bridge, data_dir: dir, name: "hall", sources: [%{"port" => "FAKE-CT1"}]},
        id: Bridge
      )

      {:ok, server_id} = Bridge.join(FakeServer.link(server, "A"))
      Contract.assert_valid!("join-request", FakeServer.get(server, :bridge))

      eventually(fn ->
        Enum.any?(FakeServer.events(server), &match?(%{event: {:clock, _}}, &1)) and
          match?(%{"boards" => [%{"serial" => "12345"}]}, FakeServer.get(server, :boards))
      end)

      ids =
        for {"command", _file, frame} <- Contract.examples() do
          FakeServer.push(server, frame)
          frame["id"]
        end

      eventually(fn ->
        replied = for reply <- FakeServer.get(server, :replies), do: reply["id"]
        Enum.all?(ids, &(&1 in replied))
      end)

      # Every example is a command the bridge understood: refused for being
      # about a port or board it does not have, perhaps, but never as nonsense.
      for reply <- FakeServer.get(server, :replies) do
        refute reply["error"] in ["bad_command", "unknown_command"], inspect(reply)
      end

      Bridge.remove(server_id)
      eventually(fn -> FakeServer.get(server, :left?) == true end)

      frames = Enum.map(FakeServer.frames(server), &Jason.decode!/1)
      for frame <- frames, do: Contract.assert_valid!(Contract.schema_of(frame), frame)

      assert hd(frames)["type"] == "hello"
      types = frames |> Enum.map(& &1["type"]) |> MapSet.new()
      assert MapSet.equal?(types, MapSet.new(~w(hello boards events reply leave)))
    end

    test "the server's leave example removes the server", %{dir: dir} do
      server = FakeServer.start(codes: ["A"])
      start_supervised!({Bridge, data_dir: dir, name: "hall", sources: []}, id: Bridge)
      {:ok, _} = Bridge.join(FakeServer.link(server, "A"))
      eventually(fn -> Enum.all?(Bridge.status().servers, & &1.up?) end)

      FakeServer.push(server, Contract.read!("examples/leave.json"))
      eventually(fn -> Arkab.Bridge.Store.servers() == [] end)
    end
  end

  # --- the serial line -----------------------------------------------------------

  describe "the DGT serial opening" do
    test "the driver writes exactly the pinned bytes, with the clock and without" do
      for {"dgt-serial-opening", file, pinned} <- Contract.examples() do
        port = "FAKE-OPEN-#{System.unique_integer([:positive])}"
        start_supervised!({Fake, port: port}, id: port)

        driver =
          start_supervised!(
            {DgtSerial,
             owner: self(),
             id: port,
             port: port,
             transport: Fake,
             resync_ms: 600_000,
             options: %{"clock" => pinned["clock"]}},
            id: {:driver, port}
          )

        expected = Base.decode16!(pinned["bytes_hex"], case: :lower)
        eventually(fn -> byte_size(Fake.written(port)) >= byte_size(expected) end)
        _ = :sys.get_state(driver)

        assert Base.encode16(Fake.written(port), case: :lower) == pinned["bytes_hex"], file

        assert pinned["bytes_hex"] ==
                 pinned["probe_hex"] <> pinned["handshake_hex"] <> pinned["asks_hex"],
               file

        update = if pinned["clock"], do: :update_nice, else: :update_board

        handshake =
          Enum.map_join(
            [:reset, :serial, :version, :board, update],
            &Arkab.Dgt.Protocol.command/1
          )

        assert Base.encode16(handshake, case: :lower) == pinned["handshake_hex"], file
      end
    end
  end

  defp eventually(fun, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait(fun, deadline)
  end

  defp wait(fun, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline, do: flunk("it did not happen in time")
      Process.sleep(20)
      wait(fun, deadline)
    end
  end
end
