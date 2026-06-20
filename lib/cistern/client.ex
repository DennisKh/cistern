defmodule Cistern.Redis.Client do
  @moduledoc false
  require Logger
  use GenServer

  @redis_module Application.compile_env(:cistern, :redis_module, Redix)

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    config = Application.get_all_env(:cistern)
    host = Keyword.fetch!(config, :host)
    port = Keyword.fetch!(config, :port)
    Logger.info("Connecting to the Redis server at #{host}:#{port}")

    config =
      config
      |> filter_empty()
      |> drop_internal_configs()

    @redis_module.start_link(config)
  end

  @doc false
  @impl true
  def handle_call({command, args, opts}, _from, conn)
      when command in [:command, :pipeline, :noreply_pipeline] do
    if Application.get_env(:cistern, :debug_commands, false) do
      Logger.debug("Execute Redix function `:#{command}` with Redis command #{inspect(args)}",
        ansi_color: :green
      )
    end

    {:reply, apply(@redis_module, command, [conn, args, opts]), conn}
  end

  defp filter_empty(configs) do
    Enum.reject(configs, fn {_key, value} ->
      value in ["", nil]
    end)
  end

  defp drop_internal_configs(configs) do
    Keyword.drop(configs, [:pool_size, :pool_max_overflow, :pool_timeout, :coerce])
  end
end
