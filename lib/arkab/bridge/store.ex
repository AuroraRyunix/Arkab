defmodule Arkab.Bridge.Store do
  @moduledoc """
  The bridge's SQLite file: the queue of driver events, the servers it is
  joined to, and a few settings. One process owns the file; everything
  else asks it.

  ## The queue

  Every event a board delivers is a row, numbered (`seq`, never reused: an
  `AUTOINCREMENT` key, so a number a server has seen is never somebody
  else's after a restart), with the time it happened. It is written before
  it is sent; it is deleted when **every** joined server has acknowledged
  it. Each server has its own place (`acked`): a server that is down holds
  up nobody else, it only keeps the rows it has not had in the file.

  A bridge joined to nobody keeps nothing: nobody is waiting for it, and a
  server that joins later starts from the boards as they are now (it asks
  for them on joining), not from last week.

  Rows are written in batches: whatever arrived while the last batch was
  being written goes in one transaction, so a loop of twelve boards is a
  few fsyncs a second, not hundreds.

  The file is WAL with `synchronous = FULL`: "written first" has to survive
  the plug being pulled, as Alnasl's outbox does one level up.
  """

  use GenServer

  alias Exqlite.Sqlite3

  @schema [
    """
    CREATE TABLE IF NOT EXISTS events (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      board TEXT NOT NULL,
      t INTEGER NOT NULL,
      e TEXT NOT NULL,
      at TEXT
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS servers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      url TEXT NOT NULL,
      key TEXT NOT NULL,
      name TEXT,
      owner INTEGER NOT NULL DEFAULT 0,
      acked INTEGER NOT NULL DEFAULT 0,
      joined_at INTEGER NOT NULL
    )
    """,
    "CREATE TABLE IF NOT EXISTS settings (name TEXT PRIMARY KEY, value TEXT)"
  ]

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  # --- the queue ---------------------------------------------------------------

  @doc """
  Queues a driver event of board `id` that happened at `t`; `at` is `{speed,
  next}` for a played board, else `nil`. Returns at once.
  """
  def append(server \\ __MODULE__, id, t, at, event) do
    case Arkab.Protocol.event_fields(event) do
      nil -> :ok
      fields -> GenServer.cast(server, {:append, {id, t, at, fields}})
    end
  end

  @doc "Waits until what was appended before is in the file. For tests."
  def sync(server \\ __MODULE__), do: GenServer.call(server, :sync)

  @doc "Up to `limit` events after `after_seq`, oldest first, as they go on the wire."
  def pending(server \\ __MODULE__, after_seq, limit),
    do: GenServer.call(server, {:pending, after_seq, limit})

  @doc "Server `id` has everything up to `seq`. Rows every server has are deleted."
  def ack(server \\ __MODULE__, id, seq), do: GenServer.call(server, {:ack, id, seq})

  @doc "How many events are in the file: waiting for at least one server."
  def waiting(server \\ __MODULE__), do: GenServer.call(server, :waiting)

  @doc "The highest number given out so far (0 before the first)."
  def last_seq(server \\ __MODULE__), do: GenServer.call(server, :last_seq)

  # --- servers -----------------------------------------------------------------

  @doc "The servers, oldest first: `%{id, url, key, name, owner?, acked}`."
  def servers(server \\ __MODULE__), do: GenServer.call(server, :servers)

  def server(server \\ __MODULE__, id), do: Enum.find(servers(server), &(&1.id == id))

  @doc """
  Joins a server: `%{url, key, name, owner?}`. One already joined at that
  address gets the new key and keeps its place. A new one starts at the
  newest event: what happened before it joined is not its business.
  """
  def add_server(server \\ __MODULE__, attrs), do: GenServer.call(server, {:add_server, attrs})

  def remove_server(server \\ __MODULE__, id), do: GenServer.call(server, {:remove_server, id})

  # --- settings ----------------------------------------------------------------

  def get(name, default \\ nil), do: GenServer.call(__MODULE__, {:get, name, default})
  def put(name, value), do: GenServer.call(__MODULE__, {:put, name, value})

  # --- the process -------------------------------------------------------------

  @impl true
  def init(opts) do
    # So that a batch still in hand is written on the way out.
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :path)
    File.mkdir_p!(Path.dirname(path))
    {:ok, db} = Sqlite3.open(path)
    :ok = Sqlite3.execute(db, "PRAGMA journal_mode = WAL")
    :ok = Sqlite3.execute(db, "PRAGMA synchronous = FULL")
    Sqlite3.set_busy_timeout(db, 5_000)
    for sql <- @schema, do: :ok = Sqlite3.execute(db, sql)

    state = %{db: db, batch: [], listeners: Keyword.get(opts, :listeners)}
    {:ok, %{state | db: db} |> Map.put(:joined?, count_servers(db) > 0)}
  end

  @impl true
  def handle_cast({:append, _row}, %{joined?: false} = state), do: {:noreply, state}

  # Written when nothing else is waiting in the mailbox, or every 200 rows
  # under a load that never lets up.
  def handle_cast({:append, row}, state) do
    state = %{state | batch: [row | state.batch]}

    if length(state.batch) >= 200,
      do: {:noreply, write_batch(state)},
      else: {:noreply, state, 0}
  end

  @impl true
  def handle_info(:timeout, state), do: {:noreply, write_batch(state)}
  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_call(message, from, %{batch: [_ | _]} = state),
    do: handle_call(message, from, write_batch(state))

  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  def handle_call({:pending, after_seq, limit}, _from, state) do
    rows =
      query(
        state.db,
        "SELECT seq, board, t, e, at FROM events WHERE seq > ?1 ORDER BY seq LIMIT ?2",
        [after_seq, limit]
      )

    events =
      for [seq, board, t, e, at] <- rows do
        event = %{"s" => seq, "t" => t, "id" => board, "e" => Jason.decode!(e)}
        if at, do: Map.put(event, "at", Jason.decode!(at)), else: event
      end

    {:reply, events, state}
  end

  def handle_call({:ack, id, seq}, _from, state) do
    query(state.db, "UPDATE servers SET acked = MAX(acked, ?2) WHERE id = ?1", [id, seq])
    prune(state.db)
    {:reply, :ok, state}
  end

  def handle_call(:waiting, _from, state),
    do: {:reply, scalar(state.db, "SELECT COUNT(*) FROM events", []), state}

  def handle_call(:last_seq, _from, state), do: {:reply, last(state.db), state}

  def handle_call(:servers, _from, state) do
    servers =
      for [id, url, key, name, owner, acked] <-
            query(
              state.db,
              "SELECT id, url, key, name, owner, acked FROM servers ORDER BY id",
              []
            ) do
        %{id: id, url: url, key: key, name: name, owner?: owner == 1, acked: acked}
      end

    {:reply, servers, state}
  end

  def handle_call({:add_server, attrs}, _from, state) do
    owner = if attrs[:owner?], do: 1, else: 0

    id =
      case query(state.db, "SELECT id FROM servers WHERE url = ?1", [attrs.url]) do
        [[id] | _] ->
          query(state.db, "UPDATE servers SET key = ?2, name = ?3, owner = ?4 WHERE id = ?1", [
            id,
            attrs.key,
            attrs[:name],
            owner
          ])

          id

        [] ->
          query(
            state.db,
            "INSERT INTO servers (url, key, name, owner, acked, joined_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            [attrs.url, attrs.key, attrs[:name], owner, last(state.db), System.os_time(:second)]
          )

          {:ok, id} = Sqlite3.last_insert_rowid(state.db)
          id
      end

    prune(state.db)
    {:reply, {:ok, id}, %{state | joined?: true}}
  end

  def handle_call({:remove_server, id}, _from, state) do
    query(state.db, "DELETE FROM servers WHERE id = ?1", [id])
    prune(state.db)
    {:reply, :ok, %{state | joined?: count_servers(state.db) > 0}}
  end

  def handle_call({:get, name, default}, _from, state) do
    value =
      case query(state.db, "SELECT value FROM settings WHERE name = ?1", [name]) do
        [[json]] -> Jason.decode!(json)
        [] -> default
      end

    {:reply, value, state}
  end

  def handle_call({:put, name, value}, _from, state) do
    query(
      state.db,
      "INSERT INTO settings (name, value) VALUES (?1, ?2) ON CONFLICT(name) DO UPDATE SET value = excluded.value",
      [name, Jason.encode!(value)]
    )

    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    write_batch(state)
    Sqlite3.close(state.db)
  end

  # --- SQL ---------------------------------------------------------------------

  defp write_batch(%{batch: []} = state), do: state

  defp write_batch(state) do
    :ok = Sqlite3.execute(state.db, "BEGIN IMMEDIATE")

    {:ok, stmt} =
      Sqlite3.prepare(state.db, "INSERT INTO events (board, t, e, at) VALUES (?1, ?2, ?3, ?4)")

    for {id, t, at, fields} <- Enum.reverse(state.batch) do
      at = if at, do: Jason.encode!(Tuple.to_list(at))
      :ok = Sqlite3.bind(stmt, [id, t, Jason.encode!(fields), at])
      :done = Sqlite3.step(state.db, stmt)
      :ok = Sqlite3.reset(stmt)
    end

    Sqlite3.release(state.db, stmt)
    :ok = Sqlite3.execute(state.db, "COMMIT")

    # The links are told there is more; each fetches its own share.
    if state.listeners do
      Registry.dispatch(state.listeners, :queued, fn entries ->
        for {pid, _} <- entries, do: send(pid, :queued)
      end)
    end

    %{state | batch: []}
  end

  # Gone: what every server has. Nobody joined: nobody waits for anything.
  defp prune(db) do
    case scalar(db, "SELECT MIN(acked) FROM servers", []) do
      nil -> query(db, "DELETE FROM events", [])
      low -> query(db, "DELETE FROM events WHERE seq <= ?1", [low])
    end

    :ok
  end

  # The number the next event gets, less one. AUTOINCREMENT remembers it
  # in sqlite_sequence even when the queue is empty.
  defp last(db) do
    case query(db, "SELECT seq FROM sqlite_sequence WHERE name = 'events'", []) do
      [[seq]] -> seq
      [] -> 0
    end
  end

  defp count_servers(db), do: scalar(db, "SELECT COUNT(*) FROM servers", [])

  defp scalar(db, sql, args) do
    case query(db, sql, args) do
      [[value]] -> value
      _none -> nil
    end
  end

  defp query(db, sql, args) do
    {:ok, stmt} = Sqlite3.prepare(db, sql)

    try do
      :ok = Sqlite3.bind(stmt, args)
      {:ok, rows} = Sqlite3.fetch_all(db, stmt)
      rows
    after
      Sqlite3.release(db, stmt)
    end
  end
end
