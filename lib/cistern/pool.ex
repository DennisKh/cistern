defmodule Cistern.Redis.Pool do
  @moduledoc false
  require Logger
  use Supervisor
  alias Cistern.Redis.Client

  @pool_name :redix_pool

  @doc false
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec pool_name() :: atom()
  def pool_name, do: @pool_name

  @spec timeout() :: non_neg_integer()
  def timeout, do: config(:pool_timeout, 5_000)

  def init(_opts) do
    config = config()
    pool_size = Keyword.get(config, :pool_size, 1)
    max_overflow = Keyword.get(config, :pool_max_overflow, 0)
    Logger.info("Initializing a pool of #{pool_size} Redis connections")

    pool_config = [
      name: {:local, @pool_name},
      worker_module: Client,
      size: pool_size,
      max_overflow: max_overflow
    ]

    children = [
      :poolboy.child_spec(@pool_name, pool_config)
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end

  defp config, do: Application.get_all_env(:cistern)

  defp config(key, default) do
    config()[key] || default
  end
end
