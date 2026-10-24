defmodule ArkabWeb.Router do
  use ArkabWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArkabWeb.Layouts, :root}
    plug ArkabWeb.Locale
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ArkabWeb do
    pipe_through :browser
    get "/lang/:code", LangController, :set
    get "/unlock", PinController, :show
    post "/unlock", PinController, :unlock
    get "/lock", PinController, :lock

    live_session :default, on_mount: {ArkabWeb.Locale, :default} do
      live "/", StatusLive, :index
      live "/help", HelpLive, :index
    end
  end
end
