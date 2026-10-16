import Config

# Read when the bridge starts, also inside a release. Nothing is required:
# a bridge that has to be configured before it starts is a bridge that
# does not start in a playing hall.

if data = System.get_env("ARKAB_DATA") do
  config :arkab, data_dir: Path.expand(data)
end

# The status page, for the hall's network: anyone there may look, which is
# the point of it. Not 4040, so that a box can run an Alnasl beside it.
if config_env() != :test do
  config :arkab, ArkabWeb.Endpoint,
    http: [
      ip: if(System.get_env("ARKAB_LISTEN") == "local", do: {127, 0, 0, 1}, else: {0, 0, 0, 0}),
      port: String.to_integer(System.get_env("ARKAB_PORT", "4050"))
    ]
end
