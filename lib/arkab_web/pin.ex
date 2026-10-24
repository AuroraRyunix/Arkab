defmodule ArkabWeb.Pin do
  @moduledoc """
  The remote PIN: what lets a phone or laptop on the hall's network do what
  this machine can do.

  Set, changed and removed from the bridge itself only (`ArkabWeb.StatusLive`
  checks `ArkabWeb.Local`). Stored as a salted PBKDF2-SHA256 hash in the
  bridge's settings table, never the PIN; compared in constant time. A right
  PIN is answered with a *grant* that goes into the Phoenix session cookie
  (signed and encrypted): the PIN's generation and a deadline twelve hours
  away. Every set, change and removal of the PIN counts the generation up,
  so grants made under the old PIN stop working at once, in a page that is
  already open too, because the page asks again before every change
  (`ArkabWeb.Local.may_change?/2`).

  A PIN has at least 4 characters (digits or anything else, 64 at most).
  Wrong guesses are throttled per peer address (`ArkabWeb.Pin.Throttle`).
  """

  alias Arkab.Bridge.Store
  alias ArkabWeb.Pin.Throttle

  @setting "remote_pin"
  @min_length 4
  @max_length 64
  @iterations 210_000
  @grant_seconds 12 * 3600
  @session_key "pin_grant"

  def min_length, do: @min_length
  def session_key, do: @session_key
  def grant_seconds, do: @grant_seconds

  @doc "Whether a PIN is set."
  @spec set?() :: boolean()
  def set?, do: match?(%{"hash" => _}, setting())

  @doc "Sets (or changes) the PIN. Every grant made before is void."
  @spec set(String.t()) :: :ok | {:error, :too_short | :too_long}
  def set(pin) when is_binary(pin) do
    cond do
      String.length(pin) < @min_length ->
        {:error, :too_short}

      String.length(pin) > @max_length ->
        {:error, :too_long}

      true ->
        salt = :crypto.strong_rand_bytes(16)
        iterations = Application.get_env(:arkab, :pin_iterations, @iterations)

        Store.put(@setting, %{
          "gen" => generation() + 1,
          "iter" => iterations,
          "salt" => Base.encode64(salt),
          "hash" => Base.encode64(hash(pin, salt, iterations))
        })
    end
  end

  @doc "Removes the PIN. Every grant made before is void."
  @spec remove() :: :ok
  def remove, do: Store.put(@setting, %{"gen" => generation() + 1})

  @doc """
  A guess from `peer` (the socket's address). `{:ok, grant}` for the right
  PIN, `{:error, :wrong}`, `{:error, {:locked, seconds}}` while locked out
  (even a right PIN does not get in then), or `{:error, :none}` without a PIN.
  """
  @spec attempt(String.t(), term()) ::
          {:ok, map()} | {:error, :wrong | :none | {:locked, pos_integer()}}
  def attempt(pin, peer) when is_binary(pin) do
    with %{"hash" => stored} = pin_setting <- setting(),
         :ok <- Throttle.claim(peer) do
      if matches?(pin, pin_setting, stored) do
        Throttle.clear(peer)
        {:ok, %{"gen" => pin_setting["gen"], "until" => now() + @grant_seconds}}
      else
        {:error, :wrong}
      end
    else
      {:locked, seconds} -> {:error, {:locked, seconds}}
      _no_pin -> {:error, :none}
    end
  end

  def attempt(_pin, _peer), do: {:error, :wrong}

  @doc "Whether a grant (from the session) is good now: this PIN generation, not expired."
  @spec valid_grant?(term()) :: boolean()
  def valid_grant?(%{"gen" => gen, "until" => until})
      when is_integer(gen) and is_integer(until) do
    case setting() do
      %{"hash" => _, "gen" => ^gen} -> now() < until and until - now() <= @grant_seconds
      _other -> false
    end
  end

  def valid_grant?(_other), do: false

  defp matches?(pin, %{"salt" => salt, "iter" => iterations}, stored) do
    with {:ok, salt} <- Base.decode64(salt),
         {:ok, stored} <- Base.decode64(stored) do
      Plug.Crypto.secure_compare(hash(pin, salt, iterations), stored)
    else
      _bad -> false
    end
  end

  defp hash(pin, salt, iterations), do: :crypto.pbkdf2_hmac(:sha256, pin, salt, iterations, 32)

  defp generation do
    case setting() do
      %{"gen" => gen} when is_integer(gen) -> gen
      _none -> 0
    end
  end

  # Not running (a library, a test): there is no PIN.
  defp setting do
    Store.get(@setting)
  catch
    :exit, _reason -> nil
  end

  defp now, do: System.os_time(:second)
end
