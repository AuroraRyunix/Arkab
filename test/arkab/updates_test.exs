defmodule Arkab.UpdatesTest do
  @moduledoc """
  The update check and what may follow it: one question to a stand-in for
  GitHub, silence when there is no answer, nothing fetched without a yes,
  and nothing started that the page's user did not ask for.
  """

  use ExUnit.Case, async: false

  alias Arkab.Bridge.Store
  alias Arkab.{FakeReleases, Updates}
  alias Arkab.Updates.Checker

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    # The bridge without its page: the store the settings live in, and the
    # PubSub the notice is told through. The checker is started here, with
    # no timer, so that nothing asks anybody by itself.
    start_supervised!({Arkab.Bridge, data_dir: dir, name: "hall", sources: [], drivers: false})
    start_supervised!({Checker, timer: false})
    Checker.forget()
    start_supervised!(FakeReleases)
    FakeReleases.install()

    on_exit(fn ->
      FakeReleases.uninstall()
      Application.delete_env(:arkab, :install_kind)
      Application.delete_env(:arkab, :updates_stop_fun)
      Application.delete_env(:arkab, :updates_stop_delay)
      Application.delete_env(:arkab, :update_status_file)
    end)

    :ok
  end

  defp newer do
    version = Version.parse!(Updates.current_version())
    "#{version.major}.#{version.minor + 1}.0"
  end

  describe "asking" do
    test "a newer release is found, with the size of what this copy would download" do
      FakeReleases.publish(newer())

      assert {:ok, info, etag} = Updates.check()
      assert info.version == newer()
      assert info.tag == "v" <> newer()
      assert info.url =~ "/releases/tag/v" <> newer()
      assert is_binary(etag)

      # A copy that is not installed fetches the archive of its system.
      assert info.asset == Updates.asset_name(:manual, newer())
      assert info.size in [52_000_000, 31_000_000, 30_000_000, 29_000_000]
    end

    test "each system asks for the download of its own, by the name the release gives it" do
      v = newer()
      assert Updates.asset_name(:manual, v, {:win32, :nt}) == "arkab-windows-x86_64-portable.zip"

      assert Updates.asset_name(:manual, v, {:unix, :linux}) =~
               ~r/^arkab-linux-(x86_64|aarch64)\.tar\.gz$/
    end

    test "an Intel Mac is told there is no build, not sent to a file that does not exist" do
      assert Updates.no_build?({:unix, :darwin}) == (Updates.arch() == "x86_64")
      refute Updates.no_build?({:unix, :linux})
      refute Updates.no_build?({:win32, :nt})

      # The name must be nil exactly when the notice says "no build".
      name = Updates.asset_name(:manual, newer(), {:unix, :darwin})
      assert is_nil(name) == Updates.no_build?({:unix, :darwin})
      assert name in [nil, "arkab-macos-aarch64.zip"]
    end

    test "the Windows installation is told the size of the full package" do
      Application.put_env(:arkab, :install_kind, :velopack)
      FakeReleases.publish(newer())

      assert {:ok, info, _etag} = Updates.check()
      assert info.asset == "ArkabApp-#{newer()}-full.nupkg"
      assert info.size == 43_000_000
    end

    test "a release without the asset has no size, and is still a release" do
      FakeReleases.publish(newer(), sizes: %{Updates.asset_name(:manual, newer()) => "big"})
      assert {:ok, %{size: nil}, _etag} = Updates.check()
    end

    test "the version that is running, or an older one, is not news" do
      FakeReleases.publish(Updates.current_version())
      assert {:current, _etag} = Updates.check()

      FakeReleases.publish("0.0.1")
      assert {:current, _etag} = Updates.check()
    end

    test "the second question carries the ETag and costs a 304" do
      FakeReleases.publish(newer())
      assert {:ok, _info, etag} = Updates.check()
      assert :not_modified = Updates.check(etag)
      assert FakeReleases.requests() == [nil, etag]
    end

    test "offline, rate-limited, nothing released, nonsense, a draft: all the same silence" do
      FakeReleases.publish(newer())

      for mode <- [:down, :rate_limited, :garbage] do
        FakeReleases.mode(mode)
        assert Updates.check() == :error
      end

      FakeReleases.mode(:ok)
      FakeReleases.publish(newer(), draft: true)
      assert Updates.check() == :error
      FakeReleases.publish(newer(), prerelease: true)
      assert Updates.check() == :error
      FakeReleases.publish("not-a-version", tag: "nightly")
      assert Updates.check() == :error
    end

    test "a repository that has released nothing is silence too" do
      assert Updates.check() == :error
    end
  end

  describe "the checker" do
    test "remembers what it heard and tells the pages" do
      Updates.subscribe()
      FakeReleases.publish(newer())

      assert {:ok, %{version: version}} = Checker.check_now()
      assert version == newer()
      assert Checker.current().version == newer()
      assert_receive :update_changed
    end

    test "a failure does not forget what was known" do
      FakeReleases.publish(newer())
      assert {:ok, _info} = Checker.check_now()

      FakeReleases.mode(:down)
      assert Checker.check_now() == :error
      assert Checker.current().version == newer()
    end

    test "a release that is no longer newer is forgotten" do
      FakeReleases.publish(newer())
      assert {:ok, _info} = Checker.check_now()

      FakeReleases.publish(Updates.current_version())
      assert Checker.check_now() == :current
      assert Checker.current() == nil
    end

    test "the timer asks nothing while the setting says never" do
      FakeReleases.publish(newer())
      Updates.put_mode("never")

      send(Checker, :tick)
      _ = :sys.get_state(Checker)
      assert FakeReleases.requests() == []
      assert Checker.current() == nil

      Updates.put_mode("ask")
      send(Checker, :tick)
      _ = :sys.get_state(Checker)
      assert FakeReleases.requests() == [nil]
      assert Checker.current().version == newer()
    end
  end

  describe "the notice" do
    setup do
      FakeReleases.publish(newer())
      {:ok, _info} = Checker.check_now()
      :ok
    end

    test "is there while the setting says ask" do
      assert Updates.notice().version == newer()
    end

    test "is gone when switched off, and what was heard is kept" do
      Updates.put_mode("never")
      assert Updates.notice() == nil
      assert Updates.available().version == newer()
    end

    test "\"Later\" puts it away for this version, not for the next" do
      Updates.later(newer())
      assert Updates.notice() == nil

      next = Version.parse!(newer())
      Checker.put(%{Updates.available() | version: "#{next.major}.#{next.minor + 1}.0"})
      assert Updates.notice() != nil
    end

    test "\"Later\" runs out" do
      Store.put("update_later", %{
        "version" => newer(),
        "until" => System.os_time(:second) - 1
      })

      assert Updates.notice().version == newer()
    end
  end

  describe "applying" do
    setup do
      FakeReleases.publish(newer())
      {:ok, _info} = Checker.check_now()
      test = self()
      Application.put_env(:arkab, :updates_stop_fun, &send(test, {:stopped, &1}))
      Application.put_env(:arkab, :updates_stop_delay, 0)
      :ok
    end

    test "a copy that cannot update itself says so and does nothing" do
      assert Updates.apply() == {:error, :manual}
      refute_receive {:stopped, _code}, 100
    end

    test "nothing known, nothing done" do
      Application.put_env(:arkab, :install_kind, :velopack)
      Checker.forget()
      assert Updates.apply() == {:error, :nothing}
      refute_receive {:stopped, _code}, 100
    end

    test "the Windows installation stops with the code its launcher waits for" do
      Application.put_env(:arkab, :install_kind, :velopack)

      assert Updates.apply() == :ok
      assert_receive {:stopped, 90}
    end

    test "the Linux installation leaves the version for the updater, and nothing else" do
      Application.put_env(:arkab, :install_kind, :systemd)
      File.rm_rf!(Updates.request_dir())

      assert Updates.apply() == :ok
      assert File.read!(Path.join(Updates.request_dir(), "request")) == newer() <> "\n"
      refute_receive {:stopped, _code}, 100
    after
      File.rm_rf!(Updates.request_dir())
    end
  end

  describe "what the Linux updater said" do
    @tag :tmp_dir
    test "is read from the file it writes", %{tmp_dir: dir} do
      file = Path.join(dir, "status")
      Application.put_env(:arkab, :update_status_file, file)

      assert Updates.last_result() == nil

      File.write!(file, "ok 0.3.0\n")
      assert Updates.last_result() == {:ok, "0.3.0"}

      File.write!(file, "failed 0.3.0 the new version did not answer; 0.2.0 is running again\n")

      assert Updates.last_result() ==
               {:failed, "0.3.0", "the new version did not answer; 0.2.0 is running again"}

      File.write!(file, "what\n")
      assert Updates.last_result() == nil
    end
  end
end
