defmodule Arkab.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :arkab,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: [arkab: [applications: [arkab: :permanent]]]
    ]
  end

  # Nothing starts by itself unless this is the bridge (`config :arkab,
  # role: :bridge`): as Alnasl's dependency it is a library of drivers, and
  # Alnasl decides what runs. See `Arkab.Application`.
  def application do
    [
      mod: {Arkab.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.2"},
      # The join: one POST to the address in the link.
      {:req, "~> 0.5"},
      # The queue. SQLite without Ecto: one table of events, one of servers,
      # one process that owns the file. A repo and migrations would be more
      # machinery than queue.
      {:exqlite, "~> 0.42"},
      # The outgoing link. Mint is already here through Req; this is its
      # WebSocket half, by the same people. See docs/protocol.md.
      {:mint_web_socket, "~> 1.0"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ] ++ uart()
  end

  # The serial port library is C code built with make. It builds on the Pi
  # and on Windows with mingw - but not from a path with a space in it, so
  # on Windows it is asked for rather than assumed. ARKAB_UART=1|0 decides;
  # when it is not set, ALNASL_UART does (Arkab built as Alnasl's
  # dependency goes the way Alnasl goes: a server built with ALNASL_UART=0
  # gets no serial NIF from here either). Without it, everything but a real
  # serial port works: `Arkab.Transport.Uart` looks the library up at run
  # time and says it is not there.
  defp uart do
    wanted =
      case System.get_env("ARKAB_UART") || System.get_env("ALNASL_UART") do
        "1" -> true
        "0" -> false
        _unset -> match?({:unix, _}, :os.type())
      end

    if wanted, do: [{:circuits_uart, "~> 1.5"}], else: []
  end

  defp aliases do
    [
      precommit: ["compile --warnings-as-errors", "format", "test"]
    ]
  end
end
