defmodule ArkabWeb do
  @moduledoc """
  The bridge's one page: who it is joined to, what waits, which ports and
  boards, and the field that joins it to a server. Nothing else, on
  purpose; the games are Alnasl's.
  """

  def static_paths, do: ~w(app.js app.css)

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
