defmodule ArkabWeb.HelpTest do
  @moduledoc """
  The help at /help and the two languages of the page: both render, the
  language is the visitor's (cookie, then browser), Dutch has every word
  English has, and the links between the two pages resolve.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias ArkabWeb.Words

  @endpoint ArkabWeb.Endpoint

  setup do
    dir = Path.join(System.tmp_dir!(), "arkab-help-#{System.unique_integer([:positive])}")
    start_supervised!({Arkab.Bridge, data_dir: dir, name: "hall", sources: [], web: true})
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  defp dutch(conn), do: conn |> get("/lang/nl") |> recycle()

  test "Dutch has every word English has" do
    assert Words.keys("nl") == Words.keys("en")
  end

  test "the help renders in English, with every section" do
    {:ok, view, html} = live(build_conn(), "/help")
    assert html =~ ~s(lang="en")

    for id <-
          ~w(help-what help-join help-remote help-servers help-queue help-ports help-update help-red) do
      assert has_element?(view, "##{id}")
    end

    assert has_element?(view, "#back-link[href='/']")
  end

  test "the help renders in Dutch once Dutch is chosen" do
    {:ok, view, html} = live(dutch(build_conn()), "/help")
    assert html =~ ~s(lang="nl")
    assert has_element?(view, "#help-join", "Aansluiten bij een server")

    for id <-
          ~w(help-what help-join help-remote help-servers help-queue help-ports help-update help-red) do
      assert has_element?(view, "##{id}")
    end
  end

  test "the page speaks Dutch too, and the language links work both ways" do
    {:ok, view, _html} = live(dutch(build_conn()), "/")
    assert has_element?(view, "#servers h2", "Servers")
    assert has_element?(view, "#join h2", "Aansluiten bij een server")
    assert has_element?(view, "#no-servers", "Nog bij geen enkele server")
    assert has_element?(view, "#help-link[href='/help']")
    assert has_element?(view, "#lang-en[href='/lang/en']")
    assert has_element?(view, "#lang-nl[aria-current=true]")

    conn = get(build_conn(), "/lang/en")
    assert redirected_to(conn) == "/"
    {:ok, view, _html} = live(recycle(conn), "/")
    assert has_element?(view, "#join h2", "Join a server")
  end

  test "the browser's language is used until a choice is made" do
    conn = build_conn() |> Plug.Conn.put_req_header("accept-language", "nl-BE,nl;q=0.9,en;q=0.5")
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#join h2", "Aansluiten bij een server")
  end

  test "an unknown language changes nothing" do
    conn = get(build_conn(), "/lang/xx")
    assert redirected_to(conn) == "/"
    {:ok, view, _html} = live(recycle(conn), "/")
    assert has_element?(view, "#join h2", "Join a server")
  end

  test "a join error is said in the visitor's language" do
    {:ok, view, _html} = live(dutch(build_conn()), "/")
    view |> form("#join-form", %{link: "not a link"}) |> render_submit()
    assert render_async(view, 5_000) =~ "geen aansluitlink"
  end
end
