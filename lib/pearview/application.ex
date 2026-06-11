defmodule Pearview.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PearviewWeb.Telemetry,
      Pearview.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:pearview, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:pearview, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pearview.PubSub},
      # Supervises the unlinked background categorisation runs started on
      # Shopper-view open, so a request process dying (e.g. a phone lock right
      # after open) can't kill an in-flight OpenRouter call. See issue #18.
      {Task.Supervisor, name: Pearview.TaskSupervisor},
      # Start to serve requests, typically the last entry
      PearviewWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pearview.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PearviewWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
