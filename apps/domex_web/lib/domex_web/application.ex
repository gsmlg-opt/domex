defmodule DomexWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DomexWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:domex_web, :dns_cluster_query) || :ignore},
      DomexWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: DomexWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DomexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
