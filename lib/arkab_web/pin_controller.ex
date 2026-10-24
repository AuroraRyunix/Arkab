defmodule ArkabWeb.PinController do
  @moduledoc """
  `/unlock`: the remote PIN's door. A right PIN puts a grant into the
  session cookie (`ArkabWeb.Pin`), which the status page and every change on
  it check again on the server; `/lock` (a link, since only a request can clear the cookie, and locking
  one's own browser is not something to forge) takes it out. Plain requests
  and not LiveView events, because only a request can set a cookie.

  The throttle's key is the socket's peer address, never a header, so a
  guesser cannot change identity by writing one.
  """

  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  alias ArkabWeb.Pin

  plug :put_view, ArkabWeb.PinHTML

  def show(conn, _params), do: render(conn, :unlock, error: nil)

  def unlock(conn, %{"pin" => pin}) do
    case Pin.attempt(pin, peer(conn)) do
      {:ok, grant} ->
        conn |> put_session(Pin.session_key(), grant) |> redirect(to: "/")

      {:error, :wrong} ->
        conn |> put_status(403) |> render(:unlock, error: :wrong)

      {:error, {:locked, seconds}} ->
        conn |> put_status(429) |> render(:unlock, error: {:locked, div(seconds + 59, 60)})

      {:error, :none} ->
        conn |> put_status(403) |> render(:unlock, error: :none)
    end
  end

  def unlock(conn, _params), do: render(conn, :unlock, error: nil)

  def lock(conn, _params) do
    conn |> delete_session(Pin.session_key()) |> redirect(to: "/")
  end

  defp peer(conn), do: get_peer_data(conn).address
end
