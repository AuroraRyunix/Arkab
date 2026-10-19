defmodule ArkabWeb.HostGuard do
  @moduledoc """
  Which host names the status page answers to, for the HTTP request (a plug)
  and for the LiveView socket (`check_origin`).

  The page has no login. What kept a stranger out of its controls was the
  address, and by default the bridge listens on the hall's network (0.0.0.0),
  where it is meant to be looked at. The origin check Phoenix does by default
  compares the page's origin with the single host "localhost", which locked
  every other machine out of the live socket (the page froze on its first
  render), and a web page in a browser on the hall's network can reach it by
  DNS rebinding anyway: its own name is pointed at the bridge after the page
  has loaded, and the browser then considers the bridge the same origin. The
  name the browser asked for is the one thing such a page cannot choose, so:

    * `call/2` answers 403 to any request whose `Host` header is not on the
      list;
    * `origin_allowed?/1` gives the socket the same list as its `check_origin`.

  The list is `localhost`, `127.0.0.1`, `::1`, the host in the endpoint's `url`,
  the names in `ARKAB_HOSTS` (for a bridge that answers to a DNS name of the
  hall's router), and, unless `ARKAB_LISTEN=local` (`config :arkab, listen:
  :lan`), this machine's own host name (also with `.local`) and every address of
  its interfaces. `config :arkab, extra_hosts: [...]` is where those names live.

  What a visitor may *do* is another question, answered in
  `ArkabWeb.StatusLive`: the controls work from this machine only.
  """

  @behaviour Plug

  import Plug.Conn

  @loopback ~w(localhost 127.0.0.1 ::1)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if host_allowed?(conn.host) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(403, "Forbidden")
      |> halt()
    end
  end

  @doc "`check_origin` callback: the origin's host must be one the bridge answers to."
  @spec origin_allowed?(URI.t()) :: boolean()
  def origin_allowed?(%URI{host: host}), do: host_allowed?(host)

  @doc "Whether `host` (as in a Host header, port already removed) is one of ours."
  @spec host_allowed?(String.t() | nil) :: boolean()
  def host_allowed?(host) when is_binary(host), do: normalize(host) in allowed_hosts()
  def host_allowed?(_host), do: false

  @doc "Every host name the bridge answers to right now."
  @spec allowed_hosts() :: [String.t()]
  def allowed_hosts do
    configured = Application.get_env(:arkab, ArkabWeb.Endpoint, [])[:url][:host]
    extra = Application.get_env(:arkab, :extra_hosts, [])
    base = @loopback ++ List.wrap(configured) ++ extra
    base = if Application.get_env(:arkab, :listen) == :lan, do: base ++ lan_hosts(), else: base
    Enum.map(base, &normalize/1)
  end

  @doc "This machine's own names and interface addresses (the hall's network)."
  @spec lan_hosts() :: [String.t()]
  def lan_hosts do
    names =
      case :inet.gethostname() do
        {:ok, name} -> [to_string(name), to_string(name) <> ".local"]
        _ -> []
      end

    addresses =
      case :inet.getifaddrs() do
        {:ok, interfaces} ->
          for {_name, opts} <- interfaces,
              {:addr, addr} <- opts,
              do: addr |> :inet.ntoa() |> to_string()

        _ ->
          []
      end

    names ++ addresses
  end

  # Host headers carry brackets around an IPv6 address, case does not matter,
  # and a fully qualified name may end in a dot.
  defp normalize(host) do
    host |> String.trim("[") |> String.trim("]") |> String.trim_trailing(".") |> String.downcase()
  end
end
