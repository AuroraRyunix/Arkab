defmodule ArkabWeb.PinTest do
  @moduledoc """
  The remote PIN: set from the bridge itself, unlocks a browser elsewhere for
  twelve hours, throttled, void the moment it is changed or removed, and
  never a way past the rule that only this machine sets it.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Arkab.{Bridge, FakeServer}
  alias ArkabWeb.{Local, Pin}

  @endpoint ArkabWeb.Endpoint

  setup do
    dir = Path.join(System.tmp_dir!(), "arkab-pin-#{System.unique_integer([:positive])}")
    Application.put_env(:arkab, :pin_iterations, 1_000)
    start_supervised!({Bridge, data_dir: dir, name: "hall", sources: [], web: true})
    Pin.Throttle.reset()

    on_exit(fn ->
      Application.delete_env(:arkab, :pin_iterations)
      File.rm_rf!(dir)
    end)

    :ok
  end

  # Who is asking: another computer, a loopback proxy (tailscale serve), or
  # this machine.
  defp as(conn, :lan),
    do: Plug.Test.put_peer_data(conn, %{address: {192, 168, 1, 23}, port: 50_000, ssl_cert: nil})

  defp as(conn, :proxied), do: Plug.Conn.put_req_header(conn, "x-forwarded-for", "100.64.0.7")
  defp as(conn, :local), do: conn

  # The unlock form, filled in: returns the answer, with the session in it.
  defp unlock(kind, pin, session \\ nil) do
    base = if session, do: recycle(session), else: build_conn()
    page = base |> as(kind) |> get("/unlock")
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html_response(page, 200))

    page |> recycle() |> as(kind) |> post("/unlock", %{"_csrf_token" => token, "pin" => pin})
  end

  defp open(session, kind), do: session |> recycle() |> as(kind) |> live("/")

  defp joined_server do
    server = FakeServer.start(codes: ["P"])
    {:ok, _id} = Bridge.join(FakeServer.link(server, "P"))
    [%{id: id}] = Bridge.Store.servers()
    id
  end

  describe "the PIN itself" do
    test "stores a salted hash, never the PIN, and checks it" do
      refute Pin.set?()
      assert :ok = Pin.set("2468")
      assert Pin.set?()

      stored = Bridge.Store.get("remote_pin")
      refute inspect(stored) =~ "2468"
      assert byte_size(Base.decode64!(stored["salt"])) == 16
      assert stored["iter"] == 1_000

      assert {:ok, %{"gen" => gen}} = Pin.attempt("2468", :peer)
      assert gen == stored["gen"]
      assert {:error, :wrong} = Pin.attempt("2469", :peer)
    end

    test "at least four characters" do
      assert {:error, :too_short} = Pin.set("123")
      refute Pin.set?()
      assert :ok = Pin.set("1234")
      assert :ok = Pin.set("a pass phrase is fine too")
    end

    test "without a PIN there is nothing to guess" do
      assert {:error, :none} = Pin.attempt("1234", :peer)
    end

    test "five wrong tries lock a peer out, even for the right PIN; another peer is untouched" do
      Pin.set("2468")
      for _ <- 1..5, do: assert({:error, :wrong} = Pin.attempt("0000", :peer))
      assert {:error, {:locked, seconds}} = Pin.attempt("2468", :peer)
      assert seconds in 299..300
      assert {:ok, _grant} = Pin.attempt("2468", :other)
    end

    test "fifty guesses at once still get five tries between them" do
      Pin.set("2468")

      answers =
        1..50
        |> Task.async_stream(fn _ -> Pin.attempt("0000", :peer) end, max_concurrency: 50)
        |> Enum.map(fn {:ok, answer} -> answer end)

      assert Enum.count(answers, &(&1 == {:error, :wrong})) == 5

      assert Enum.all?(
               answers -- List.duplicate({:error, :wrong}, 5),
               &match?({:error, {:locked, _}}, &1)
             )
    end

    test "a right PIN clears the count" do
      Pin.set("2468")
      for _ <- 1..4, do: Pin.attempt("0000", :peer)
      assert {:ok, _} = Pin.attempt("2468", :peer)
      for _ <- 1..4, do: Pin.attempt("0000", :peer)
      assert {:ok, _} = Pin.attempt("2468", :peer)
    end

    test "changing or removing the PIN voids every grant" do
      Pin.set("2468")
      {:ok, grant} = Pin.attempt("2468", :peer)
      assert Pin.valid_grant?(grant)

      Pin.set("1357")
      refute Pin.valid_grant?(grant)

      {:ok, grant} = Pin.attempt("1357", :peer)
      assert Pin.valid_grant?(grant)
      Pin.remove()
      refute Pin.valid_grant?(grant)
      refute Pin.set?()

      Pin.set("1357")
      refute Pin.valid_grant?(grant)
    end

    test "an expired or forged grant is no grant" do
      Pin.set("2468")
      {:ok, %{"gen" => gen}} = Pin.attempt("2468", :peer)
      now = System.os_time(:second)
      refute Pin.valid_grant?(%{"gen" => gen, "until" => now - 1})
      refute Pin.valid_grant?(%{"gen" => gen, "until" => now + 10 * 24 * 3600})
      refute Pin.valid_grant?(%{"gen" => gen + 1, "until" => now + 60})
      refute Pin.valid_grant?(%{"admin" => true})
      refute Pin.valid_grant?(nil)
    end

    test "may_change? is local, or a good grant" do
      Pin.set("2468")
      {:ok, grant} = Pin.attempt("2468", :peer)
      assert Local.may_change?(true, nil)
      assert Local.may_change?(false, grant)
      refute Local.may_change?(false, nil)
      refute Local.may_change?(false, %{"gen" => 99, "until" => System.os_time(:second) + 5})
    end
  end

  describe "from another computer" do
    test "without a PIN, read-only stays read-only and offers no door" do
      {:ok, view, _html} = live(as(build_conn(), :lan), "/")
      assert has_element?(view, "#read-only")
      refute has_element?(view, "#enter-pin")
      refute has_element?(view, "#pin")
      refute has_element?(view, "#join-form")

      conn = unlock(:lan, "2468")
      assert html_response(conn, 403) =~ "no remote PIN"
    end

    test "with a PIN, the banner offers Enter PIN, and the page is still read-only" do
      Pin.set("2468")
      {:ok, view, _html} = live(as(build_conn(), :lan), "/")
      assert has_element?(view, "#read-only #enter-pin")
      refute has_element?(view, "#join-form")
      refute has_element?(view, "#pin")
    end

    test "a wrong PIN is refused and gives nothing" do
      Pin.set("2468")
      conn = unlock(:lan, "1111")
      assert html_response(conn, 403) =~ "not the PIN"
      {:ok, view, _html} = open(conn, :lan)
      assert has_element?(view, "#read-only")
      refute has_element?(view, "#join-form")
    end

    test "the right PIN gives the controls, and an event then works" do
      id = joined_server()
      Pin.set("2468")

      conn = unlock(:lan, "2468")
      assert redirected_to(conn) == "/"

      {:ok, view, _html} = open(conn, :lan)
      refute has_element?(view, "#read-only")
      assert has_element?(view, "#unlocked")
      assert has_element?(view, "#join-form")
      assert has_element?(view, "#remove-#{id}")
      refute has_element?(view, "#pin"), "the PIN is managed from the bridge only"

      render_click(view, "remove", %{"id" => to_string(id)})
      assert Bridge.Store.servers() == []
    end

    test "locking again takes the grant away" do
      Pin.set("2468")
      conn = unlock(:lan, "2468")
      conn = conn |> recycle() |> as(:lan) |> get("/lock")
      assert redirected_to(conn) == "/"
      {:ok, view, _html} = open(conn, :lan)
      assert has_element?(view, "#read-only")
    end

    test "events sent by hand are refused without a grant" do
      id = joined_server()
      Pin.set("2468")
      {:ok, view, _html} = live(as(build_conn(), :lan), "/")

      render_click(view, "remove", %{"id" => to_string(id)})
      render_click(view, "update_check", %{"on" => "false"})
      render_submit(view, "pin_set", %{"pin" => "9999"})
      render_click(view, "pin_remove", %{})

      assert [%{id: ^id}] = Bridge.Store.servers()
      assert Bridge.Store.get("update_check") == nil
      assert {:ok, _} = Pin.attempt("2468", :peer), "the PIN was not touched"
    end

    test "a grant does not let a browser set, change or remove the PIN" do
      Pin.set("2468")
      conn = unlock(:lan, "2468")
      {:ok, view, _html} = open(conn, :lan)

      render_submit(view, "pin_set", %{"pin" => "9999"})
      render_click(view, "pin_remove", %{})

      assert Pin.set?()
      assert {:ok, _} = Pin.attempt("2468", :peer)
      assert {:error, :wrong} = Pin.attempt("9999", :peer)
    end

    test "changing the PIN locks an open page at its next event" do
      id = joined_server()
      Pin.set("2468")
      conn = unlock(:lan, "2468")
      {:ok, view, _html} = open(conn, :lan)
      assert has_element?(view, "#join-form")

      Pin.set("1357")
      render_click(view, "remove", %{"id" => to_string(id)})

      assert [%{id: ^id}] = Bridge.Store.servers()
      refute has_element?(view, "#join-form")
      assert has_element?(view, "#read-only")
    end

    test "removing the PIN locks the grant out too" do
      Pin.set("2468")
      conn = unlock(:lan, "2468")
      Pin.remove()
      {:ok, view, _html} = open(conn, :lan)
      assert has_element?(view, "#read-only")
      refute has_element?(view, "#join-form")
    end

    test "five wrong tries in the page lock the address out, the right PIN too" do
      Pin.set("2468")
      for _ <- 1..5, do: unlock(:lan, "0000")
      conn = unlock(:lan, "2468")
      assert html_response(conn, 429) =~ "Too many wrong tries"
      {:ok, view, _html} = open(conn, :lan)
      assert has_element?(view, "#read-only")
    end

    test "a post without the CSRF token is refused" do
      Pin.set("2468")

      assert_error_sent 403, fn ->
        build_conn()
        |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
        |> as(:lan)
        |> post("/unlock", %{"pin" => "2468"})
      end
    end
  end

  describe "behind a proxy on loopback" do
    test "is not this machine, but can unlock with the PIN" do
      id = joined_server()
      Pin.set("2468")

      {:ok, view, _html} = live(as(build_conn(), :proxied), "/")
      assert has_element?(view, "#read-only #enter-pin")
      refute has_element?(view, "#join-form")
      refute has_element?(view, "#pin")

      conn = unlock(:proxied, "2468")
      assert redirected_to(conn) == "/"
      {:ok, view, _html} = open(conn, :proxied)
      assert has_element?(view, "#remove-#{id}")
      refute has_element?(view, "#pin"), "still not local: no PIN management"
    end
  end

  describe "this machine" do
    test "manages the PIN from the page" do
      {:ok, view, _html} = live(build_conn(), "/")
      assert has_element?(view, "#pin")
      refute has_element?(view, "#pin-remove")

      view |> form("#pin-form", %{pin: "12"}) |> render_submit()
      assert has_element?(view, "#pin-message.error")
      refute Pin.set?()

      view |> form("#pin-form", %{pin: "2468"}) |> render_submit()
      assert has_element?(view, "#pin-message.ok")
      assert Pin.set?()
      assert has_element?(view, "#pin-remove")

      view |> element("#pin-remove") |> render_click()
      refute Pin.set?()
    end

    test "never sees the Enter PIN door, with or without a PIN" do
      Pin.set("2468")
      {:ok, view, _html} = live(build_conn(), "/")
      refute has_element?(view, "#read-only")
      refute has_element?(view, "#enter-pin")
    end
  end
end
