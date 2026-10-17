defmodule Domex.Discovery.Supervisor do
  @moduledoc """
  Supervisor managing network discovery listeners and probers.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Domex.Discovery.SsdpListener,
      Domex.Discovery.MiioProbe,
      Domex.Discovery.MideaListener
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
