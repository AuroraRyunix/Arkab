import Config

# The tests start the bridge's pieces themselves, each with a directory of
# its own; nothing starts with the application.
config :arkab, role: :library
# Phoenix's test connections ask for this host.
config :arkab, extra_hosts: ["www.example.com"]
config :arkab, data_dir: Path.expand("../tmp/test", __DIR__)

config :arkab, ArkabWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4052],
  secret_key_base: "zM0b3p9vQx4sN1kT8cR7yW2uH5jL6aE0fG3dS9qP1oI4uY7tR2eW5qA8sD1fG4hJ",
  server: false

config :logger, level: :warning

# The emulated loops answer at once; a real one is given a second.
config :arkab,
  loop_ping_window_ms: 30,
  loop_reply_ms: 80,
  loop_gap_ms: 5,
  loop_discover_ms: 400

# No launcher secret, no file in the data directory, no question to GitHub:
# the tests that want them start them themselves.
config :arkab, launcher_details: false, updates_timer: false
