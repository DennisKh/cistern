defmodule CisternTest do
  use ExUnit.Case, async: false

  doctest Cistern

  setup do
    %{
      key: Enum.random(1_000..2_000) |> to_string(),
      value: Enum.random(3_000..4_000)
    }
  end

  test "set/1 stores a value in a cache", %{key: key, value: value} do
    assert {:ok, ^value} = Cistern.set(key, value)
  end

  test "set/1 stores a value in a cache with ttl", %{key: key, value: value} do
    assert {:ok, ^value} = Cistern.set(key, value, ttl: 200)
    :timer.sleep(500)
    assert {:ok, nil} = Cistern.get(key)
  end

  test "get/1 returns a cached value", %{key: key, value: value} do
    assert {:ok, ^value} = Cistern.set(key, value)
    assert {:ok, ^value} = Cistern.get(key)
  end

  test "get/1 returns a cached value as a number", %{key: key} do
    assert {:ok, _value} = Cistern.set(key, "5")
    assert {:ok, 5} = Cistern.get(key)
  end

  test "get/1 returns a cached value as a boolean", %{key: key} do
    assert {:ok, _value} = Cistern.set(key, "true")
    assert {:ok, true} = Cistern.get(key)
  end

  test "multiple/1 returns multiple values for a list of keys" do
    assert {:ok, value_1} = Cistern.set("key_1", 1)
    assert {:ok, value_2} = Cistern.set("key_2", 2)

    assert {:ok, [^value_1, ^value_2]} = Cistern.multiple(["key_1", "key_2"])
  end

  test "multiple/1 returns nil for non-existing key" do
    assert {:ok, value_1} = Cistern.set("key_3", 1)

    assert {:ok, [^value_1, nil]} = Cistern.multiple(["key_3", "key_4"])
  end

  test "increment/1 increments the number stored at key by one", %{key: key} do
    assert {:ok, _value} = Cistern.set(key, 1)
    assert {:ok, 2} = Cistern.increment(key)
    assert {:ok, 3} = Cistern.increment(key)
  end

  test "increment/1 returns error if the value is not a number", %{value: value} do
    assert {:ok, _value} = Cistern.set("foo", value)

    assert {:error, %Redix.Error{message: "ERR value is not an integer or out of range"}} ==
             Cistern.increment("foo")
  end

  test "set_many/1 stores multiple key-value pairs", %{key: key, value: value} do
    assert :ok = Cistern.set_many([{key, value}, {"key_5", 100}])
    assert {:ok, [^value, 100]} = Cistern.multiple([key, "key_5"])
  end

  test "set_many/1 returns :ok for an empty list" do
    assert :ok = Cistern.set_many([])
  end

  test "delete/1 deletes a cache for one key", %{key: key, value: value} do
    assert {:ok, ^value} = Cistern.set(key, value)
    assert {:ok, 1} = Cistern.delete(key)
    assert {:ok, nil} = Cistern.get(key)
  end

  test "delete_many/1 deletes a cache for multiple keys", %{key: key, value: value} do
    assert {:ok, _} = Cistern.set(key, value)
    assert {:ok, _} = Cistern.set(value, key)
    assert {:ok, 2} = Cistern.delete_many([key, value])
    assert {:ok, nil} = Cistern.get(key)
    assert {:ok, nil} = Cistern.get(value)
  end

  test "delete/1 treats an iodata list as a single key", %{value: value} do
    key = ["prefix", "439002600634484"]
    assert {:ok, ^value} = Cistern.set(key, value)
    assert {:ok, ^value} = Cistern.get(key)
    assert {:ok, 1} = Cistern.delete(key)
    assert {:ok, nil} = Cistern.get(key)
  end

  test "command/1 executes a Redis command and returns a result" do
    assert {:ok, "PONG"} == Cistern.command(["PING"])
  end

  test "noreply_pipeline/1 executes a Redis command and does not return a result" do
    assert :ok == Cistern.noreply_pipeline([["PING"], ["DEL", "any_key"]])
  end
end
