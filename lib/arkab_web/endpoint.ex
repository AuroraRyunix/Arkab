defmodule ArkabWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :arkab

  @session_options [store: :cookie, key: "_arkab_key", signing_salt: "q7Rb2kXa", same_site: "Lax"]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Phoenix's and LiveView's own scripts, as their packages ship them: no
  # build step for a page this size.
  plug Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.min.js)

  plug Plug.Static,
    at: "/vendor",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)

  # The favicon is the mark (`ArkabWeb.Logo`), made from priv/logo/mark.svg,
  # so it is answered here and not read from priv/static.
  plug :favicon

  plug Plug.Static, at: "/", from: :arkab, only: ArkabWeb.static_paths()

  # The launcher's Details panel - this machine, a secret, no proxy header, or
  # a 404. Before anything that logs, so a panel left open does not fill the
  # log it shows. See the plug.
  plug ArkabWeb.Plugs.LauncherStats

  plug Plug.RequestId
  plug Plug.Parsers, parsers: [:urlencoded], pass: ["*/*"]
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ArkabWeb.Router

  @doc false
  def favicon(%Plug.Conn{request_path: "/favicon.svg"} = conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("image/svg+xml")
    |> Plug.Conn.put_resp_header("cache-control", "public, max-age=3600")
    |> Plug.Conn.send_resp(200, ArkabWeb.Logo.favicon())
    |> Plug.Conn.halt()
  end

  def favicon(conn, _opts), do: conn

  @doc """
  The page's signing secret: made on the first start and kept in `path`,
  so a bridge needs no configuration and its cookies survive a restart.
  """
  def ensure_secret(path) do
    config = Application.get_env(:arkab, __MODULE__, [])

    unless config[:secret_key_base] do
      secret =
        case File.read(path) do
          {:ok, secret} when byte_size(secret) >= 64 ->
            secret

          _none ->
            secret = Base.encode64(:crypto.strong_rand_bytes(48))
            File.write!(path, secret)
            secret
        end

      Application.put_env(:arkab, __MODULE__, Keyword.put(config, :secret_key_base, secret))
    end

    :ok
  end
end
