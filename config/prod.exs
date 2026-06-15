import Config

# TLS is terminated and http->https is enforced at the reverse proxy (Nginx
# Proxy Manager); the app only ever speaks plain HTTP to it. We deliberately do
# NOT set `force_ssl` here: with the proxy already redirecting, an app-side
# Plug.SSL redirect double-forces SSL and loops whenever the app doesn't see
# `x-forwarded-proto: https`. The endpoint's `url: [scheme: "https"]`
# (config/runtime.exs) still makes generated links absolute https URLs.

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
