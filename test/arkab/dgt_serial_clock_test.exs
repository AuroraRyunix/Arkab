defmodule Arkab.DgtSerialClockTest do
  # A clock switched on and standing still: "nice" update mode never says a
  # word about it, so the driver has to ask.
  use ExUnit.Case, async: false

  alias Arkab.Dgt.Emulator
  alias Arkab.Driver.DgtSerial
  alias Arkab.Transport.Fake

  defp start_board(name, clock) do
    port = "FAKE-CLOCK-#{name}"
    device = {Emulator, Emulator.new(clock: clock)}
    start_supervised!({Fake, port: port, device: device}, id: port)

    start_supervised!(
      {DgtSerial, owner: self(), id: name, port: port, transport: Fake, resync_ms: 100},
      id: name
    )

    name
  end

  test "a stopped clock is read at the handshake" do
    id = start_board("stopped", %{white_ms: 5_400_000, black_ms: 5_390_000, running: :none})

    assert_receive {:driver, ^id, {:clock, %{white_ms: 5_400_000, black_ms: 5_390_000}}}, 2_000
  end

  test "a board that never answers the clock question is asked five times, not forever" do
    id = start_board("silent", nil)

    Process.sleep(1_200)
    asks = for {:driver, ^id, {:raw, :tx, "A"}} <- messages(), do: :ask
    assert length(asks) == 5
  end

  test "serial number and firmware arrive, and an answered question is not asked again" do
    id = start_board("serial", nil)

    assert_receive {:driver, ^id, {:info, %{serial: "12345"}}}, 2_000
    assert_receive {:driver, ^id, {:info, %{firmware: "1.8"}}}, 2_000

    Process.sleep(500)
    sent = for {:driver, ^id, {:raw, :tx, byte}} when byte in ["E", "M"] <- messages(), do: byte
    # Once each, in the handshake.
    assert Enum.sort(sent) == ["E", "M"]
  end

  defp messages do
    receive do
      message -> [message | messages()]
    after
      0 -> []
    end
  end
end
