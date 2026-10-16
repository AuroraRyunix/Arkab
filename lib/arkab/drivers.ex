defmodule Arkab.Drivers do
  @moduledoc """
  What the drivers need running: the registry that finds a loop's bus by its
  port (`Arkab.BusRegistry`) and the supervisor the buses live under
  (`Arkab.BusSupervisor`).

  Not started by Arkab as a library - nothing is. Whoever runs drivers puts
  this in its own tree: Alnasl does, and so does the bridge
  (`Arkab.Bridge`), unless it finds one already running.
  """

  use Supervisor

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Is it running in this node already?"
  def running?, do: Process.whereis(Arkab.BusSupervisor) != nil

  @impl true
  def init(_opts) do
    Supervisor.init(
      [
        {Registry, keys: :unique, name: Arkab.BusRegistry},
        {DynamicSupervisor, name: Arkab.BusSupervisor, strategy: :one_for_one}
      ],
      strategy: :one_for_all
    )
  end
end
