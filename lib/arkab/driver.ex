defmodule Arkab.Driver do
  @moduledoc """
  A source of boards.

  A driver is a process. It is started with `owner: pid` and `id: term` and
  from then on sends the owner `{:driver, id, event}`:

  | event | meaning |
  |---|---|
  | `{:position, board}` | the WHOLE board as it reads now: a 64-tuple, a8 first (`Arkab.Board`). Sent on every change, and again whenever the driver re-reads the board |
  | `{:clock, %{white_ms, black_ms, running}}` | a clock reading; `running` is `:white`, `:black` or `:none`. Never sent by a board without a clock |
  | `:connected` / `:disconnected` | the board answers / has stopped answering |
  | `{:info, map}` | what the board says about itself: `:serial`, `:firmware`, `:battery` |
  | `{:poll, :ok \\| :missed}` | one question to the board was answered / was not - the signal quality |
  | `{:raw, :rx \\| :tx, binary}` | the bytes on the wire, for the capture file |

  A driver that plays recorded or simulated time wraps each event as
  `{:at, t_ms, speed, next_t_ms, event}`; see `Arkab.Driver.Player`.

  Full positions, not moves and not changes: what a move is, is the
  tracker's business (Alnasl's), and a driver that reports the whole board
  cannot drift from it.

  This contract is the cut between Arkab and Alnasl. Alnasl reads it from a
  driver in its own process tree, or from a bridge that ran the same driver
  somewhere else (`Arkab.Protocol` carries it over the wire unchanged).

  The drivers here: `Arkab.Driver.Replay` (a capture file played back),
  `Arkab.Driver.DgtSerial` (one DGT board on a serial port) and
  `Arkab.Driver.DgtBus` (a loop of DGT boards). The bus driver needs
  `Arkab.Drivers` running.
  """

  @callback start_link(keyword()) :: GenServer.on_start()

  @doc "Sends an event to a driver's owner."
  def emit(owner, id, event), do: send(owner, {:driver, id, event})
end
