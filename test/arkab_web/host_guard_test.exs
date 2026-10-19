defmodule ArkabWeb.HostGuardTest do
  @moduledoc """
  `ArkabWeb.HostGuard`: the page answers to its own names only, so a web
  page that renamed the bridge (DNS rebinding) gets a 403 and no socket.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias ArkabWeb.HostGuard

  @endpoint ArkabWeb.Endpoint

  setup do
    dir = Path.join(System.tmp_dir!(), "arkab-host-#{System.unique_integer([:positive])}")
    start_supervised!({Arkab.Bridge, data_dir: dir, name: "hall", sources: [], web: true})
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  defp ask(host, path \\ "/help") do
    build_conn() |> Map.put(:host, host) |> get(path)
  end

  test "this machine's own names are answered" do
    for host <- ["localhost", "127.0.0.1", "LOCALHOST"] do
      assert ask(host).status == 200, host
    end
  end

  test "a name the page chose is a 403, on every route" do
    for path <- ["/", "/help", "/lang/nl"] do
      assert ask("attacker.example", path).status == 403, path
    end
  end

  test "the machine's own name and addresses need the page to be open to the network" do
    {:ok, name} = :inet.gethostname()
    refute HostGuard.host_allowed?(to_string(name))

    Application.put_env(:arkab, :listen, :lan)
    on_exit(fn -> Application.delete_env(:arkab, :listen) end)

    assert HostGuard.host_allowed?(to_string(name))
    assert ask(to_string(name)).status == 200
    refute HostGuard.host_allowed?("attacker.example")
    assert ask("attacker.example").status == 403
  end

  test "the socket's origin goes through the same list" do
    assert HostGuard.origin_allowed?(URI.parse("http://localhost:4050"))
    assert HostGuard.origin_allowed?(URI.parse("http://127.0.0.1:4050"))
    refute HostGuard.origin_allowed?(URI.parse("http://attacker.example:4050"))
    refute HostGuard.origin_allowed?(URI.parse("null"))
  end

  test "a name listed in extra_hosts (ARKAB_HOSTS) is answered" do
    Application.put_env(:arkab, :extra_hosts, ["www.example.com", "bridge.hall.lan"])
    on_exit(fn -> Application.put_env(:arkab, :extra_hosts, ["www.example.com"]) end)
    assert ask("bridge.hall.lan").status == 200
  end
end
