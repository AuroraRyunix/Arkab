import Config

# Run on its own, Arkab is the bridge. (As Alnasl's dependency this file is
# not read at all, and nothing starts: see `Arkab.Application`.)
config :arkab, role: :bridge

# Where the bridge keeps its queue, its servers and its captures.
config :arkab, data_dir: Path.expand("../data", __DIR__)

config :arkab, ArkabWeb.Endpoint,
  url: [host: "localhost"],
  # The hosts the page answers to, not "localhost" alone (that locked every
  # other machine out of the live page) and not "anything" (DNS rebinding):
  # see `ArkabWeb.HostGuard`.
  check_origin: {ArkabWeb.HostGuard, :origin_allowed?, []},
  adapter: Bandit.PhoenixAdapter,
  # At a stop, open connections (the status page left open in a browser,
  # which is always) get three seconds to go, not Bandit's fifteen: fifteen
  # plus the database was most of the launcher's twenty, and it looked hung.
  http: [thousand_island_options: [shutdown_timeout: 3_000]],
  render_errors: [formats: [html: ArkabWeb.ErrorHTML], layout: false],
  pubsub_server: Arkab.PubSub,
  live_view: [signing_salt: "aRk4bL1v"]

config :logger, :default_formatter, format: "$time [$level] $message\n"

config :phoenix, :json_library, Jason

# The macOS release job compiles the SQLite library from source rather than
# fetching the precompiled one: that wants macOS 14, and the app promises 11.
# rel/macos/build_app.sh checks the result.
if System.get_env("EXQLITE_FORCE_BUILD") == "true" do
  config :exqlite, force_build: true
end

import_config "#{config_env()}.exs"
