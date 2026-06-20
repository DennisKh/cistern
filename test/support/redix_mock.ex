defmodule RedixMock do
  @moduledoc """
  Redix library mock.
  """

  def start_link(_any) do
    case Registry.start_link(keys: :unique, name: RedixMock.Registry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok, :conn}
  end

  @doc """
  Removes all mock state so it cannot leak between tests. Call from an ExUnit
  `setup` block. Stops every registered key Agent and clears the registry.
  """
  def reset do
    for {_key, pid, _value} <-
          Registry.select(RedixMock.Registry, [{{:"$1", :"$2", :"$3"}, [], [:"$$"]}]) do
      if Process.alive?(pid), do: Agent.stop(pid)
    end

    :ok
  end

  def command(_conn, ["SET", key, value], _opts) do
    ensure_agent(key, value)

    Agent.update(name(key), fn _any -> value end)
    {:ok, "OK"}
  end

  def command(_conn, ["SET", key, value, "PX", ttl], _opts) do
    ensure_agent(key, value)

    Agent.update(name(key), fn _any -> value end)

    Task.start_link(fn ->
      :timer.sleep(ttl)
      Agent.update(name(key), fn _any -> nil end)
    end)

    {:ok, "OK"}
  end

  def command(_conn, ["MSET" | commands], _opts) do
    # Real Redis rejects an MSET with an odd number of arguments. Surfacing the
    # same error here keeps a malformed pair list (e.g. a duplicated field that
    # throws off pairing) from silently "passing" in tests.
    if rem(length(commands), 2) != 0 do
      {:error, %Redix.Error{message: "ERR wrong number of arguments for 'mset' command"}}
    else
      # Apply pairs left-to-right, matching Redis last-write-wins semantics.
      commands
      |> Enum.chunk_every(2)
      |> Enum.each(fn attrs ->
        command(:conn, ["SET" | attrs], [])
      end)

      {:ok, "OK"}
    end
  end

  def command(_conn, ["GET", key], _opts) do
    ensure_agent(key)
    {:ok, Agent.get(name(key), & &1)}
  end

  def command(_conn, ["INCR", "foo"], _opts) do
    {:error, %Redix.Error{message: "ERR value is not an integer or out of range"}}
  end

  def command(_conn, ["INCR", key], _opts) do
    ensure_agent(key)
    agent_name = name(key)
    Agent.update(agent_name, fn state -> (state || 0) + 1 end)
    {:ok, Agent.get(agent_name, & &1)}
  end

  def command(_conn, ["PING"], _opts) do
    {:ok, "PONG"}
  end

  def command(_conn, ["MGET" | keys], _opts) do
    {:ok,
     Enum.map(keys, fn key ->
       ensure_agent(key)
       Agent.get(name(key), & &1)
     end)}
  end

  def command(_conn, ["DEL", "some_key"], _opts) do
    {:ok, 0}
  end

  def command(_conn, ["DEL", key], _opts) do
    ensure_agent(key)
    Agent.update(name(key), fn _state -> nil end)
    {:ok, 1}
  end

  def command(_conn, ["PEXPIRE", key, ttl], _opts) do
    ensure_agent(key)

    Task.start_link(fn ->
      :timer.sleep(ttl)
      Agent.update(name(key), fn _any -> nil end)
    end)

    {:ok, 1}
  end

  def command(_conn, ["DEL" | keys], _opts) do
    Enum.each(keys, fn key ->
      ensure_agent(key)
      Agent.update(name(key), fn _state -> nil end)
    end)

    {:ok, length(keys)}
  end

  def noreply_pipeline(_conn, _args, _opts) do
    :ok
  end

  def pipeline(_conn, commands, _opts) do
    # Tests can force a pipeline failure (e.g. a failing PEXPIRE in set_many's
    # TTL step) by setting `:cistern, :mock_pipeline_error`.
    case Application.get_env(:cistern, :mock_pipeline_error) do
      nil ->
        results =
          Enum.map(commands, fn cmd ->
            {:ok, result} = command(:conn, cmd, [])
            result
          end)

        {:ok, results}

      reason ->
        {:error, reason}
    end
  end

  defp ensure_agent(key, value \\ nil) do
    Agent.start_link(fn -> value end, name: name(key))
  end

  defp name(key) do
    {:via, Registry, {RedixMock.Registry, key}}
  end
end
