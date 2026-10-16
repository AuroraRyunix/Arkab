defmodule Arkab.Application do
  @moduledoc false

  # Two lives. As the bridge (`config :arkab, role: :bridge`, which Arkab's
  # own config says) it starts `Arkab.Bridge` with the configured data
  # directory and its page. As a library - Alnasl's dependency, whose
  # config never says so - it starts an empty supervisor and nothing else:
  # the drivers belong to whoever supervises them.

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:arkab, :role) == :bridge do
        [
          {Arkab.Bridge,
           data_dir: Application.fetch_env!(:arkab, :data_dir),
           web: Application.get_env(:arkab, :web, true)}
        ]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Arkab.Supervisor)
  end
end
