defmodule ArkabWeb.StatusLive do
  @moduledoc """
  The bridge's page. Read once a second, because what it shows - a line up
  or down, events waiting - changes on its own. In English or Dutch
  (`ArkabWeb.Words`); the help is `ArkabWeb.HelpLive`.

  Anyone on the hall's network may look; only the machine itself may touch,
  or a browser unlocked with the remote PIN (`ArkabWeb.Local.may_change?/2`,
  `ArkabWeb.Pin`). The peer is read from the socket when the page mounts
  (`local?`), the PIN grant from the session, and every event that changes
  something asks again on the server, whatever the page drew: a button that is
  not drawn is still an event anybody can send. The PIN itself is set, changed
  and removed from this machine only (`local?`, never the grant).
  """

  use ArkabWeb, :live_view

  import ArkabWeb.Components, only: [foot: 1, logo: 1]

  alias Arkab.{Autostart, Updates}
  alias ArkabWeb.{Local, Pin, Words}

  # Everything that changes something. The rest of the events are none.
  @changing ~w(join update later update_check check_now autostart remove)
  # The PIN's own: this machine only, a grant is not enough.
  @local_only ~w(pin_set pin_remove)

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      :timer.send_interval(1_000, :refresh)
      Phoenix.PubSub.subscribe(Arkab.PubSub, Updates.topic())
    end

    {:ok,
     socket
     |> assign(
       joining?: false,
       message: nil,
       update_message: nil,
       checking?: false,
       local?: Local.local_socket?(socket),
       grant: session[Pin.session_key()],
       pin_message: nil
     )
     |> assign_access()
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, socket |> assign_access() |> load()}
  def handle_info(:update_changed, socket), do: {:noreply, load(socket)}
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event(event, params, socket) when event in @changing or event in @local_only do
    socket = assign_access(socket)

    allowed? =
      if event in @local_only, do: socket.assigns.local?, else: socket.assigns.may_change?

    if allowed?, do: change(event, params, socket), else: {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp change("join", %{"link" => link}, socket) do
    {:noreply,
     socket
     |> assign(joining?: true, message: nil)
     |> start_async(:join, fn -> Arkab.Bridge.join(link) end)}
  end

  defp change("update", _params, socket) do
    case Updates.apply() do
      :ok -> {:noreply, assign(socket, update_message: {:ok, :update_started})}
      {:error, _reason} -> {:noreply, assign(socket, update_message: nil) |> load()}
    end
  end

  defp change("later", %{"version" => version}, socket) do
    Updates.later(version)
    {:noreply, load(socket)}
  end

  defp change("update_check", params, socket) do
    Updates.put_mode(if(params["on"] == "true", do: "ask", else: "never"))
    {:noreply, load(socket)}
  end

  defp change("check_now", _params, socket) do
    {:noreply,
     socket
     |> assign(checking?: true, update_message: nil)
     |> start_async(:check, fn -> Updates.Checker.check_now() end)}
  end

  defp change("autostart", params, socket) do
    case Autostart.set(params["on"] == "true") do
      :ok -> {:noreply, load(socket)}
      {:error, _words} -> {:noreply, assign(socket, update_message: {:error, :autostart_failed})}
    end
  end

  defp change("remove", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id), do: Arkab.Bridge.remove(id)
    {:noreply, load(socket)}
  end

  defp change("pin_set", %{"pin" => pin}, socket) do
    message =
      case Pin.set(pin) do
        :ok -> {:ok, :pin_saved}
        {:error, _short} -> {:error, :pin_short}
      end

    {:noreply, socket |> assign(pin_message: message) |> assign_access()}
  end

  defp change("pin_remove", _params, socket) do
    Pin.remove()
    {:noreply, socket |> assign(pin_message: {:ok, :pin_removed}) |> assign_access()}
  end

  @impl true
  def handle_async(:check, {:ok, answer}, socket) do
    message =
      case answer do
        {:ok, _info} -> nil
        :current -> {:ok, :up_to_date}
        :error -> {:error, :check_failed}
      end

    {:noreply, socket |> assign(checking?: false, update_message: message) |> load()}
  end

  def handle_async(:check, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, checking?: false, update_message: {:error, :check_failed})}

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
  defp words(:elsewhere, locale), do: Words.t(locale, :err_elsewhere)
  defp words(_other, locale), do: Words.t(locale, :err_other)

  defp load(socket) do
    status =
      try do
        Arkab.Bridge.status()
      catch
        :exit, _reason ->
          %{
            name: "",
            servers: [],
            waiting: 0,
            store: %{dropped: 0, error: nil},
            ports: [],
            boards: [],
            recording?: false
          }
      end

    assign(socket,
      status: status,
      notice: Updates.notice(),
      install_kind: Updates.install_kind(),
      update_mode: Updates.mode(),
      last_update: Updates.last_result(),
      autostart?: Autostart.supported?() and Autostart.enabled?()
    )
  end

  # Asked again on every tick and every change: a PIN that was changed or a
  # grant that ran out takes the buttons away from a page that is still open.
  defp assign_access(socket) do
    may_change? = Local.may_change?(socket.assigns.local?, socket.assigns.grant)
    pin_set? = Pin.set?()

    assign(socket,
      may_change?: may_change?,
      pin_offered?: not may_change? and pin_set?,
      pin_set?: pin_set?,
      unlocked?: not socket.assigns.local? and Pin.valid_grant?(socket.assigns.grant)
    )
  end

  defp megabytes(bytes), do: :erlang.float_to_binary(bytes / 1_048_576, decimals: 1)

  @impl true
  def render(assigns) do
    ~H"""
    <main id="bridge">
      <header>
        <h1><.logo /> Arkab <span class="name">{@status.name}</span></h1>

        <p class="note">{Words.t(@locale, :tagline)}</p>
      </header>

      <section :if={!@may_change?} id="read-only">
        <h2>{Words.t(@locale, :read_only_title)}</h2>

        <p>{Words.t(@locale, :read_only)}</p>

        <p :if={@pin_offered?}>{Words.t(@locale, :read_only_pin)}</p>

        <p :if={@pin_offered?}>
          <a id="enter-pin" href="/unlock">{Words.t(@locale, :enter_pin)}</a>
        </p>
      </section>

      <section :if={@unlocked?} id="unlocked">
        <p class="note">{Words.t(@locale, :unlocked_note)}</p>

        <p><a id="lock-link" href="/lock">{Words.t(@locale, :lock_again)}</a></p>
      </section>

      <section :if={@notice} id="update">
        <h2>{Words.t(@locale, :update_available, version: @notice.version)}</h2>

        <p :if={@notice.size} class="note">
          {Words.t(@locale, :update_size, mb: megabytes(@notice.size))}
        </p>

        <p :if={@install_kind != :manual} class="note">{Words.t(@locale, :update_cost)}</p>

        <p :if={@install_kind == :manual && !@notice.no_build} class="note">
          {Words.t(@locale, :update_manual)}
        </p>

        <p :if={@notice.no_build} class="note">{Words.t(@locale, :update_no_build)}</p>

        <form :if={@may_change?} id="update-form" phx-submit="update">
          <button :if={@install_kind != :manual} id="update-button" type="submit">
            {Words.t(@locale, :update_install)}
          </button>

          <a
            :if={@install_kind == :manual && !@notice.no_build}
            id="update-link"
            href={@notice.url}
            rel="noopener"
          >
            {Words.t(@locale, :update_releases)}
          </a>

          <button
            id="update-later"
            type="button"
            phx-click="later"
            phx-value-version={@notice.version}
          >
            {Words.t(@locale, :update_later)}
          </button>
        </form>
      </section>

      <p
        :if={match?({:failed, _, _}, @last_update)}
        id="update-failed"
        class="error"
      >
        {Words.t(@locale, :update_failed,
          version: elem(@last_update, 1),
          why: elem(@last_update, 2)
        )}
      </p>

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
              :if={@may_change?}
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

        <p :if={@status.store.dropped > 0} id="store-dropped" class="error">
          {Words.t(@locale, :store_dropped, n: @status.store.dropped)}
        </p>

        <p :if={@status.store.error} id="store-error" class="error">
          {Words.t(@locale, :store_error, why: @status.store.error)}
        </p>
      </section>

      <section :if={@may_change?} id="join">
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

      <section id="program">
        <h2>{Words.t(@locale, :program_title)}</h2>

        <p class="note">
          {Words.t(@locale, :version)} <span class="mono">{Updates.current_version()}</span>
        </p>

        <p :if={@may_change?}>
          <label>
            <input
              id="update-check"
              type="checkbox"
              checked={@update_mode == "ask"}
              phx-click="update_check"
              phx-value-on={to_string(@update_mode != "ask")}
            /> {Words.t(@locale, :update_check)}
          </label>
        </p>

        <p :if={@may_change? and Autostart.supported?()}>
          <label>
            <input
              id="autostart"
              type="checkbox"
              checked={@autostart?}
              phx-click="autostart"
              phx-value-on={to_string(!@autostart?)}
            /> {Words.t(@locale, :autostart)}
          </label>
        </p>

        <p :if={@may_change?}>
          <button id="check-now" type="button" phx-click="check_now" disabled={@checking?}>
            {if @checking?, do: Words.t(@locale, :checking), else: Words.t(@locale, :check_now)}
          </button>

          <span :if={@update_message} id="update-message" class={elem(@update_message, 0)}>
            {Words.t(@locale, elem(@update_message, 1))}
          </span>
        </p>

        <div :if={@local?} id="pin">
          <h3>{Words.t(@locale, :pin_title)}</h3>

          <p class="note">
            {if @pin_set?,
              do: Words.t(@locale, :pin_is_set),
              else: Words.t(@locale, :pin_is_not_set)}
          </p>

          <form id="pin-form" phx-submit="pin_set">
            <input
              id="pin-input"
              type="password"
              name="pin"
              autocomplete="new-password"
              placeholder={Words.t(@locale, :pin_new)}
              aria-label={Words.t(@locale, :pin_new)}
            /> <button id="pin-save" type="submit">{Words.t(@locale, :pin_save)}</button>
            <button :if={@pin_set?} id="pin-remove" type="button" phx-click="pin_remove">
              {Words.t(@locale, :pin_remove)}
            </button>
          </form>

          <p :if={@pin_message} id="pin-message" class={elem(@pin_message, 0)}>
            {Words.t(@locale, elem(@pin_message, 1))}
          </p>

          <p class="note">{Words.t(@locale, :pin_hint)}</p>

          <p class="note">{Words.t(@locale, :pin_plain)}</p>
        </div>
      </section>
      <.foot locale={@locale} page={:status} />
    </main>
    """
  end
end
