# Cistern

An Elixir library that wraps [Redix](https://github.com/whatyouhide/redix) with a [Poolboy](https://github.com/devinus/poolboy)-managed connection pool, providing a simple, typed API for common Redis operations.

Available on [Hex](https://hex.pm/packages/cistern).

## Features

- Connection pooling via Poolboy (configurable size and overflow)
- Automatic type coercion on reads: `"true"`/`"false"` → `boolean`, numeric strings → `integer`
- High-level helpers: `get`, `set` (with optional TTL), `multiple`, `set_many`, `delete`, `delete_many`, `increment`
- Low-level escape hatches: `command/2` and `pipeline/2` for arbitrary Redis commands
- Fire-and-forget `noreply_pipeline/2` for write-heavy workloads
- Composable key validation — accepts binaries, integers, or iodata lists

## Requirements

- Erlang 26+
- Elixir 1.17+
- A running Redis instance

## Installation

Add `cistern` to your dependencies in `mix.exs`:

```elixir
{:cistern, "~> 0.1"}
```

Then fetch dependencies:

```bash
mix deps.get
```

## Configuration

Add the following to your `config/config.exs` (or environment-specific file):

```elixir
config :cistern,
  host: "localhost",
  port: 6379,
  password: "",           # omit or leave blank for no auth
  pool_size: 10,          # number of persistent connections
  pool_max_overflow: 5,   # extra connections allowed under load
  pool_timeout: 5_000,    # ms to wait for a free connection
  sync_connect: true,
  exit_on_disconnection: true
```

### Runtime configuration (production)

For production it's common to read connection settings from environment
variables at boot via `config/runtime.exs`:

```elixir
import Config

if config_env() == :prod do
  config :cistern,
    host: System.fetch_env!("REDIS_HOST"),
    port: String.to_integer(System.get_env("REDIS_PORT", "6379")),
    password: System.get_env("REDIS_PASSWORD", ""),
    pool_size: String.to_integer(System.get_env("REDIS_POOL_SIZE", "10"))
end
```

## Usage

### Starting under a Supervision tree

```elixir
children = [
  Cistern,
  # ...
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Or start manually:

```elixir
{:ok, _pid} = Cistern.start_link()
```

### Basic operations

```elixir
# Store a value
{:ok, "bar"} = Cistern.set("foo", "bar")

# Store with a TTL (milliseconds)
{:ok, "bar"} = Cistern.set("foo", "bar", ttl: 10_000)

# Retrieve — strings are coerced to boolean or integer when possible
{:ok, "bar"}  = Cistern.get("foo")
{:ok, true}   = Cistern.get("flag_key")   # stored as "true"
{:ok, 42}     = Cistern.get("count_key")  # stored as "42"
{:ok, nil}    = Cistern.get("missing")

# Opt out of coercion to keep the raw string (e.g. zero-padded codes)
{:ok, "01001"} = Cistern.get("zip_key", coerce: false)  # stored as "01001"

# Bulk write
:ok = Cistern.set_many([{"foo", "bar"}, {"count", 1}])
:ok = Cistern.set_many([{"a", 1}, {"b", 2}], ttl: 60_000)

# Bulk read
{:ok, ["bar", 1]} = Cistern.multiple(["foo", "count"])

# Atomic increment
{:ok, 2} = Cistern.increment("count")

# Delete
{:ok, 1} = Cistern.delete("foo")           # returns count of deleted keys
{:ok, 2} = Cistern.delete_many(["a", "b"])
```

### Iodata keys

Keys can be iodata lists — they are joined into a single binary before being
sent to Redis. Non-binary elements (e.g. integer ids) are stringified and kept,
so `["user:", 1]` and `["user:", 2]` produce distinct keys:

```elixir
key = ["user:", user_id]   # user_id may be a binary or an integer
Cistern.set(key, data)
Cistern.get(key)
Cistern.delete(key)
```

### Raw Redis commands

```elixir
# Single command
{:ok, "PONG"} = Cistern.command(["PING"])
{:ok, "OK"}   = Cistern.command(["SET", "foo", "bar"])

# Pipelined commands (returns list of results)
{:ok, ["OK", "OK"]} = Cistern.pipeline([["SET", "a", 1], ["SET", "b", 2]])

# Fire-and-forget pipeline (no reply waited for)
:ok = Cistern.noreply_pipeline([["SET", "a", 1], ["SET", "b", 2]])
```

> **Note:** `noreply_pipeline/2` uses `CLIENT REPLY OFF` under the hood. If your Redis server or proxy does not support the `CLIENT` command, use `pipeline/2` instead.

## Testing

The library ships with a `RedixMock` test double that replaces the real Redix module via `Application.compile_env`. Configure it in `config/test.exs`:

```elixir
config :cistern, redis_module: RedixMock
```

Run the test suite:

```bash
mix test
```

Run with coverage:

```bash
mix test --cover
```

## Development

```bash
# Fetch deps
mix deps.get

# Start an interactive session
iex -S mix

# Static analysis
mix credo

# Generate docs
mix docs
```

## Architecture

```
Cistern          — public API and type coercion
  └── Cistern.Redis.Pool    — Supervisor that owns the Poolboy pool
        └── Cistern.Redis.Client  — GenServer worker; one per connection
```

Each `command/2`, `pipeline/2`, or `noreply_pipeline/2` call checks out a connection from the pool, executes the command via Redix, and returns it — all within a single `:poolboy.transaction/3`.
