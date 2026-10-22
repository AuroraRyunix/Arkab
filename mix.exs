defmodule Arkab.MixProject do
  use Mix.Project

  def project do
    [
      app: :arkab,
      version: "0.3.8",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases()
    ]
  end

  # Nothing starts by itself unless this is the bridge (`config :arkab,
  # role: :bridge`): as Alnasl's dependency it is a library of drivers, and
  # Alnasl decides what runs. See `Arkab.Application`.
  def application do
    [
      mod: {Arkab.Application, []},
      extra_applications: [:logger, :crypto, :runtime_tools]
    ]
  end

  # What is shipped: an ordinary Erlang release, the runtime inside, so there
  # is nothing to install first - the same shape as Alnasl's (docs/releasing.md).
  # A folder, not a single self-unpacking executable, on purpose: an unsigned
  # executable that unpacks a runtime and starts processes is what antivirus
  # takes for a dropper. As Alnasl's dependency none of this runs: releases
  # are the root project's business, and `config :arkab, role: :bridge`
  # (config/config.exs) is the root project's config, which a dependency's
  # never is - see `Arkab.Application`.
  defp releases do
    [
      arkab: [
        applications: [arkab: :permanent],
        steps: [:assemble, &__MODULE__.release_extras/1]
      ]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  @doc false
  # The files that stand beside `bin/` in a release, per system. A step and
  # not an overlay: an overlay copies the same files everywhere (a .bat in a
  # Linux tarball), and the Windows launcher is built, not copied.
  def release_extras(release) do
    case :os.type() do
      {:win32, _} ->
        copy_extras(release, "rel/windows", ~w(Arkab.bat))
        windows_launcher(release)
        velopack_dll(release)
        c_runtime(release)
        without_debug_files(release)

      # Nothing beside bin/ on a Mac: the release goes inside Arkab.app,
      # whose launcher (rel/macos/launcher.sh) is put there by
      # rel/macos/build_app.sh, and systemd units mean nothing to macOS.
      {:unix, :darwin} ->
        :ok

      _unix ->
        copy_extras(
          release,
          "rel/linux",
          ~w(arkab.sh install.sh update.sh uninstall.sh arkab.service
             arkab-update.service arkab-update.path)
        )
    end

    File.write!(Path.join(release.path, "VERSION"), release.version <> "\n")
    release
  end

  defp copy_extras(release, dir, names) do
    for name <- names do
      target = Path.join(release.path, name)
      File.cp!(Path.join([__DIR__, dir, name]), target)
      if Path.extname(name) == ".sh", do: File.chmod!(target, 0o755)
    end
  end

  # Arkab.exe, compiled from rel/windows/launcher.c with `zig cc`. Without
  # Zig the release is still whole and starts through Arkab.bat; what will
  # not work is the installer, and rel/windows/build_installer.ps1 refuses a
  # payload without the launcher, as does the release workflow. So a missing
  # or failing Zig warns here and is fatal there.
  defp windows_launcher(release) do
    script = Path.join([__DIR__, "rel", "windows", "build_launcher.ps1"])
    output = Path.join(release.path, "Arkab.exe")

    if System.find_executable("zig") do
      args =
        ~w(-NoProfile -ExecutionPolicy Bypass -File) ++
          [script, "-OutputPath", output, "-Version", release.version]

      case System.cmd("powershell", args, stderr_to_stdout: true) do
        {out, 0} ->
          Mix.shell().info(out)

        {out, status} ->
          Mix.shell().error(
            "Arkab.exe was NOT built (build_launcher.ps1 exited #{status}). " <>
              "The release starts through Arkab.bat; no installer can be packed from it.\n" <>
              out
          )
      end
    else
      Mix.shell().info([
        :yellow,
        "Skipping Arkab.exe: zig is not on PATH. The release starts through ",
        "Arkab.bat; no installer can be packed from it.",
        :reset
      ])
    end
  end

  # Velopack's own library, for the launcher's "download and install". Not
  # in the repository: the release workflow fetches a pinned, checksummed
  # copy to rel/windows/velopack_libc.dll. A build without it has no update
  # button and is otherwise the same program.
  defp velopack_dll(release) do
    source = Path.join([__DIR__, "rel", "windows", "velopack_libc.dll"])
    if File.exists?(source), do: File.cp!(source, Path.join(release.path, "velopack_libc.dll"))
  end

  # Erlang's Windows runtime is linked against Microsoft's C runtime, which
  # Erlang's own installer puts on the machine and a release does not: on a
  # PC that never had it, erl.exe stops with "VCRUNTIME140.dll was not
  # found". The three DLLs are Microsoft's to redistribute beside a program
  # that needs them (NOTICE), so they are copied from the build machine -
  # which has them, or it could not have built this - to stand beside
  # erl.exe. Where they are already there, nothing is copied.
  defp c_runtime(release) do
    system32 = Path.join(System.get_env("SystemRoot") || "C:/Windows", "System32")

    for bin <- Path.wildcard(Path.join(release.path, "erts-*/bin")),
        name <- ~w(vcruntime140.dll vcruntime140_1.dll msvcp140.dll),
        source = Path.join(system32, name),
        target = Path.join(bin, name),
        File.exists?(source) and not File.exists?(target) do
      File.cp!(source, target)
    end
  end

  # Erlang's Windows build ships its debugger symbols and a debug build of
  # the emulator: about a third of the download, for a debugger nobody will
  # attach in a playing hall.
  defp without_debug_files(release) do
    for pattern <- ["erts-*/bin/*.pdb", "erts-*/bin/beam.debug.*"],
        file <- Path.wildcard(Path.join(release.path, pattern)) do
      File.rm!(file)
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      # Security tooling, wired into `precommit` and CI; never part of a release.
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16", only: [:dev, :test], runtime: false},
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
      {:lazy_html, ">= 0.1.0", only: :test},
      # The bridge-protocol contract (priv/contracts) is checked against JSON
      # Schema in the tests; nothing of it ships.
      {:ex_json_schema, "~> 0.11.5", only: :test}
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
      precommit: [
        "compile --warnings-as-errors",
        "format",
        "deps.audit",
        "hex.audit",
        "sobelow --config",
        "test"
      ]
    ]
  end
end
