defmodule ArkabWeb.Local do
  @moduledoc """
  Whether a visitor is on this machine. The status page may be read from
  anywhere on the hall's network, but everything on it that changes something
  (joining and leaving servers, updating, the Windows start-up entry) works
  from the machine itself, or from a browser that was unlocked with the remote
  PIN (`may_change?/2`); the PIN itself is set from the machine only.

  "This machine" is the peer address of the connection, read from the socket
  (`get_connect_info(socket, :peer_data)`) and never from a header, and a
  loopback peer that arrives with a proxy header (`x-forwarded-for` and its
  kin) is somebody's reverse proxy talking, not this machine: the same rule as
  `ArkabWeb.Plugs.LauncherStats`. An SSH port forward to the bridge arrives
  from loopback without such a header and counts as local, which is how a bridge
  with no screen is managed from a laptop.
  """

  @proxy_headers ~w(x-forwarded-for forwarded x-real-ip cf-connecting-ip x-forwarded-host)

  @doc "Whether the peer (a `get_peer_data` map or nil) is loopback and the headers show no proxy."
  @spec local?(map() | nil, [{String.t(), String.t()}] | nil) :: boolean()
  def local?(peer_data, x_headers) do
    loopback?(peer_data) and not proxied?(x_headers)
  end

  @doc """
  Whether a visitor may change things: this machine, or a browser that holds
  a valid remote-PIN grant (`ArkabWeb.Pin`). The one question every change
  asks, in the LiveView and in the controllers; `local?` alone is for what
  must stay on this machine (setting the PIN, the launcher's Details).
  """
  @spec may_change?(boolean(), term()) :: boolean()
  def may_change?(true, _grant), do: true
  def may_change?(_local?, grant), do: ArkabWeb.Pin.valid_grant?(grant)

  @doc "The same, for a LiveView socket in `mount/3`."
  def local_socket?(socket) do
    local?(
      Phoenix.LiveView.get_connect_info(socket, :peer_data),
      Phoenix.LiveView.get_connect_info(socket, :x_headers)
    )
  end

  defp proxied?(nil), do: false

  defp proxied?(headers),
    do: Enum.any?(headers, fn {name, _value} -> String.downcase(name) in @proxy_headers end)

  defp loopback?(%{address: {127, _, _, _}}), do: true
  defp loopback?(%{address: {0, 0, 0, 0, 0, 0, 0, 1}}), do: true
  defp loopback?(%{address: {0, 0, 0, 0, 0, 0xFFFF, a, _}}), do: div(a, 256) == 127
  defp loopback?(_other), do: false
end
