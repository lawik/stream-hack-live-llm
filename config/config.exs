# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :live_llm,
  ecto_repos: [LiveLlm.Repo],
  generators: [timestamp_type: :utc_datetime]

config :ex_aws, :s3,
  scheme: "https://",
  host: "fly.storage.tigris.dev",
  port: 443

host = if app = System.get_env("FLY_APP_NAME"), do: "#{app}.fly.dev", else: "localhost"

# Configures the endpoint
config :live_llm, LiveLlmWeb.Endpoint,
  url: [host: host],
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || "8080"),
  ],
  server: true,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LiveLlmWeb.ErrorHTML, json: LiveLlmWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LiveLlm.PubSub,
  live_view: [signing_salt: "9hPAX1Si"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :live_llm, LiveLlm.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  live_llm: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  live_llm: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :bumblebee, :progress_bar_enabled, false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
