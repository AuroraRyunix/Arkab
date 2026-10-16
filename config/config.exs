import Config

# Run on its own, Arkab is the bridge. (As Alnasl's dependency this file is
# not read at all, and nothing starts: see `Arkab.Application`.)
config :arkab, role: :bridge

# Where the bridge keeps its queue, its servers and its captures.
config :arkab, data_dir: Path.expand("../data", __DIR__)

config :arkab, ArkabWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: ArkabWeb.ErrorHTML], layout: false],
  pubsub_server: Arkab.PubSub,
  live_view: [signing_salt: "aRk4bL1v"]

config :logger, :default_formatter, format: "$time [$level] $message\n"

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
