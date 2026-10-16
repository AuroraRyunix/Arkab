defmodule Arkab.Bridge do
  @moduledoc """
  The bridge: the boards of one hall, read here and sent to one or more
  Alnasls over one outgoing WebSocket each. No tracker, no rounds, no
  logins.

      Arkab.Bridge
      ├─ registries                 boards by name, links by server, who wants to hear of new events
      ├─ Store                      the SQLite file: the queue, the servers, the settings
      ├─ Recorder                   the capture files, while recording is on
      ├─ Arkab.Drivers              the loops' buses (unless something here runs them already)
      ├─ Boards                     a Bridge.Board per board: its driver, and the queue it feeds
      ├─ Ports                      which ports, which boards; every command from a server
      ├─ Links                      a Bridge.Link per server: the socket, the acks, the commands
      └─ ArkabWeb.Endpoint          the status page (`web: true`)

  Options: `:data_dir` (required), `:web` (default false), `:name` (what
  the servers call it; the machine's name otherwise), `:sources` (the
  ports, replacing the stored ones - for tests), `:transport`, `:drivers`
  (start `Arkab.Drivers`; by default only when it is not running yet).
  """

  use Supervisor

  alias Arkab.Bridge.{Join, Link, Store}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    data = Keyword.fetch!(opts, :data_dir)
    File.mkdir_p!(data)
    :persistent_term.put({__MODULE__, :name}, Keyword.get(opts, :name) || hostname())

    drivers? = Keyword.get_lazy(opts, :drivers, fn -> not Arkab.Drivers.running?() end)

    children =
      [
        {Registry, keys: :unique, name: Arkab.Bridge.BoardRegistry},
        {Registry, keys: :unique, name: Arkab.Bridge.LinkRegistry},
        {Registry, keys: :duplicate, name: Arkab.Bridge.Listeners},
        {Phoenix.PubSub, name: Arkab.PubSub},
        {Store, path: Path.join(data, "arkab.db"), listeners: Arkab.Bridge.Listeners},
        {Arkab.Recorder,
         name: Arkab.Bridge.Recorder,
         root: Path.join(data, "captures"),
         cap: fn -> Store.get("capture_cap_mb", 500) * 1_000_000 end}
      ] ++
        if(drivers?, do: [Arkab.Drivers], else: []) ++
        [
          {DynamicSupervisor, name: Arkab.Bridge.Boards, strategy: :one_for_one},
          {Arkab.Bridge.Ports, Keyword.take(opts, [:sources, :transport])},
          {DynamicSupervisor, name: Arkab.Bridge.Links, strategy: :one_for_one},
          {Task, &start_links/0}
        ] ++ web(opts)

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp web(opts) do
    if Keyword.get(opts, :web, false) do
      ArkabWeb.Endpoint.ensure_secret(Path.join(Keyword.fetch!(opts, :data_dir), "secret"))
      [ArkabWeb.Endpoint]
    else
      []
    end
  end

  defp hostname do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end

  # --- what the bridge is ------------------------------------------------------

  @doc "This bridge's name for itself, made once and kept: the servers know it by this."
  def id do
    case Store.get("bridge_id") do
      nil ->
        id = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        Store.put("bridge_id", id)
        id

      id ->
        id
    end
  end

  @doc "What the servers call it."
  def name, do: :persistent_term.get({__MODULE__, :name}, "bridge")

  def software, do: "arkab " <> to_string(Application.spec(:arkab, :vsn))

  @doc "Whether the bridge writes capture files of its boards."
  def recording?, do: :persistent_term.get({__MODULE__, :recording}, true)

  def set_recording(on) when is_boolean(on) do
    Store.put("recording", on)
    :persistent_term.put({__MODULE__, :recording}, on)
  end

  # --- servers -----------------------------------------------------------------

  @doc """
  Joins the server of a join link (`Arkab.Bridge.Join`): `{:ok, server_id}`
  or `{:error, reason}`.
  """
  def join(link, req_options \\ []) do
    identity = %{
      "v" => Arkab.Protocol.version(),
      "bridge" => id(),
      "name" => name(),
      "software" => software()
    }

    with {:ok, attrs} <- Join.redeem(link, identity, req_options),
         {:ok, server_id} <- Store.add_server(attrs) do
      restart_link(server_id)
      {:ok, server_id}
    end
  end

  @doc """
  Leaves a server: it is told (when it can be reached now), and its place in
  the queue goes. Removing it on the server does the same from that end.
  """
  def remove(server_id) do
    case Link.whereis(server_id) do
      nil -> :ok
      pid -> Link.leave(pid)
    end

    stop_link(server_id)
    Store.remove_server(server_id)
  end

  @doc "Everything the status page shows."
  def status do
    ports = Arkab.Bridge.Ports.status()

    servers =
      for server <- Store.servers() do
        link = Link.whereis(server.id)
        info = if link, do: Link.info(link), else: %{up?: false, error: nil}
        Map.merge(Map.take(server, [:id, :url, :name, :owner?]), info)
      end

    Map.merge(ports, %{
      name: name(),
      servers: servers,
      waiting: Store.waiting()
    })
  end

  defp start_links do
    for server <- Store.servers(), do: restart_link(server.id)
    :ok
  end

  defp restart_link(server_id) do
    stop_link(server_id)

    DynamicSupervisor.start_child(Arkab.Bridge.Links, {Link, server_id: server_id})
  end

  defp stop_link(server_id) do
    case Link.whereis(server_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(Arkab.Bridge.Links, pid)
    end
  end
end
