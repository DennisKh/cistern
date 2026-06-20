defmodule Cistern do
  @moduledoc """
  A `Redix`-backed Redis client with a `poolboy`-managed connection pool and
  automatic type coercion on reads.

  ## Features

  - Connection pooling via `:poolboy` (configurable size and overflow)
  - Automatic type coercion: `"true"`/`"false"` → `boolean`, numeric strings → `integer`
  - High-level helpers: `get/1`, `set/3`, `multiple/1`, `set_many/2`, `delete/1`,
    `delete_many/1`, `increment/1`
  - Low-level escape hatches: `command/2` and `pipeline/2`
  - Fire-and-forget writes via `noreply_pipeline/2`
  - Composable iodata keys — pass `["prefix:", id]` anywhere a key is accepted

  ## Configuration

  Add the following to `config/config.exs` (or an environment-specific file):

      config :cistern,
        host: "localhost",
        port: 6379,
        password: "",           # omit or leave blank for no auth
        pool_size: 10,          # number of persistent connections
        pool_max_overflow: 5,   # extra connections allowed under load
        pool_timeout: 5_000,    # ms to wait for a free connection
        sync_connect: true,
        exit_on_disconnection: true

  ## Starting under a supervision tree

      children = [
        Cistern,
        # ...other children
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  ## Quick example

      iex> Cistern.set("counter", 0)
      {:ok, 0}
      iex> Cistern.increment("counter")
      {:ok, 1}
      iex> Cistern.get("counter")
      {:ok, 1}
      iex> Cistern.delete("counter")
      {:ok, 1}
  """
  alias Cistern.Redis.Pool

  @type value :: Redix.Protocol.redis_value() | boolean()
  @type result :: {:ok, value()} | {:error, atom() | Redix.Error.t()}

  @doc """
  Starts a pool of connections to Redis.

  This function returns `{:ok, pid}` if the Poolboy and Redix are started
  successfully.

  The connection options should be set in the config file.

    config :cistern,
      host: "localhost",
      port: 6379,
      pool_size: 10,
      pool_max_overflow: 5,
      pool_timeout: 5_000,
      password: "",
      sync_connect: true,
      exit_on_disconnection: true
  """
  @spec start_link(opts :: keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []), do: Pool.start_link(opts)

  @doc """
  Returns a child spec to use Cistern in supervision trees.

  To use Cistern with the default options (same as calling `Cistern.start_link()`):

      children = [
        Cistern,
        # ...
      ]

  No options are supported for now. All options should be set in the config file.
  """
  @spec child_spec(args :: keyword()) :: Supervisor.child_spec()
  def child_spec(args \\ []) do
    %{
      id: __MODULE__,
      type: :worker,
      start: {__MODULE__, :start_link, args}
    }
  end

  @doc """
  Returns one cached value by a key.
  Redis stores any term as a string. The returned value will be parsed to a possible type:
    * "true" and "false" to a boolean
    * string number to an integer, ex: "123" to 123
    * regular strings will remain unchanged

  ## Examples

      iex> Cistern.set_many([{"foo", "bar"}, {"boo", "true"}, {"baz", "1"}])
      :ok
      iex> Cistern.get("foo")
      {:ok, "bar"}
      iex> Cistern.get("boo")
      {:ok, true}
      iex> Cistern.get("baz")
      {:ok, 1}
      iex> Cistern.get("some")
      {:ok, nil}
  """
  @spec get(key :: any()) :: result()
  def get(key) do
    key = validate_key(key)

    ["GET", key]
    |> command()
    |> translate()
  end

  @doc """
  Returns multiple cached values by a list of keys. For every key that does not hold a string value
  or does not exist,the special value `nil` is returned.

  ## Examples

      iex> Cistern.set_many([{"foo", "bar"}, {"boo", true}])
      :ok
      iex> Cistern.multiple(["foo", "boo"])
      {:ok, ["bar", true]}
      iex> Cistern.multiple([])
      {:ok, nil}
      iex> Cistern.multiple(["any"])
      {:ok, [nil]}
  """
  @spec multiple(keys :: [any()]) :: {:ok, nil | [value()]} | {:error, atom() | Redix.Error.t()}
  def multiple(keys) do
    validated_keys = Enum.map(keys, &validate_key/1)

    if Enum.empty?(validated_keys) do
      {:ok, nil}
    else
      ["MGET" | validated_keys]
      |> command()
      |> translate_many()
    end
  end

  @doc """
  Stores a value in Redis cache under a given key. If key already holds a value, it is overwritten,
  regardless of its type. Any previous time to live associated with the key
  is discarded on successful SET operation.

  ## Options

    * `:ttl` - An expiration time to set for the provided key (time-to-live),
      this value should be in milliseconds.

  ## Examples

      iex> Cistern.set("foo", "bar", ttl: 10_000)
      {:ok, "bar"}
      iex> Cistern.set("baz", 1)
      {:ok, 1}
      iex> Cistern.set("boo", true)
      {:ok, true}
  """
  @spec set(key :: any(), value :: any(), opts :: Keyword.t()) :: result()
  def set(key, value, opts \\ []) do
    key = validate_key(key)

    case Keyword.fetch(opts, :ttl) do
      {:ok, ttl} ->
        command(["SET", key, value, "PX", ttl])

      _ ->
        command(["SET", key, value])
    end
    |> case do
      {:ok, "OK"} -> {:ok, value}
      any -> any
    end
  end

  @doc """
  Increments the number stored at key by one.
  See Redis docs https://redis.io/commands/incr/ for more details.

  ## Examples

      iex> Cistern.set_many([{"baz", 1}, {"other", 0}, {"foo", "bar"}])
      :ok
      iex> Cistern.increment("baz")
      {:ok, 2}
      iex> Cistern.increment("other")
      {:ok, 1}
      iex> Cistern.increment("foo")
      {:error, %Redix.Error{message: "ERR value is not an integer or out of range"}}
  """
  @spec increment(key :: any()) :: result()
  def increment(key) do
    key = validate_key(key)
    command(["INCR", key])
  end

  @doc """
  Stores multiple key-value pairs in the cache.

  ## Options

    * `:ttl` - An expiration time to set for the provided keys, one for all,
      this value should be in milliseconds.

  ## Examples

      iex> Cistern.set_many([{"foo", "bar"}, {"boo", "true"}])
      :ok
      iex> Cistern.set_many([])
      :ok
  """
  @spec set_many(Keyword.t(), opts :: Keyword.t()) :: :ok
  def set_many(kv_list, opts \\ []) do
    %{kv: validated_kv_list, keys: validated_keys} =
      Enum.reduce(kv_list, %{keys: [], kv: []}, fn {key, value}, acc ->
        validated_key = validate_key(key)
        kv = [validated_key, value]

        acc
        |> Map.put(:keys, [validated_key | acc.keys])
        |> Map.put(:kv, [kv | acc.kv])
      end)

    flattened_kv_list =
      validated_kv_list
      |> Enum.uniq()
      |> List.flatten()

    do_set_many(flattened_kv_list)

    maybe_set_ttl(validated_keys, opts)
    :ok
  end

  @doc """
  Removes cache for a single key. A key is ignored if it does not exist.
  Returns `{:ok, 1}` when the key existed, `{:ok, 0}` otherwise.

  The key may be a binary or iodata (e.g. `["prefix", id]`); the same iodata
  interpretation used by `get/1`, `set/3` and `increment/1` applies. For
  deleting multiple distinct keys in a single round-trip, use `delete_many/1`.

  ## Examples

      iex> Cistern.delete("some_key")
      {:ok, 0}
  """
  @spec delete(key :: any()) :: {:ok, non_neg_integer()} | {:error, atom() | Redix.Error.t()}
  def delete(key) do
    command(["DEL", validate_key(key)])
  end

  @doc """
  Removes cache for a list of specified keys. A key is ignored if it does not
  exist. Returns a count of deleted keys.

  Each element is validated like a key passed to `get/1` (binary or iodata).

  ## Examples

      iex> Cistern.delete_many(["foo", "boo"])
      {:ok, 2}
      iex> Cistern.delete_many([])
      {:ok, 0}
  """
  @spec delete_many(keys :: [any()]) ::
          {:ok, non_neg_integer()} | {:error, atom() | Redix.Error.t()}
  def delete_many([]), do: {:ok, 0}

  def delete_many(keys) when is_list(keys) do
    validated_keys = Enum.map(keys, &validate_key/1)
    command(["DEL" | validated_keys])
  end

  @doc """
  Wrapper to call `Redix.command/3` inside a poolboy worker.

  ## Options
    * See https://hexdocs.pm/redix/Redix.html#pipeline/3-options for more options.

  ## Examples

      iex> Cistern.command(["SET", "foo", "bar"])
      {:ok, "OK"}
      iex> Cistern.command(["GET", "foo"])
      {:ok, "bar"}
      iex> Cistern.command(["PING"])
      {:ok, "PONG"}
  """
  @spec command(args :: list(), opts :: Keyword.t()) ::
          {:ok, Redix.Protocol.redis_value()} | {:error, atom | Redix.Error.t()}
  def command(args, opts \\ []) do
    :poolboy.transaction(
      Pool.pool_name(),
      fn worker -> GenServer.call(worker, {:command, args, opts}) end,
      Pool.timeout()
    )
  end

  @doc """
  Wrapper to call `Redix.pipeline/3` inside a poolboy worker.

  ## Options

    * See https://hexdocs.pm/redix/Redix.html#pipeline/3-options for more options.

  ## Examples

      iex> Cistern.pipeline([["SET", "foo", "bar"], ["SET", "baz", "true"]])
      {:ok, ["OK", "OK"]}
  """
  @spec pipeline(args :: [list()], opts :: Keyword.t()) ::
          {:ok, [Redix.Protocol.redis_value()]}
          | {:error, atom() | Redix.Error.t() | Redix.ConnectionError.t()}
  def pipeline(args, opts \\ []) do
    :poolboy.transaction(
      Pool.pool_name(),
      fn worker -> GenServer.call(worker, {:pipeline, args, opts}) end,
      Pool.timeout()
    )
  end

  @doc """
  Wrapper to call `Redix.noreply_pipeline/3` inside a poolboy worker.

  Note: `Redix.noreply_pipeline/3` issues `CLIENT REPLY OFF/ON` under the hood.
  If your Redis server (or a proxy in front of it) does not support the `CLIENT`
  command, use `pipeline/2` instead.

  ## Options

    * See https://hexdocs.pm/redix/Redix.html#pipeline/3-options for more options.

  ## Examples

      iex> Cistern.noreply_pipeline([["SET", "foo", "bar"], ["SET", "baz", "true"]])
      :ok
  """
  @spec noreply_pipeline(args :: list(), opts :: Keyword.t()) ::
          :ok | {:error, atom() | Redix.Error.t() | Redix.ConnectionError.t()}
  def noreply_pipeline(args, opts \\ []) do
    :poolboy.transaction(
      Pool.pool_name(),
      fn worker -> GenServer.call(worker, {:noreply_pipeline, args, opts}) end,
      Pool.timeout()
    )
  end

  defp do_set_many([]), do: :ok

  defp do_set_many(flattened_kv_list) do
    {:ok, _} =
      ["MSET" | flattened_kv_list]
      |> command()
  end

  defp maybe_set_ttl([], _opts), do: :ok

  defp maybe_set_ttl(validated_keys, opts) do
    case Keyword.fetch(opts, :ttl) do
      {:ok, ttl} ->
        validated_keys
        |> Enum.uniq()
        |> Enum.map(fn validated_key ->
          ["PEXPIRE", validated_key, ttl]
        end)
        |> pipeline()

        :ok

      _ ->
        :ok
    end
  end

  defp validate_key(nil) do
    raise("""
      The Redis cache key can't be nil.

      To be converted to IO data, a key must either be an empty list or be one
      of the following elements:

      * binary
      * integer
      * a list containing only binaries
    """)
  end

  defp validate_key(key) when is_binary(key), do: key

  defp validate_key(key) when is_list(key) do
    key
    |> Enum.filter(&is_binary/1)
    |> IO.iodata_to_binary()
  end

  defp validate_key(key), do: to_string(key)

  defp translate({:ok, value}), do: {:ok, do_translate(value)}
  defp translate(result), do: result

  defp translate_many({:ok, list}) do
    {:ok, Enum.map(list, &do_translate/1)}
  end

  defp translate_many(any), do: any

  defp do_translate("true"), do: true
  defp do_translate("false"), do: false

  defp do_translate(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _any -> val
    end
  end

  defp do_translate(any), do: any
end
