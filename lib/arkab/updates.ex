defmodule Arkab.Updates do
  @moduledoc """
  Whether a newer Arkab is out, and - only when the arbiter says so -
  getting it.

  ## What it does by itself: one small question

  Every half hour (`Arkab.Updates.Checker`) the box asks GitHub for the
  latest release of this program: one request, a few kilobytes, with the
  ETag of the last answer so that "nothing changed" costs nothing. That is
  all it ever does unasked. Offline, a timeout and GitHub's rate limit are
  the same answer - nothing to show - and none of them is an error an
  arbiter has to read in the middle of a round.

  The question itself is a setting (`update_check`: `"ask"` or `"never"`,
  the status page). There is no third value: nothing is ever installed
  without a person saying yes.

  ## What it does when told to

  The hall may be on a phone's hotspot, and the boards are being read. So
  the notice says how big the download is before anything is fetched, and
  that the boards are not read while the update runs - about a minute. A
  bridge has no idea what a game is, so unlike the server it cannot refuse
  while one is in progress; the person who presses the button has to know.

  How it is applied depends on how the program was installed
  (`install_kind/0`):

    * `:velopack` - the Windows installer. This program stops with exit code
      90; `rel/windows/launcher.c`, which started it, sees that code,
      asks Velopack for the update, and starts the new version - or the old
      one again when anything at all went wrong.
    * `:systemd` - the Linux installer. This program writes the version it
      wants into a file; a systemd path unit sees the file and runs
      `/opt/arkab/update.sh` as root, which downloads, verifies, switches
      and restarts - or switches back.
    * `:manual` - a portable zip, `Arkab.app` on a Mac, a checkout. The
      notice says what to do: on a Mac, replace the app with the new one
      (docs/macos.md says why there is no button there yet).

  Neither the data directory nor anything in it is part of an update on
  either road; see `Arkab.DataHome`.
  """

  require Logger

  alias Arkab.Bridge.Store
  alias Arkab.Updates.Checker

  @repo "teapot-chess/Arkab"
  @latest_url "https://api.github.com/repos/#{@repo}/releases/latest"
  @releases_page "https://github.com/#{@repo}/releases"
  @user_agent "Arkab-UpdateCheck"

  # The code rel/windows/launcher.c waits for (ARKAB_UPDATE_EXIT_CODE
  # there). Two files that cannot share a constant share a comment.
  @update_exit_code 90

  @topic "updates"

  def topic, do: @topic
  def subscribe, do: Phoenix.PubSub.subscribe(Arkab.PubSub, @topic)
  def releases_page, do: @releases_page
  def update_exit_code, do: @update_exit_code

  @doc "The version that is running."
  def current_version, do: to_string(Application.spec(:arkab, :vsn))

  # --- the setting ---------------------------------------------------------------

  @doc "`\"ask\"` (look, and say so when there is one) or `\"never\"`."
  def mode do
    case setting("update_check") do
      "never" -> "never"
      _ask -> "ask"
    end
  end

  def put_mode(mode) when mode in ["ask", "never"] do
    Store.put("update_check", mode)
    broadcast()
  end

  @doc "\"Later\": the notice stays away until tomorrow, for this version."
  def later(version) when is_binary(version) do
    until = System.os_time(:second) + 20 * 3600
    Store.put("update_later", %{"version" => version, "until" => until})
    broadcast()
  end

  # The bridge's own little table of settings (`Arkab.Bridge.Store`). Not
  # running (a library, a test): nothing is set, and the defaults apply.
  defp setting(name) do
    Store.get(name)
  catch
    :exit, _reason -> nil
  end

  defp snoozed?(version) do
    case setting("update_later") do
      %{"version" => ^version, "until" => until} when is_integer(until) ->
        System.os_time(:second) < until

      _other ->
        false
    end
  end

  # --- what the site shows -------------------------------------------------------

  @doc """
  The newer release the checker knows of, or `nil`: `%{version, tag, url,
  size, asset}` with `size` the bytes of what this installation would
  download (`nil` when the release does not say).
  """
  def available, do: Checker.current()

  @doc "What the banner on every page shows, or `nil`: not when switched off, not when put off until later."
  def notice do
    with "ask" <- mode(),
         %{version: version} = info <- available(),
         false <- snoozed?(version) do
      info
    else
      _nothing -> nil
    end
  end

  @doc "Tells every open page to look at `notice/0` again."
  def broadcast, do: Phoenix.PubSub.broadcast(Arkab.PubSub, @topic, :update_changed)

  # --- asking GitHub -------------------------------------------------------------

  @doc """
  One conditional request for the latest release.

    * `{:ok, info, etag}` - a newer release than this program
    * `{:current, etag}` - reached GitHub; nothing newer
    * `:not_modified` - the answer of `etag` still stands
    * `:error` - offline, a timeout, a refusal, an answer that makes no
      sense. Logged at debug level and nowhere else.
  """
  def check(etag \\ nil) do
    headers =
      [{"accept", "application/vnd.github+json"}, {"user-agent", @user_agent}] ++
        if(etag, do: [{"if-none-match", etag}], else: [])

    # Not `Arkab.Http.request/1`: the tests' stand-in for the results
    # server would answer for GitHub.
    request =
      [url: @latest_url, headers: headers, receive_timeout: 10_000, retry: false]
      |> Keyword.merge(Application.get_env(:arkab, :updates_req_options, []))
      |> Req.new()

    case Req.get(request) do
      {:ok, %Req.Response{status: 200, body: %{"tag_name" => tag} = release} = response} ->
        read_release(tag, release, List.first(Req.Response.get_header(response, "etag")))

      {:ok, %Req.Response{status: 304}} ->
        :not_modified

      {:ok, %Req.Response{status: status}} ->
        # 404 is a repository without a release; 403 and 429 are the rate
        # limit every unauthenticated caller shares. None is news.
        Logger.debug("Update check: GitHub answered #{status}")
        :error

      {:error, reason} ->
        Logger.debug("Update check: #{inspect(reason)}")
        :error
    end
  end

  defp read_release(tag, release, etag) do
    with false <- release["draft"] == true or release["prerelease"] == true,
         {:ok, version} <- Version.parse(String.trim_leading(to_string(tag), "v")),
         {:ok, current} <- Version.parse(current_version()) do
      if Version.compare(version, current) == :gt do
        asset = asset_for(release["assets"], to_string(version))

        {:ok,
         %{
           version: to_string(version),
           tag: tag,
           url: release["html_url"] || "#{@releases_page}/tag/#{tag}",
           asset: asset && asset["name"],
           size: asset && asset["size"],
           no_build: no_build?(:os.type())
         }, etag}
      else
        {:current, etag}
      end
    else
      _unusable ->
        Logger.debug("Update check: a release that cannot be read (#{inspect(tag)})")
        :error
    end
  end

  # The file this installation would fetch, to say its size before asking.
  # Velopack may fetch a smaller delta instead; the full package is the
  # honest upper bound.
  defp asset_for(assets, version) when is_list(assets) do
    case asset_name(install_kind(), version) do
      nil -> nil
      name -> Enum.find(assets, &(is_map(&1) and &1["name"] == name and is_integer(&1["size"])))
    end
  end

  defp asset_for(_none, _version), do: nil

  @doc "The release asset an installation of `kind` downloads for `version`."
  def asset_name(:velopack, version), do: "#{Arkab.DataHome.pack_id()}-#{version}-full.nupkg"

  def asset_name(kind, version), do: asset_name(kind, version, :os.type())

  @doc false
  # The system as an argument, so that a test on one can ask about another.
  def asset_name(_kind, _version, {:win32, _}), do: "arkab-windows-x86_64-portable.zip"
  # Intel Macs have no build: `nil` names no file, so no link to a missing one.
  def asset_name(_kind, _version, {:unix, :darwin}) do
    if arch() == "aarch64", do: "arkab-macos-aarch64.zip"
  end

  def asset_name(_kind, _version, _unix), do: "arkab-linux-#{arch()}.tar.gz"

  @doc "True on an Intel Mac, for which no build is made."
  def no_build?(os), do: os == {:unix, :darwin} and arch() == "x86_64"

  @doc "`x86_64` or `aarch64`, as the release assets are named."
  def arch do
    architecture = to_string(:erlang.system_info(:system_architecture))

    cond do
      String.starts_with?(architecture, ["aarch64", "arm64"]) -> "aarch64"
      true -> "x86_64"
    end
  end

  # --- how this copy was installed -----------------------------------------------

  @doc """
  `:velopack`, `:systemd` or `:manual` - see the moduledoc. Both installers
  say who they are in `ARKAB_UPDATER` (the launcher, the unit); the layout
  on disk is checked as well, so that a copied folder or a hand-set variable
  does not offer a button that cannot work.
  """
  def install_kind do
    case Application.get_env(:arkab, :install_kind) do
      nil -> detect_kind()
      kind when kind in [:velopack, :systemd, :manual] -> kind
    end
  end

  defp detect_kind do
    case System.get_env("ARKAB_UPDATER") do
      "velopack" -> if velopack_layout?(), do: :velopack, else: :manual
      "systemd" -> if File.dir?(request_dir()), do: :systemd, else: :manual
      _none -> :manual
    end
  end

  # <install root>\current\ is the release, <install root>\Update.exe is
  # Velopack's. Anything else is not an installation Velopack can update.
  defp velopack_layout? do
    with root when is_binary(root) <- System.get_env("RELEASE_ROOT"),
         expanded = Path.expand(root),
         "current" <- Path.basename(expanded) do
      File.exists?(Path.join(Path.dirname(expanded), "Update.exe"))
    else
      _other -> false
    end
  end

  # --- applying ------------------------------------------------------------------

  @doc """
  Downloads and installs the update the checker found, and restarts.

    * `{:error, :nothing}` - no newer release is known
    * `{:error, :manual}` - this copy cannot update itself
    * `:ok` - under way. The program stops shortly; the page reconnects to
      whatever comes back.

  There is no "games in progress" refusal as there is on a server that
  tracks them: a bridge does not know what a game is. The page says what an
  update costs - the boards are not read while it runs - before it asks.
  """
  def apply do
    kind = install_kind()

    case {available(), kind} do
      {nil, _kind} ->
        {:error, :nothing}

      {_info, :manual} ->
        {:error, :manual}

      {info, kind} ->
        Logger.info("Update to #{info.version} requested")
        hand_over(kind, info)
    end
  end

  # Velopack: stop, cleanly - `System.stop/1` takes the supervision tree
  # down in order, so the queue is closed before any file is swapped -
  # and let the launcher do the rest. A moment first, so the page that asked
  # can still be told.
  defp hand_over(:velopack, _info) do
    stop = Application.get_env(:arkab, :updates_stop_fun, &System.stop/1)

    Task.start(fn ->
      Process.sleep(Application.get_env(:arkab, :updates_stop_delay, 500))
      stop.(@update_exit_code)
    end)

    :ok
  end

  # systemd: the version, in a file that a path unit watches. The file says
  # which version and nothing else; update.sh takes it for a version number
  # or not at all.
  defp hand_over(:systemd, info) do
    dir = request_dir()

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(Path.join(dir, "request"), info.version <> "\n") do
      :ok
    else
      {:error, reason} -> {:error, {:request, reason}}
    end
  end

  @doc "Where the Linux installation leaves its request for the updater."
  def request_dir, do: Path.join(Application.fetch_env!(:arkab, :data_dir), "update")

  @doc """
  What the Linux updater said about its last run, or `nil`: `{:ok,
  version}` or `{:failed, version, words}`. It writes one line to the file
  the unit names in `ARKAB_UPDATE_STATUS`.
  """
  def last_result do
    path =
      Application.get_env(:arkab, :update_status_file) || System.get_env("ARKAB_UPDATE_STATUS")

    with path when is_binary(path) <- path,
         {:ok, text} <- File.read(path),
         [word, version | rest] <- text |> String.trim() |> String.split(" ", parts: 3) do
      case word do
        "ok" -> {:ok, version}
        "failed" -> {:failed, version, List.first(rest) || ""}
        _other -> nil
      end
    else
      _none -> nil
    end
  end
end
