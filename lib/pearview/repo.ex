defmodule Pearview.Repo do
  use Ecto.Repo,
    otp_app: :pearview,
    adapter: Ecto.Adapters.SQLite3
end
