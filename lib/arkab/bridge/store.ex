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

  ## When the queue cannot be kept

  A server that is joined and never comes back holds every row for ever, and
  the boards say a clock reading a second. So the queue has a ceiling.
  Above `@soft_cap` rows the oldest clock readings go first (a clock is
  restated by the next one; nobody replays last Tuesday's seconds), and only
  when clocks alone cannot bring it down, at `@hard_cap`, the oldest of
  anything - positions and results included. Every throw-away is counted and
  logged, and the page says so (`health/1`).

  A write the disk refuses is the same story, not a crash: the batch is
  thrown away, counted, logged and shown, and the bridge goes on reading
  boards. Before, the process died on the refused write, took the boards and
  the endpoint with it, and came back to a full disk to do it again until the
  supervisor gave up.

  A file that will not open (garbled, truncated, not a database) is moved
  aside with the time in its name, and the bridge starts with a fresh one. The
  servers it knew are gone with it, so the bridge has to be joined again; the
  old file stays where it was for anyone who wants to look.
  """

  use GenServer

  require Logger

  alias Exqlite.Sqlite3

  # Rows. About 150 bytes each, so these are roughly 30 MB and 150 MB.
  @soft_cap 200_000
  @hard_cap 1_000_000

  # Which rows are clock readings (`Arkab.Protocol.event_fields/1`'s "clk").
  @clock_only ~s(e LIKE '%"k":"clk"%')

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

  @doc """
  What went wrong with keeping the queue since the bridge started:
  `%{dropped: events thrown away, error: why the last write failed or nil}`.
  """
  def health(server \\ __MODULE__), do: GenServer.call(server, :health)

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
    db = open_db(path)

    state = %{
      db: db,
      batch: [],
      listeners: Keyword.get(opts, :listeners),
      joined?: count_servers(db) > 0,
      soft_cap: Keyword.get(opts, :soft_cap, @soft_cap),
      hard_cap: Keyword.get(opts, :hard_cap, @hard_cap),
      rows: scalar(db, "SELECT COUNT(*) FROM events", []),
      dropped: 0,
      error: nil
    }

    {:ok, rearm(state)}
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
    # A disk that will not take the update leaves the server where it was; it
    # is sent the same events again, which it recognises by their numbers.
    state =
      try do
        query(state.db, "UPDATE servers SET acked = MAX(acked, ?2) WHERE id = ?1", [id, seq])
        pruned(state)
      rescue
        error -> failed(state, 0, error)
      end

    {:reply, :ok, state}
  end

  def handle_call(:waiting, _from, state),
    do: {:reply, scalar(state.db, "SELECT COUNT(*) FROM events", []), state}

  def handle_call(:last_seq, _from, state), do: {:reply, last(state.db), state}

  def handle_call(:health, _from, state),
    do: {:reply, %{dropped: state.dropped, error: state.error}, state}

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

    state = pruned(state)
    {:reply, {:ok, id}, %{state | joined?: true}}
  end

  def handle_call({:remove_server, id}, _from, state) do
    query(state.db, "DELETE FROM servers WHERE id = ?1", [id])
    state = pruned(state)
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
    batch = Enum.reverse(state.batch)

    try do
      insert!(state.db, batch)
    rescue
      error -> failed(%{state | batch: []}, length(batch), error)
    else
      :ok ->
        # The links are told there is more; each fetches its own share.
        if state.listeners do
          Registry.dispatch(state.listeners, :queued, fn entries ->
            for {pid, _} <- entries, do: send(pid, :queued)
          end)
        end

        trim(%{state | batch: [], rows: state.rows + length(batch), error: nil})
    end
  end

  # One transaction. Anything the disk refuses raises, and the transaction is
  # rolled back on the way, so a half-written batch is never in the file.
  defp insert!(db, batch) do
    ok!(Sqlite3.execute(db, "BEGIN IMMEDIATE"))

    try do
      {:ok, stmt} =
        Sqlite3.prepare(db, "INSERT INTO events (board, t, e, at) VALUES (?1, ?2, ?3, ?4)")

      try do
        for {id, t, at, fields} <- batch do
          at = if at, do: Jason.encode!(Tuple.to_list(at))
          ok!(Sqlite3.bind(stmt, [id, t, Jason.encode!(fields), at]))
          :done = Sqlite3.step(db, stmt)
          ok!(Sqlite3.reset(stmt))
        end
      after
        Sqlite3.release(db, stmt)
      end

      ok!(Sqlite3.execute(db, "COMMIT"))
    rescue
      error ->
        Sqlite3.execute(db, "ROLLBACK")
        reraise error, __STACKTRACE__
    end
  end

  defp ok!(:ok), do: :ok
  defp ok!(other), do: raise("sqlite: #{inspect(other)}")

  # A batch (or an update) the disk refused: thrown away, counted, said.
  defp failed(state, lost, error) do
    why = Exception.message(error)

    Logger.error(
      "arkab queue: the write failed (#{why}); #{lost} event(s) thrown away. " <>
        "The bridge goes on reading the boards; look at the disk."
    )

    %{state | dropped: state.dropped + lost, error: why}
  end

  # --- the ceiling -------------------------------------------------------------

  # Over the soft cap by a little (so not once per batch): the oldest clock
  # readings go. Over the hard cap still: the oldest rows of any kind.
  defp trim(%{rows: rows, trim_at: at} = state) when rows <= at, do: state

  defp trim(state) do
    total = scalar(state.db, "SELECT COUNT(*) FROM events", [])
    clocks = drop_oldest(state.db, total - state.soft_cap, @clock_only)
    others = drop_oldest(state.db, total - clocks - state.hard_cap, "1")
    lost = clocks + others

    if lost > 0 do
      Logger.warning(
        "arkab queue: more than #{state.soft_cap} events are waiting, so #{lost} of the oldest " <>
          "were thrown away (#{clocks} clock readings, #{others} others). A joined server " <>
          "that never comes back is the usual reason: remove it."
      )
    end

    rearm(%{state | rows: total - lost, dropped: state.dropped + lost})
  rescue
    error -> failed(rearm(state), 0, error)
  end

  # Deletes up to `n` of the oldest rows that match `where`; how many went.
  defp drop_oldest(_db, n, _where) when n <= 0, do: 0

  defp drop_oldest(db, n, where) do
    query(
      db,
      "DELETE FROM events WHERE seq IN (SELECT seq FROM events WHERE #{where} ORDER BY seq LIMIT ?1)",
      [n]
    )

    {:ok, changes} = Sqlite3.changes(db)
    changes
  end

  # When to look at the ceiling next: a margin above the soft cap, or above
  # where a trim that could not reach it left things.
  defp rearm(state) do
    margin = max(div(state.soft_cap, 20), 1)
    Map.put(state, :trim_at, max(state.soft_cap, state.rows) + margin)
  end

  # After rows may have left the queue because every server has them.
  defp pruned(state) do
    gone = prune(state.db)
    rearm(%{state | rows: max(state.rows - gone, 0)})
  end

  # Gone: what every server has. Nobody joined: nobody waits for anything.
  # How many rows that was.
  defp prune(db) do
    case scalar(db, "SELECT MIN(acked) FROM servers", []) do
      nil -> query(db, "DELETE FROM events", [])
      low -> query(db, "DELETE FROM events WHERE seq <= ?1", [low])
    end

    {:ok, changes} = Sqlite3.changes(db)
    changes
  end

  # --- the file ----------------------------------------------------------------

  # Opens the queue file; a file that will not open, or does not check out as a
  # database, is moved aside (with the time in its name) and a fresh one is
  # started in its place.
  defp open_db(path) do
    case try_open(path) do
      {:ok, db} ->
        db

      {:error, reason} ->
        moved = move_aside(path)

        Logger.error(
          "arkab queue: #{path} could not be opened (#{reason}). It was moved to #{moved}, and " <>
            "the bridge starts with a fresh, empty one. The servers it knew are gone from this " <>
            "bridge: join them again with new links."
        )

        {:ok, db} = try_open(path)
        db
    end
  end

  defp try_open(path) do
    {:ok, db} = Sqlite3.open(path)

    try do
      ok!(Sqlite3.execute(db, "PRAGMA journal_mode = WAL"))
      ok!(Sqlite3.execute(db, "PRAGMA synchronous = FULL"))
      Sqlite3.set_busy_timeout(db, 5_000)
      for sql <- @schema, do: ok!(Sqlite3.execute(db, sql))

      case query(db, "PRAGMA quick_check", []) do
        [["ok"]] -> {:ok, db}
        other -> raise "quick_check says #{inspect(other)}"
      end
    rescue
      error ->
        Sqlite3.close(db)
        {:error, Exception.message(error)}
    end
  end

  # arkab.db, and the -wal and -shm files that only make sense beside it.
  defp move_aside(path) do
    stamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    moved = "#{path}.corrupt-#{stamp}"

    for suffix <- ["", "-wal", "-shm"], File.exists?(path <> suffix) do
      File.rename!(path <> suffix, moved <> suffix)
    end

    moved
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
