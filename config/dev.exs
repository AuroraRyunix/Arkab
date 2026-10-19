import Config

config :arkab, ArkabWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4050],
  debug_errors: true,
  server: true
