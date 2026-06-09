# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pearview,
  ecto_repos: [Pearview.Repo],
  generators: [timestamp_type: :utc_datetime]

# AI categorisation via OpenRouter (OpenAI-compatible). The API key is read from
# OPENROUTER_API_KEY at call time; the model can be overridden with the
# OPENROUTER_MODEL env var. See `Pearview.AI`.
config :pearview, Pearview.AI,
  base_url: "https://openrouter.ai/api/v1",
  model: "deepseek/deepseek-v4-flash"

# Configure the endpoint
config :pearview, PearviewWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PearviewWeb.ErrorHTML, json: PearviewWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pearview.PubSub,
  live_view: [signing_salt: "3LNv759Y"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
