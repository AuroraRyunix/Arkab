import Config

# Read when the bridge starts, also inside a release. Nothing is required:
# a bridge that has to be configured before it starts is a bridge that
# does not start in a playing hall.

# Where everything is kept: the queue, the servers' keys, the captures.
# `Arkab.DataHome` says where an installed copy keeps it and why that is
# never a folder an installer owns.
data_dir =
  cond do
    data = System.get_env("ARKAB_DATA") -> Path.expand(data)
    config_env() == :prod -> Path.expand(Arkab.DataHome.default())
    true -> nil
  end

if data_dir do
  # Refused before anything is written there: data inside a folder that an
  # update replaces or an uninstall removes is data with a date on it.
  if reason = Arkab.DataHome.refusal(data_dir) do
    raise Arkab.DataHome.refusal_message(data_dir, reason)
  end

  File.mkdir_p!(data_dir)
  config :arkab, data_dir: data_dir
end

# The status page, for the hall's network: anyone there may look, which is
# the point of it. ARKAB_LISTEN=local keeps it to this machine. Not 4040, so
# that a box can run an Alnasl beside it. PORT is what the Windows launcher
# and the service unit set; ARKAB_PORT wins when both are there.
if config_env() != :test do
  port = System.get_env("ARKAB_PORT") || System.get_env("PORT") || "4050"

  # `ArkabWeb.HostGuard` adds this machine's names and addresses to the hosts
  # it answers to only when the page is open to the hall's network. A bridge
  # reached by a DNS name (the router's, a reverse proxy's) lists it in
  # ARKAB_HOSTS, comma-separated.
  config :arkab,
    listen: if(System.get_env("ARKAB_LISTEN") == "local", do: :local, else: :lan),
    extra_hosts:
      "ARKAB_HOSTS"
      |> System.get_env("")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

  config :arkab, ArkabWeb.Endpoint,
    http: [
      ip: if(System.get_env("ARKAB_LISTEN") == "local", do: {127, 0, 0, 1}, else: {0, 0, 0, 0}),
      port: String.to_integer(port)
    ]
end
