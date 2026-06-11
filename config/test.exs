import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pearview, Pearview.Repo,
  database: Path.expand("../db/pearview_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pearview, PearviewWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "nEEtGzXBmaVwMuFivLyCNw4x6y2xSVZLGc3ojDQStbf03kkFwdl0OQZa/7FfUZa6",
  server: false

# Route all OpenRouter calls through Req.Test so tests never hit the network,
# and pin a known API key so request-shape assertions are deterministic.
config :pearview, Pearview.AI,
  api_key: "test-openrouter-key",
  req_options: [plug: {Req.Test, Pearview.AI}]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
