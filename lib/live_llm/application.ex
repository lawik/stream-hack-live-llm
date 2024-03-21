defmodule LiveLlm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LiveLlmWeb.Telemetry,
      LiveLlm.Repo,
      {DNSCluster, query: Application.get_env(:live_llm, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LiveLlm.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: LiveLlm.Finch},
      # Start a worker by calling: LiveLlm.Worker.start_link(arg)
      # {LiveLlm.Worker, arg},
      # Start to serve requests, typically the last entry
      LiveLlmWeb.Endpoint,
      LiveLlm.LLM
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LiveLlm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LiveLlmWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
