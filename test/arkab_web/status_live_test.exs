defmodule ArkabWeb.StatusLiveTest do
  @moduledoc """
  The page: servers with their dot and Remove, what waits, the ports, and
  the one field. Plus the promise to Alnasl: as a library, nothing starts.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Arkab.{Bridge, FakeServer}

  @endpoint ArkabWeb.Endpoint

  setup do
    dir = Path.join(System.tmp_dir!(), "arkab-page-#{System.unique_integer([:positive])}")
    start_supervised!({Bridge, data_dir: dir, name: "hall", sources: [], web: true})
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  test "as a library, Arkab starts nothing of its own" do
    assert Application.get_env(:arkab, :role) == :library
    assert Supervisor.which_children(Arkab.Supervisor) == []
  end

  test "the join field says where in Alnasl the link comes from" do
    {:ok, view, _html} = live(build_conn(), "/")
    assert has_element?(view, "#join .note", "Halls, your hall, Bridges")
    assert has_element?(view, "#join .note", "Add a bridge")
  end

  test "the page joins a server from a pasted link, and removes it again" do
    server = FakeServer.start(codes: ["P"])
    {:ok, view, _html} = live(build_conn(), "/")

    assert has_element?(view, "#no-servers")
    assert has_element?(view, "#join-form")

    view |> form("#join-form", %{link: "not a link"}) |> render_submit()
    assert render_async(view, 5_000) =~ "not a join link"

    view |> form("#join-form", %{link: FakeServer.link(server, "P")}) |> render_submit()
    render_async(view, 5_000)
    send(view.pid, :refresh)
    assert has_element?(view, "#server-list li")

    [%{id: id}] = Arkab.Bridge.Store.servers()
    view |> element("#remove-#{id}") |> render_click()
    assert has_element?(view, "#no-servers")
  end

  test "a newer version is offered, with its size, and Later puts it away" do
    Arkab.Updates.Checker.put(%{
      version: "9.9.9",
      tag: "v9.9.9",
      url: "https://example.test/releases/tag/v9.9.9",
      asset: "arkab-linux-x86_64.tar.gz",
      size: 31_457_280,
      no_build: false
    })

    on_exit(fn -> :persistent_term.erase({Arkab.Updates.Checker, :available}) end)

    {:ok, view, _html} = live(build_conn(), "/")
    assert has_element?(view, "#update")
    assert render(view) =~ "9.9.9"
    assert render(view) =~ "30.0 MB"
    # A copy that is not installed updates by hand: a link, no button.
    assert has_element?(view, "#update-link")
    refute has_element?(view, "#update-button")

    view |> element("#update-later") |> render_click()
    refute has_element?(view, "#update")
  end

  describe "from another machine on the network" do
    defp lan(address \\ {192, 168, 1, 23}) do
      Plug.Test.put_peer_data(build_conn(), %{address: address, port: 50_000, ssl_cert: nil})
    end

    test "the page is a read-only view: the servers show, no control is drawn" do
      server = FakeServer.start(codes: ["P"])
      {:ok, _id} = Bridge.join(FakeServer.link(server, "P"))
      [%{id: id}] = Arkab.Bridge.Store.servers()

      {:ok, view, html} = live(lan(), "/")

      assert has_element?(view, "#read-only")
      assert html =~ "Read-only view"
      assert has_element?(view, "#server-#{id}")
      refute has_element?(view, "#remove-#{id}")
      refute has_element?(view, "#join-form")
      refute has_element?(view, "#check-now")
      refute has_element?(view, "#update-check")
    end

    test "it says so in Dutch too" do
      conn =
        lan()
        |> get("/lang/nl")
        |> recycle()
        |> Plug.Test.put_peer_data(%{address: {10, 0, 0, 4}, port: 1, ssl_cert: nil})

      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#read-only", "Alleen-lezen")
    end

    test "an event sent by hand changes nothing" do
      server = FakeServer.start(codes: ["P"])
      {:ok, _id} = Bridge.join(FakeServer.link(server, "P"))
      [%{id: id}] = Arkab.Bridge.Store.servers()
      other = FakeServer.start(codes: ["Q"])

      {:ok, view, _html} = live(lan(), "/")

      render_hook(view, "remove", %{"id" => to_string(id)})
      assert [%{id: ^id}] = Arkab.Bridge.Store.servers()

      render_hook(view, "join", %{"link" => FakeServer.link(other, "Q")})
      assert length(Arkab.Bridge.Store.servers()) == 1

      render_hook(view, "update", %{})
      render_hook(view, "autostart", %{"on" => "true"})
      assert Process.alive?(view.pid)
    end

    test "a loopback peer behind a proxy header is not this machine" do
      conn = build_conn() |> Plug.Conn.put_req_header("x-forwarded-for", "203.0.113.9")
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#read-only")
    end

    test "this machine gets the controls" do
      {:ok, view, _html} = live(build_conn(), "/")
      refute has_element?(view, "#read-only")
      assert has_element?(view, "#join-form")
    end
  end
end
