defmodule ArkabWeb.Router do
  use ArkabWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArkabWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ArkabWeb do
    pipe_through :browser
    live "/", StatusLive, :index
  end
end
