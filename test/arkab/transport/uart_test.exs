defmodule Arkab.Transport.UartTest do
  use ExUnit.Case, async: true

  alias Arkab.Transport.Uart

  # A Mac ran out of processes after a day of retrying an unplugged adapter:
  # every failed open left its UART, and the UART's helper program, behind.
  test "a port that does not open leaves no UART behind" do
    if Uart.available?() do
      links = fn -> self() |> Process.info(:links) |> elem(1) |> MapSet.new() end
      before = links.()

      for _ <- 1..3,
          do: assert({:error, _} = Uart.open("/dev/arkab-no-such-port", baud: 9600))

      assert links.() == before
    end
  end
end
