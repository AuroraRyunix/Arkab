defmodule Arkab.JoinTest do
  @moduledoc """
  The one step: a link in, a server joined. The bridge finds the address
  and the key by itself; a link used up, expired or pointing at nothing is
  said in words, and nothing is stored.
  """

  use ExUnit.Case, async: false

  alias Arkab.Bridge
  alias Arkab.Bridge.{Join, Store}
  alias Arkab.FakeServer

  setup do
    dir = Path.join(System.tmp_dir!(), "arkab-join-#{System.unique_integer([:positive])}")
    start_supervised!({Bridge, data_dir: dir, name: "hall", sources: []})
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  test "a join link is a link to /join/<code> on http or https" do
    assert {:ok, %URI{host: "alnasl.zerotwo.cloud"}} =
             Join.parse(" https://alnasl.zerotwo.cloud/join/K7Q-4MD ")

    assert {:ok, _} = Join.parse("http://192.168.1.20:4040/join/K7Q-4MD")
    assert Join.parse("https://alnasl.zerotwo.cloud/setup") == {:error, :not_a_link}
    assert Join.parse("K7Q-4MD") == {:error, :not_a_link}
    assert Join.parse("ftp://x/join/K7Q") == {:error, :not_a_link}
    assert Bridge.join("nonsense") == {:error, :not_a_link}
  end

  test "pasting the link joins the server: the key is fetched and kept, never typed" do
    server = FakeServer.start()
    assert {:ok, id} = Bridge.join(FakeServer.link(server))

    assert [%{id: ^id, name: "fake", owner?: true, key: key, url: url}] = Store.servers()
    assert key == FakeServer.get(server, :key)
    assert url == "ws://127.0.0.1:#{server.port}/bridge/link"

    # The server was told who joined.
    assert %{"bridge" => bridge, "name" => "hall", "v" => 1} = FakeServer.get(server, :bridge)
    assert bridge == Bridge.id()
  end

  test "a code works once" do
    server = FakeServer.start()
    assert {:ok, _id} = Bridge.join(FakeServer.link(server))
    assert Bridge.join(FakeServer.link(server)) == {:error, :used_or_expired}
    assert length(Store.servers()) == 1
  end

  test "a server that does not answer is said to be so, and nothing is stored" do
    server = FakeServer.start()
    FakeServer.down(server)
    assert Bridge.join(FakeServer.link(server)) == {:error, :unreachable}
    assert Store.servers() == []
  end
end
