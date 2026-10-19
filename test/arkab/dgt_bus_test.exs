defmodule Arkab.DgtBusTest do
  @moduledoc """
  Two boards on one loop, as the owner has them: an old one (firmware 1.9,
  address 6310, which is its serial number) and a new one (firmware 4.0,
  address 12799). Neither may be taken for the other, neither may be
  reported missing for the other's sake, and a board that answers a little
  late is a slow board, not an absent one.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Arkab.Dgt.Emulator
  alias Arkab.Driver.DgtBus
  alias Arkab.Transport.Fake

  defmodule Slow do
    @moduledoc "A loop whose old board (the first) answers `ms` late."
    alias Arkab.Dgt.Emulator

    def handle({[old | others], ms}, bytes) do
      {slow, old} = Emulator.handle(old, bytes)
      {fast, others} = Emulator.handle(others, bytes)
      {[{:after, ms, slow}, fast], {[old | others], ms}}
    end
  end

  defmodule Mangled do
    @moduledoc "A loop whose old board's long answers arrive with a wrong last byte."
    alias Arkab.Dgt.Emulator

    def handle([old | others], bytes) do
      {said, old} = Emulator.handle(old, bytes)
      {fast, others} = Emulator.handle(others, bytes)
      {[mangle(said), fast], [old | others]}
    end

    defp mangle(said) when byte_size(said) > 20 do
      size = byte_size(said) - 1
      <<body::binary-size(^size), last>> = said
      body <> <<Bitwise.band(last + 1, 0x7F)>>
    end

    defp mangle(said), do: said
  end

  defp boards do
    [
      Emulator.new(address: 6310, serial: "06310", version: "1.9", bus?: true),
      Emulator.new(address: 12_799, serial: "00730", version: "4.0", bus?: true)
    ]
  end

  defp start_loop(device, name) do
    port = "FAKE-BUS-#{name}"
    start_supervised!({Fake, port: port, device: device}, id: port)

    start_supervised!(Arkab.Drivers)

    {:ok, bus} = DgtBus.ensure(port, transport: Fake, discover_ms: 60_000, reply_ms: 200)
    for address <- [6310, 12_799], do: DgtBus.attach(bus, address, self(), "#{port}##{address}")
    {port, bus}
  end

  defp stats(bus), do: Map.new(DgtBus.stats(bus), &{&1.address, &1})

  defp wait_for(fun, ms \\ 4_000) do
    deadline = System.monotonic_time(:millisecond) + ms

    Stream.repeatedly(fn ->
      Process.sleep(25)
      fun.()
    end)
    |> Enum.find(&(&1 or System.monotonic_time(:millisecond) > deadline))
  end

  test "an old and a new board on one loop are two boards that both answer" do
    {port, bus} = start_loop({Emulator, boards()}, "TWO")

    assert wait_for(fn ->
             s = stats(bus)
             s[6310].answered > 30 and s[12_799].answered > 30
           end)

    s = stats(bus)
    assert s[6310].missed == 0
    assert s[12_799].missed == 0

    # The old board is known by its serial number, the new one by nothing
    # but its address; the ids are the port and the address.
    assert_received {:driver, id, {:info, %{firmware: "1.9", serial: "06310", loop_number: 6310}}}
    assert id == "#{port}#6310"
    assert_received {:driver, _, {:info, %{firmware: "4.0", loop_number: 12_799} = info}}
    refute Map.has_key?(info, :serial)
  end

  test "a board that answers inside its time is not reported missing" do
    {_port, bus} = start_loop({Slow, {boards(), 120}}, "SLOWISH")
    assert wait_for(fn -> stats(bus)[6310].answered > 5 end, 8_000)
    assert stats(bus)[6310].missed == 0
    assert stats(bus)[12_799].missed == 0
  end

  test "a board a little too slow is given the time it shows it needs" do
    log =
      capture_log(fn ->
        {_port, bus} = start_loop({Slow, {boards(), 260}}, "SLOW")
        assert wait_for(fn -> stats(bus)[6310].answered > 5 end, 15_000)
        s = stats(bus)
        # It missed while the loop found out, not for ever; the other never.
        assert s[6310].missed <= 2
        assert s[12_799].missed == 0
        assert s[6310].connected?
      end)

    assert log =~ "too late"
    assert log =~ "6310 did not answer"
  end

  test "a miss says what came back instead: nothing, or which bytes" do
    log =
      capture_log(fn ->
        {_port, bus} = start_loop({Mangled, boards()}, "MANGLED")
        assert wait_for(fn -> stats(bus)[6310].missed > 0 end, 8_000)
      end)

    assert log =~ ~r/6310 did not answer \w+ within \d+ ms: \d+ bytes came back/
    assert log =~ "damaged (bad checksum)"
  end
end
