defmodule ArkabWeb.StatusLive do
  @moduledoc """
  The bridge's page. Read once a second, because what it shows - a line up
  or down, events waiting - changes on its own.
  """

  use ArkabWeb, :live_view

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
    do: {:noreply, socket |> assign(joining?: false, message: {:ok, "Joined."}) |> load()}

  def handle_async(:join, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, joining?: false, message: {:error, words(reason)})}

  def handle_async(:join, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, joining?: false, message: {:error, words(:unreachable)})}

  defp words(:not_a_link),
    do: "That is not a join link. It looks like https://server/join/K7Q-4MD."

  defp words(:used_or_expired),
    do: "That link is used up or expired. Ask the server for a new one."

  defp words(:unreachable), do: "The server in that link does not answer from here."

  defp words(:version),
    do: "That server speaks another version of the link. Update one of the two."

  defp words(_other), do: "That address answered, but not like a server."

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
        <h1>Arkab <span class="name">{@status.name}</span></h1>
        <p class="note">Reads the boards in this hall and sends them on.</p>
      </header>

      <section id="servers">
        <h2>Servers</h2>
        <ul :if={@status.servers != []} id="server-list">
          <li :for={server <- @status.servers} id={"server-#{server.id}"}>
            <span
              class={["dot", if(server.up?, do: "up", else: "down")]}
              title={if(server.up?, do: "connected", else: "not connected")}
            ></span>
            <span class="server-name">{server.name}</span>
            <span :if={!server.up? && server.error} class="note">{server.error}</span>
            <button
              id={"remove-#{server.id}"}
              type="button"
              phx-click="remove"
              phx-value-id={server.id}
              data-confirm="Leave this server? It stops getting these boards."
            >
              Remove
            </button>
          </li>
        </ul>
        <p :if={@status.servers == []} class="note" id="no-servers">Joined to no server yet.</p>
        <p id="waiting">Events waiting: <strong>{@status.waiting}</strong></p>
      </section>

      <section id="join">
        <h2>Join a server</h2>
        <form id="join-form" phx-submit="join">
          <input
            id="join-link"
            type="text"
            name="link"
            placeholder="https://server/join/K7Q-4MD"
            autocomplete="off"
          />
          <button id="join-button" type="submit" disabled={@joining?}>
            {if @joining?, do: "Joining...", else: "Join"}
          </button>
          <button id="scan-button" type="button" phx-hook="Scan" hidden>Scan</button>
        </form>
        <video id="scan-video" phx-update="ignore" hidden playsinline></video>
        <p :if={@message} id="join-message" class={elem(@message, 0)}>{elem(@message, 1)}</p>
        <p class="note">
          On the server: Setup, Add a bridge. Paste or scan the link it shows; that is all.
        </p>
      </section>

      <section id="ports">
        <h2>Ports and boards</h2>
        <p :if={@status.ports == []} class="note">No ports.</p>
        <ul id="port-list">
          <li :for={port <- @status.ports} id={"port-#{port.port}"}>
            <span class="mono">{port.port}</span>
            <span class="note">{port.description}</span>
            <span :if={!port.read?} class="note">(not read)</span>
            <ul>
              <li
                :for={board <- Enum.filter(@status.boards, &(&1.port == port.port))}
                id={"board-#{board.id}"}
              >
                <span class={["dot", if(board.connected?, do: "up", else: "down")]}></span>
                {if board.address, do: "Board no. #{board.address}", else: "Board"}
                <span :if={board.info[:serial]} class="mono">serial {board.info[:serial]}</span>
              </li>
            </ul>
          </li>
        </ul>
        <p class="note">Recording: {if @status.recording?, do: "on", else: "off"}</p>
      </section>
    </main>
    """
  end
end
