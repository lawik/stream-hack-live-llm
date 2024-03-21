defmodule LiveLlm.Repo do
  use Ecto.Repo,
    otp_app: :live_llm,
    adapter: Ecto.Adapters.Postgres
end
