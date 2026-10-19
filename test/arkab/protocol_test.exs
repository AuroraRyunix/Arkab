defmodule Arkab.ProtocolTest do
  @moduledoc """
  What goes over the link comes out as it went in: every driver event, its
  time, and the played board's speed and next time. And nothing from the
  other end becomes an atom it did not already have.
  """

  use ExUnit.Case, async: true

  alias Arkab.{Board, Protocol}

  defp round_trip(event, at \\ nil) do
    wrapped =
      case at do
        nil -> event
        {t, speed, next} -> {:at, t, speed, next, event}
      end

    map = Protocol.encode_event(7, "COM3#12799", 1_791_700_000_123, wrapped)
    # Through JSON, as on the wire.
    {:ok, %{"type" => "events", "events" => [map]}} =
      Protocol.events([map]) |> Protocol.encode() |> Protocol.decode()

    {:ok, decoded} = Protocol.decode_event(map)
    decoded
  end

  test "every driver event survives the trip" do
    {:ok, after_e4} =
      Board.from_text("rnbqkbnrpppppppp............P...................PPPP.PPPRNBQKBNR")

    events = [
      {:position, Board.start()},
      {:position, after_e4},
      {:position, Board.empty()},
      {:clock, %{white_ms: 5_400_000, black_ms: 5_399_000, running: :white, armed: :white}},
      {:clock, %{white_ms: 60_000, black_ms: 59_000, running: :none}},
      :connected,
      :disconnected,
      {:poll, :ok},
      {:poll, :ok, 57},
      {:poll, :missed},
      {:raw, :rx, <<0x8E, 0x00, 0x05, 52, 0x00>>},
      {:raw, :tx, <<0x42>>},
      {:info, %{serial: "06310", firmware: "1.9", bus_address: 12_799}},
      {:info, %{clock: false}},
      {:info, %{loop: [1, 2], loop_number: 3, clock_battery_low: true, battery: "00FF"}}
    ]

    for event <- events do
      assert %{seq: 7, id: "COM3#12799", t: 1_791_700_000_123, at: nil, event: ^event} =
               round_trip(event)
    end
  end

  test "a played board's speed and next time travel with it" do
    decoded = round_trip({:position, Board.start()}, {4_200, 20, 4_900})
    assert decoded.t == 4_200
    assert decoded.at == {20, 4_900}

    assert round_trip(:connected, {0, 1.5, nil}).at == {1.5, nil}
  end

  test "an unknown name in what a board says about itself does not travel" do
    map = Protocol.encode_event(1, "COM3", 1, {:info, %{serial: "1", secret_thing: "x"}})
    assert map["e"]["i"] == %{"serial" => "1"}

    sneaky =
      put_in(map, ["e", "i"], %{"serial" => "1", "not_an_atom_#{System.unique_integer()}" => 1})

    assert {:ok, %{event: {:info, %{serial: "1"}}}} = Protocol.decode_event(sneaky)
  end

  test "what is not an event is said to be so" do
    assert Protocol.encode_event(1, "COM3", 1, {:something, :else}) == nil
    assert Protocol.decode_event(%{"s" => 1}) == {:error, :bad_event}

    assert Protocol.decode_event(%{
             "s" => 1,
             "t" => 1,
             "id" => "x",
             "e" => %{"k" => "pos", "b" => "nonsense"}
           }) ==
             {:error, :bad_event}

    assert Protocol.decode("not json") == {:error, :bad_frame}
    assert Protocol.decode(~s({"no":"type"})) == {:error, :bad_frame}
  end

  test "a board's name says where it is" do
    assert Protocol.board_id("COM3", nil) == "COM3"
    assert Protocol.board_id("/dev/ttyUSB0", 12_799) == "/dev/ttyUSB0#12799"
    assert Protocol.parse_board_id("/dev/ttyUSB0#12799") == {"/dev/ttyUSB0", 12_799}
    assert Protocol.parse_board_id("COM3") == {"COM3", nil}
    assert Protocol.parse_board_id("replay-1") == {"replay-1", nil}
  end

  test "the frames each side sends" do
    assert {:ok, %{"type" => "hello", "v" => 1, "bridge" => "b", "key" => "k"}} =
             Protocol.hello("b", "k", "hall", "arkab 0.1.0")
             |> Protocol.encode()
             |> Protocol.decode()

    assert Protocol.welcome(41, "server")["seen"] == 41
    assert Protocol.ack(9) == %{"type" => "ack", "seq" => 9}

    assert %{"type" => "command", "id" => "c1", "cmd" => "resend", "board" => "COM3"} =
             Protocol.command("c1", "resend", board: "COM3")

    assert Protocol.reply("c1", {:error, :not_owner})["error"] == "not_owner"
    assert Protocol.accepts?(Protocol.version())
    refute Protocol.accepts?(Protocol.version() + 1)
  end
end
