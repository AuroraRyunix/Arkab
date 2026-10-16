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
end
