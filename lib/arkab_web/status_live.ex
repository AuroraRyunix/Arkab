defmodule ArkabWeb.StatusLive do
  @moduledoc """
  The bridge's page. Read once a second, because what it shows - a line up
  or down, events waiting - changes on its own. In English or Dutch
  (`ArkabWeb.Words`); the help is `ArkabWeb.HelpLive`.
  """

  use ArkabWeb, :live_view

  import ArkabWeb.Components, only: [foot: 1, logo: 1]

  alias ArkabWeb.Words

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(1_000, :refresh)
    {:ok, socket |> assign(joining?: false, message: nil) |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("join", %{"link" => link}, socket) do
    {:noreply,
     socket
     |> assign(joining?: true, message: nil)
     |> start_async(:join, fn -> Arkab.Bridge.join(link) end)}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id), do: Arkab.Bridge.remove(id)
    {:noreply, load(socket)}
  end

  @impl true
  def handle_async(:join, {:ok, {:ok, _id}}, socket),
    do:
      {:noreply,
       socket
       |> assign(joining?: false, message: {:ok, Words.t(socket.assigns.locale, :joined)})
       |> load()}

  def handle_async(:join, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       assign(socket, joining?: false, message: {:error, words(reason, socket.assigns.locale)})}

  def handle_async(:join, {:exit, _reason}, socket),
    do:
      {:noreply,
       assign(socket,
         joining?: false,
         message: {:error, words(:unreachable, socket.assigns.locale)}
       )}

  defp words(:not_a_link, locale), do: Words.t(locale, :err_not_a_link)
  defp words(:used_or_expired, locale), do: Words.t(locale, :err_used_or_expired)
  defp words(:unreachable, locale), do: Words.t(locale, :err_unreachable)
  defp words(:version, locale), do: Words.t(locale, :err_version)
  defp words(_other, locale), do: Words.t(locale, :err_other)

  defp load(socket) do
    status =
      try do
        Arkab.Bridge.status()
      catch
        :exit, _reason ->
          %{name: "", servers: [], waiting: 0, ports: [], boards: [], recording?: false}
      end

    assign(socket, status: status)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="bridge">
      <header>
        <h1><.logo /> Arkab <span class="name">{@status.name}</span></h1>
        
        <p class="note">{Words.t(@locale, :tagline)}</p>
      </header>
      
      <section id="servers">
        <h2>{Words.t(@locale, :servers)}</h2>
        
        <ul :if={@status.servers != []} id="server-list">
          <li :for={server <- @status.servers} id={"server-#{server.id}"}>
            <span
              class={["dot", if(server.up?, do: "up", else: "down")]}
              title={
                if(server.up?,
                  do: Words.t(@locale, :connected),
                  else: Words.t(@locale, :not_connected)
                )
              }
            ></span> <span class="server-name">{server.name}</span>
            <span :if={!server.up? && server.error} class="note">{server.error}</span>
            <button
              id={"remove-#{server.id}"}
              type="button"
              phx-click="remove"
              phx-value-id={server.id}
              data-confirm={Words.t(@locale, :confirm_remove)}
            >
              {Words.t(@locale, :remove)}
            </button>
          </li>
        </ul>
        
        <p :if={@status.servers == []} class="note" id="no-servers">
          {Words.t(@locale, :no_servers)}
        </p>
        
        <p id="waiting">{Words.t(@locale, :waiting)} <strong>{@status.waiting}</strong></p>
      </section>
      
      <section id="join">
        <h2>{Words.t(@locale, :join_title)}</h2>
        
        <form id="join-form" phx-submit="join">
          <input
            id="join-link"
            type="text"
            name="link"
            placeholder="https://server/join/K7Q-4MD"
            autocomplete="off"
          />
          <button id="join-button" type="submit" disabled={@joining?}>
            {if @joining?, do: Words.t(@locale, :joining), else: Words.t(@locale, :join)}
          </button>
          
          <button id="scan-button" type="button" phx-hook="Scan" hidden>
            {Words.t(@locale, :scan)}
          </button>
        </form>
         <video id="scan-video" phx-update="ignore" hidden playsinline></video>
        <p :if={@message} id="join-message" class={elem(@message, 0)}>{elem(@message, 1)}</p>
        
        <p class="note">{Words.t(@locale, :join_hint)}</p>
      </section>
      
      <section id="ports">
        <h2>{Words.t(@locale, :ports_title)}</h2>
        
        <p :if={@status.ports == []} class="note">{Words.t(@locale, :no_ports)}</p>
        
        <ul id="port-list">
          <li :for={port <- @status.ports} id={"port-#{port.port}"}>
            <span class="mono">{port.port}</span> <span class="note">{port.description}</span>
            <span :if={!port.read?} class="note">{Words.t(@locale, :not_read)}</span>
            <ul>
              <li
                :for={board <- Enum.filter(@status.boards, &(&1.port == port.port))}
                id={"board-#{board.id}"}
              >
                <span class={["dot", if(board.connected?, do: "up", else: "down")]}></span> {if board.address,
                  do: Words.t(@locale, :board_no, n: board.address),
                  else: Words.t(@locale, :board)}
                <span :if={board.info[:serial]} class="mono">
                  {Words.t(@locale, :serial)} {board.info[:serial]}
                </span>
              </li>
            </ul>
          </li>
        </ul>
        
        <p class="note">
          {Words.t(@locale, :recording)} {if @status.recording?,
            do: Words.t(@locale, :on),
            else: Words.t(@locale, :off)}
        </p>
      </section>
       <.foot locale={@locale} page={:status} />
    </main>
    """
  end
end
