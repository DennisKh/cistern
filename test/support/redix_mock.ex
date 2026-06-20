defmodule RedixMock do
  @moduledoc """
  Redix library mock.
  """

  def start_link(_any) do
    Registry.start_link(keys: :unique, name: RedixMock.Registry)
    {:ok, :conn}
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
    commands
    |> Enum.chunk_every(2)
    |> Enum.each(fn attrs ->
      command(:conn, ["SET" | attrs], [])
    end)

    {:ok, "OK"}
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
    results =
      Enum.map(commands, fn cmd ->
        {:ok, result} = command(:conn, cmd, [])
        result
      end)

    {:ok, results}
  end

  defp ensure_agent(key, value \\ nil) do
    Agent.start_link(fn -> value end, name: name(key))
  end

  defp name(key) do
    {:via, Registry, {RedixMock.Registry, key}}
  end
end
