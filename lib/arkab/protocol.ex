defmodule Arkab.Protocol do
  @moduledoc """
  The link between a bridge and an Alnasl: what goes over the one
  WebSocket, in both directions. `docs/protocol.md` is the same thing in
  prose; this module is the one both ends compile, so they cannot read it
  differently.

  Every frame is a JSON text frame, an object with a `"type"`. Version
  `#{1}` (`version/0`). A server that does not speak the bridge's version
  says so (`refused`, `"version"`) instead of guessing.

  ## Bridge to server

  | type | fields | meaning |
  |---|---|---|
  | `hello` | `v`, `bridge`, `key`, `name`, `software` | the first frame, always: who this is |
  | `events` | `events: [event]` | driver events, oldest first, numbered |
  | `boards` | `boards`, `ports`, `recording` | what the bridge reads now; sent on joining and on every change |
  | `reply` | `id`, `ok`, `error` | the answer to a command |
  | `leave` | | this server was removed on the bridge |

  ## Server to bridge

  | type | fields | meaning |
  |---|---|---|
  | `welcome` | `v`, `seen`, `server` | accepted; `seen` is the highest number it holds |
  | `refused` | `reason` | `"version"`, `"key"` (not ours), `"revoked"` (removed here: forget me) |
  | `ack` | `seq` | everything up to `seq` is the server's now |
  | `command` | `id`, `cmd`, ... | see `commands/0` |
  | `leave` | | this bridge was removed on the server |

  ## An event

  `{"s": seq, "t": ms, "id": board, "e": {...}}` and, from a driver that
  plays recorded time (`Arkab.Driver.Player`), `"at": [speed, next]`. `t`
  is the time the event happened: wall-clock milliseconds on the bridge for
  a real board, the recording's own time for a played one. `id` is the
  board (`board_id/2`). `e` is the driver event (`Arkab.Driver`), in the
  capture file's words where it has them (`Arkab.Capture`).
  """

  alias Arkab.Board

  @version 1

  # What a board says about itself, as the drivers say it. A name that is
  # not in this list does not travel, and nothing from the other end ever
  # becomes an atom it did not already have.
  @info_keys [
    :serial,
    :firmware,
    :battery,
    :bus_address,
    :trademark,
    :error,
    :loop,
    :loop_number,
    :clock,
    :clock_battery_low
  ]
  @info_names Map.new(@info_keys, &{to_string(&1), &1})

  @doc "The protocol version this side speaks."
  def version, do: @version

  @doc "The versions this side accepts from the other."
  def accepts?(v), do: v == @version

  @doc """
  The commands a server can send, with their fields: `rescan` (`port`, or
  every port), `add_port` (`port`), `forget_port` (`port`, owner only),
  `forget_board` (`board`, owner only), `resend` (`board`, or every board:
  the whole board again - status, what it said about itself, the position,
  the clock), `record` (`on`: true or false).
  """
  def commands, do: ~w(rescan add_port forget_port forget_board resend record)

  @doc "The commands only a server joined as owner may give."
  def owner_only, do: ~w(forget_port forget_board)

  # --- boards ------------------------------------------------------------------

  @doc """
  The name a board goes by on the link: its port, and its address on a
  loop. `"COM3"`, `"/dev/ttyUSB0#12799"`. A played board's port is whatever
  the bridge calls it.
  """
  def board_id(port, nil), do: port
  def board_id(port, address) when is_integer(address), do: "#{port}##{address}"

  @doc "`{port, address}` of a board's name; `address` is `nil` for a single board."
  def parse_board_id(id) when is_binary(id) do
    case Regex.run(~r/^(.*)#(\d+)$/, id) do
      [_, port, address] -> {port, String.to_integer(address)}
      nil -> {id, nil}
    end
  end

  # --- frames ------------------------------------------------------------------

  @doc "A frame as JSON text."
  def encode(%{"type" => _} = frame), do: Jason.encode!(frame)

  @doc "`{:ok, frame}` for a JSON object with a type, `{:error, :bad_frame}` for anything else."
  def decode(text) do
    case Jason.decode(text) do
      {:ok, %{"type" => type} = frame} when is_binary(type) -> {:ok, frame}
      _other -> {:error, :bad_frame}
    end
  end

  def hello(bridge, key, name, software),
    do: %{
      "type" => "hello",
      "v" => @version,
      "bridge" => bridge,
      "key" => key,
      "name" => name,
      "software" => software
    }

  def welcome(seen, server),
    do: %{"type" => "welcome", "v" => @version, "seen" => seen, "server" => server}

  def refused(reason) when reason in ["version", "key", "revoked"],
    do: %{"type" => "refused", "reason" => reason}

  def ack(seq), do: %{"type" => "ack", "seq" => seq}
  def leave, do: %{"type" => "leave"}

  def command(id, cmd, fields \\ %{}) when is_binary(cmd),
    do:
      fields
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(%{"type" => "command", "id" => id, "cmd" => cmd})

  def reply(id, :ok), do: %{"type" => "reply", "id" => id, "ok" => true}

  def reply(id, {:error, why}),
    do: %{"type" => "reply", "id" => id, "ok" => false, "error" => to_string(why)}

  def events(events), do: %{"type" => "events", "events" => events}

  # --- events ------------------------------------------------------------------

  @doc """
  An event as it is stored and sent: `seq`, the board's name, the time it
  happened and the driver event, which may be wrapped in `{:at, t, speed,
  next, event}` (then `t` is that one, and `speed` and `next` travel too).
  `nil` for an event that does not travel.
  """
  def encode_event(seq, id, _t, {:at, at, speed, next, event}) do
    with %{} = map <- encode_event(seq, id, at, event) do
      Map.put(map, "at", [speed, next])
    end
  end

  def encode_event(seq, id, t, event) do
    case event_fields(event) do
      nil -> nil
      fields -> %{"s" => seq, "t" => t, "id" => id, "e" => fields}
    end
  end

  @doc "The fields of a driver event, without its number and time. `nil` for one that does not travel."
  def event_fields({:position, board}), do: %{"k" => "pos", "b" => Board.to_text(board)}
  def event_fields({:clock, reading}), do: Arkab.Capture.clock_line(reading)
  def event_fields(:connected), do: %{"k" => "st", "v" => "connected"}
  def event_fields(:disconnected), do: %{"k" => "st", "v" => "disconnected"}

  def event_fields({:poll, result}) when result in [:ok, :missed],
    do: %{"k" => "poll", "v" => to_string(result)}

  def event_fields({:poll, :ok, n}) when is_integer(n) and n > 1,
    do: %{"k" => "poll", "v" => "ok", "n" => n}

  def event_fields({:raw, direction, bytes}) when direction in [:rx, :tx],
    do: %{"k" => to_string(direction), "h" => Base.encode16(bytes, case: :lower)}

  def event_fields({:info, info}) when is_map(info) do
    fields = for {key, value} <- info, key in @info_keys, into: %{}, do: {to_string(key), value}
    %{"k" => "info", "i" => fields}
  end

  def event_fields(_other), do: nil

  @doc """
  An event as it arrived: `{:ok, %{seq, id, t, at, event}}` - `at` is
  `{speed, next}` or `nil` - or `{:error, :bad_event}`.
  """
  def decode_event(%{"s" => seq, "t" => t, "id" => id, "e" => fields} = map)
      when is_integer(seq) and is_integer(t) and is_binary(id) and is_map(fields) do
    at =
      case map["at"] do
        [speed, next] when is_number(speed) and (is_integer(next) or is_nil(next)) ->
          {speed, next}

        _none ->
          nil
      end

    case event(fields) do
      {:ok, event} -> {:ok, %{seq: seq, id: id, t: t, at: at, event: event}}
      :error -> {:error, :bad_event}
    end
  end

  def decode_event(_other), do: {:error, :bad_event}

  defp event(%{"k" => "pos", "b" => text}) do
    case Board.from_text(text) do
      {:ok, board} -> {:ok, {:position, board}}
      :error -> :error
    end
  end

  defp event(%{"k" => "clk"} = line) do
    reading = %{white_ms: line["w"], black_ms: line["b"], running: side(line["r"], :none)}

    reading =
      case side(line["l"], nil) do
        nil -> reading
        armed -> Map.put(reading, :armed, armed)
      end

    {:ok, {:clock, reading}}
  end

  defp event(%{"k" => "st", "v" => "connected"}), do: {:ok, :connected}
  defp event(%{"k" => "st", "v" => "disconnected"}), do: {:ok, :disconnected}
  # "n": how many answers this one stands for (see `Arkab.Bridge.Board`).
  # A bridge that does not say means one.
  defp event(%{"k" => "poll", "v" => "ok", "n" => n}) when is_integer(n) and n > 1,
    do: {:ok, {:poll, :ok, min(n, 1_000_000)}}

  defp event(%{"k" => "poll", "v" => "ok"}), do: {:ok, {:poll, :ok}}
  defp event(%{"k" => "poll", "v" => "missed"}), do: {:ok, {:poll, :missed}}

  defp event(%{"k" => direction, "h" => hex}) when direction in ["rx", "tx"] do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, {:raw, String.to_existing_atom(direction), bytes}}
      :error -> :error
    end
  end

  defp event(%{"k" => "info", "i" => fields}) when is_map(fields) do
    {:ok,
     {:info,
      for({k, v} <- fields, is_map_key(@info_names, k), into: %{}, do: {@info_names[k], v})}}
  end

  defp event(_other), do: :error

  defp side("white", _default), do: :white
  defp side("black", _default), do: :black
  defp side("none", _default), do: :none
  defp side(_other, default), do: default
end
