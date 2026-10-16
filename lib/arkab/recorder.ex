defmodule Arkab.Recorder do
  @moduledoc """
  Writes captures (`Arkab.Capture`): a file per board, appended to, never
  in the way of the board that delivered.

  Files live in `<root>/board-<id>/<start time>.jsonl`. A file is closed and
  a new one begun at `rotate_bytes` (8 MB); when a `:cap` is given and all
  files together pass it, the oldest go.

  Options: `:name`; `:dir` - a fixed root and no cap (the tests); or
  `:root` - a function giving the root, asked whenever a file is opened -
  with `:cap`, a function giving the cap in bytes (asked as rarely, so a
  setting changed in a page applies to the next file). Alnasl runs one
  for its boards, the bridge one for its own.
  """

  use GenServer

  alias Arkab.Capture

  @rotate_bytes 8_000_000

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "Appends what board `board_id` delivered. Never blocks the caller and never fails it."
  def record(server \\ __MODULE__, board_id, event) do
    case Capture.line(event) do
      nil ->
        :ok

      fields ->
        GenServer.cast(
          server,
          {:record, board_id, Map.put(fields, "t", System.os_time(:millisecond))}
        )
    end
  end

  @doc "Closes the open files, so what was written can be read back."
  def flush(server \\ __MODULE__), do: GenServer.call(server, :flush, 15_000)

  @doc "Every capture file under `root`, newest first: `%{dir, name, path, size, modified}`."
  def files(root) do
    for dir <- ls(root),
        name <- ls(Path.join(root, dir)),
        String.ends_with?(name, ".jsonl"),
        path = Path.join([root, dir, name]),
        {:ok, stat} <- [File.stat(path, time: :posix)] do
      %{dir: dir, name: name, path: path, size: stat.size, modified: stat.mtime}
    end
    |> Enum.sort_by(&{&1.modified, &1.name}, :desc)
  end

  # Not `Path.wildcard/1`: on Windows a data directory may come with
  # backslashes, which a glob reads as escapes.
  defp ls(dir) do
    case File.ls(dir) do
      {:ok, names} -> names
      _error -> []
    end
  end

  # --- the process -------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       files: %{},
       rotate: Keyword.get(opts, :rotate_bytes, @rotate_bytes),
       dir: Keyword.get(opts, :dir),
       root: Keyword.get(opts, :root),
       cap: Keyword.get(opts, :cap)
     }}
  end

  @impl true
  def handle_cast({:record, board_id, fields}, state) do
    {:noreply, write(state, board_id, fields)}
  rescue
    _error -> {:noreply, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    for {_id, %{io: io}} <- state.files, do: File.close(io)
    {:reply, :ok, %{state | files: %{}}}
  end

  @impl true
  def terminate(_reason, state) do
    for {_id, %{io: io}} <- state.files, do: File.close(io)
    :ok
  end

  defp write(state, board_id, fields) do
    data = [Jason.encode_to_iodata!(fields), ?\n]
    size = IO.iodata_length(data)

    file =
      case state.files[board_id] do
        %{bytes: bytes} = file when bytes + size <= state.rotate ->
          file

        stale ->
          if stale, do: File.close(stale.io)
          open(state, board_id)
      end

    IO.binwrite(file.io, data)
    %{state | files: Map.put(state.files, board_id, %{file | bytes: file.bytes + size})}
  end

  defp root(%{dir: dir}) when is_binary(dir), do: dir
  defp root(%{root: fun}) when is_function(fun, 0), do: fun.()
  defp root(%{root: root}) when is_binary(root), do: root

  defp open(state, board_id) do
    dir = Path.join(root(state), "board-#{dir_name(board_id)}")
    File.mkdir_p!(dir)
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    path = unique(dir, stamp, 0)
    {:ok, io} = File.open(path, [:append, :binary, {:delayed_write, 64_000, 500}])
    enforce_cap(state)
    %{io: io, bytes: 0, path: path}
  end

  # A bridge's board is a port name ("COM3", "/dev/ttyUSB0/12"): a folder
  # name it can be, slashes and all, once they are not slashes.
  defp dir_name(id) when is_integer(id), do: Integer.to_string(id)
  defp dir_name(id), do: id |> to_string() |> String.replace(~r/[^A-Za-z0-9_.-]+/, "-")

  defp unique(dir, stamp, n) do
    path = Path.join(dir, if(n == 0, do: "#{stamp}.jsonl", else: "#{stamp}-#{n}.jsonl"))
    if File.exists?(path), do: unique(dir, stamp, n + 1), else: path
  end

  # The cap is on everything together; the oldest file goes first.
  defp enforce_cap(%{dir: nil, cap: cap} = state) when is_function(cap, 0) do
    cap = cap.()
    files = Enum.reverse(files(root(state)))
    total = files |> Enum.map(& &1.size) |> Enum.sum()

    Enum.reduce_while(files, total, fn file, total ->
      if total > cap do
        File.rm(file.path)
        {:cont, total - file.size}
      else
        {:halt, total}
      end
    end)

    :ok
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp enforce_cap(_state), do: :ok
end
