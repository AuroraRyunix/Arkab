defmodule ArkabWeb.Locale do
  @moduledoc """
  Which language the page speaks. The visitor's choice (the `locale` of the
  session, set by `/lang/:code`) wins; until there is one, the browser's
  `Accept-Language`; failing both, English. The result is put in the session
  too, so the LiveView, which sees only the session, speaks the same language.
  """

  import Plug.Conn

  alias ArkabWeb.Words

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      case get_session(conn, "locale") do
        locale when locale in ["en", "nl"] -> locale
        _none -> from_browser(conn)
      end

    conn |> put_session("locale", locale) |> assign(:locale, locale)
  end

  @doc "`on_mount` for the LiveViews: the session's language."
  def on_mount(:default, _params, session, socket) do
    locale = if session["locale"] in Words.locales(), do: session["locale"], else: "en"
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp from_browser(conn) do
    header = conn |> get_req_header("accept-language") |> List.first() || ""

    if header |> String.downcase() |> String.trim_leading() |> String.starts_with?("nl"),
      do: "nl",
      else: "en"
  end
end
