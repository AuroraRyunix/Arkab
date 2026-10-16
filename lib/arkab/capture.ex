defmodule Arkab.Capture do
  @moduledoc """
  The capture format: everything a board delivered, one JSON object a line.

      {"t":1791700000123,"k":"cfg","flipped":false,"round":4,"board":7,"driver":"dgt_serial"}
      {"t":1791700000456,"k":"pos","b":"rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR"}
      {"t":1791700003210,"k":"clk","w":5400000,"b":5400000,"r":"white","l":"white"}
      {"t":1791700003300,"k":"rx","h":"8e0005340c"}
      {"t":1791700009000,"k":"st","v":"disconnected"}
      {"t":1791700012000,"k":"note","text":"knocked over on purpose"}

  `t` is wall-clock milliseconds. `pos` is the board exactly as the driver
  reported it - before anybody turns a flipped board round - as 64
  characters from a8 to h1. `clk` is a clock reading: both times, the side
  running (`r`: `white`, `black`, `none` - or `off` for a clock switched
  off) and, from a driver that can tell, the side its lever is set for
  (`l`). `rx`/`tx` are the raw serial bytes of a real board, hex. `cfg` says
  how the board was set up when the lines after it were written, so a
  capture can be replayed the way it was read.

  Writing is `Arkab.Recorder`'s; reading back is `read/2`, which gives the
  timed events a driver would deliver - what `Arkab.Driver.Replay` plays.
  """

  alias Arkab.Board
  alias Arkab.Dgt.Protocol

  @doc "The fields of the line for `event`, without `t`; `nil` for what is not written down."
  def line({:position, board}), do: %{"k" => "pos", "b" => Board.to_text(board)}

  def line({:clock, :off}), do: %{"k" => "clk", "r" => "off"}
  def line({:clock, reading}), do: clock_line(reading)

  def line({:status, status}), do: %{"k" => "st", "v" => to_string(status)}

  def line({:raw, direction, bytes}),
    do: %{"k" => to_string(direction), "h" => Base.encode16(bytes, case: :lower)}

  def line({:cfg, fields}),
    do: Map.put(Map.new(fields, fn {k, v} -> {to_string(k), v} end), "k", "cfg")

  def line({:note, text}), do: %{"k" => "note", "text" => text}
  def line(_other), do: nil

  @doc "A clock reading as the fields of a `clk` line."
  def clock_line(reading) do
    %{
      "k" => "clk",
      "w" => reading[:white_ms],
      "b" => reading[:black_ms],
      "r" => to_string(reading[:running] || :none)
    }
    |> then(&if(reading[:armed], do: Map.put(&1, "l", to_string(reading.armed)), else: &1))
  end

  @doc """
  Reads a capture: `{:ok, %{events, cfg, notes, lines, raw?}}` where `events`
  is `[{ms_since_first_line, driver_event}]`. A capture that holds raw bytes
  and no positions (a recording of a real board, or a log written by
  `tools/serial_proxy.py`) is decoded with the DGT protocol on the way.
  """
  def read(path, address \\ nil) do
    with {:ok, text} <- File.read(path) do
      # A capture of a loop marks each line with the address it belongs to
      # (`"a"`); `address` picks one board out of it.
      lines =
        text
        |> String.split("\n", trim: true)
        |> Enum.map(&parse_line/1)
        |> Enum.reject(&(is_nil(&1) or (address != nil and &1["a"] not in [nil, address])))

      case lines do
        [] ->
          {:error, :empty}

        [%{"t" => t0} | _] ->
          positions? = Enum.any?(lines, &(&1["k"] == "pos"))
          raw? = Enum.any?(lines, &(&1["k"] == "rx"))

          events = if positions?, do: from_positions(lines, t0), else: from_bytes(lines, t0)

          {:ok,
           %{
             events: events,
             cfg: lines |> Enum.filter(&(&1["k"] == "cfg")) |> List.first() || %{},
             notes: for(%{"k" => "note", "t" => t, "text" => text} <- lines, do: {t - t0, text}),
             lines: length(lines),
             raw?: raw? and not positions?
           }}
      end
    end
  end

  defp parse_line(line) do
    case Jason.decode(line) do
      {:ok, %{"t" => t, "k" => _} = fields} when is_integer(t) -> fields
      _not_ours -> proxy_line(line)
    end
  end

  # tools/serial_proxy.py: "   12.345678  BRD>APP  86 00 43 ..." and "# 12.3  NOTE  text".
  defp proxy_line(line) do
    case Regex.run(~r/^\s*(\d+\.\d+)\s+(APP>BRD|BRD>APP)\s+([0-9a-fA-F ]+)$/, line) do
      [_, seconds, direction, hex] ->
        %{
          "t" => round(String.to_float(seconds) * 1000),
          "k" => if(direction == "BRD>APP", do: "rx", else: "tx"),
          "h" => String.replace(hex, " ", "")
        }

      nil ->
        case Regex.run(~r/^#\s*(\d+\.\d+)\s+NOTE\s+(.*)$/, line) do
          [_, seconds, text] ->
            %{"t" => round(String.to_float(seconds) * 1000), "k" => "note", "text" => text}

          nil ->
            nil
        end
    end
  end

  defp from_positions(lines, t0) do
    Enum.flat_map(lines, fn
      %{"k" => "pos", "t" => t, "b" => text} ->
        case Board.from_text(text) do
          {:ok, board} -> [{t - t0, {:position, board}}]
          :error -> []
        end

      %{"k" => "clk", "t" => t, "r" => "off"} ->
        [{t - t0, {:info, %{clock: false}}}]

      %{"k" => "clk", "t" => t} = line ->
        reading = %{white_ms: line["w"], black_ms: line["b"], running: running(line["r"])}

        reading =
          case line["l"] do
            "white" -> Map.put(reading, :armed, :white)
            "black" -> Map.put(reading, :armed, :black)
            _none -> reading
          end

        [{t - t0, {:clock, reading}}]

      %{"k" => "st", "t" => t, "v" => "connected"} ->
        [{t - t0, :connected}]

      %{"k" => "st", "t" => t, "v" => "disconnected"} ->
        [{t - t0, :disconnected}]

      _other ->
        []
    end)
  end

  # Raw bytes only: run them through the protocol parser and the same small
  # board model the serial driver keeps.
  defp from_bytes(lines, t0) do
    {events, _state} =
      lines
      |> Enum.filter(&(&1["k"] == "rx"))
      |> Enum.flat_map_reduce({<<>>, nil}, fn %{"t" => t, "h" => hex}, {buffer, board} ->
        bytes =
          case Base.decode16(hex, case: :mixed) do
            {:ok, bytes} -> bytes
            :error -> <<>>
          end

        {messages, rest} = Protocol.parse(buffer <> bytes)

        {events, board} =
          Enum.flat_map_reduce(messages, board, fn message, board ->
            case Protocol.apply_message(message, board) do
              {:position, board} -> {[{t - t0, {:position, board}}], board}
              {:clock, reading} -> {[{t - t0, {:clock, reading}}], board}
              {:info, %{clock: false} = off} -> {[{t - t0, {:info, off}}], board}
              _other -> {[], board}
            end
          end)

        {events, {rest, board}}
      end)

    events
  end

  defp running("white"), do: :white
  defp running("black"), do: :black
  defp running(_other), do: :none
end
