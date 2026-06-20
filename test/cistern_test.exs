defmodule CisternTest do
  use ExUnit.Case, async: false

  doctest Cistern

  setup do
    # Reset mock state between tests so leaked keys can't mask bugs.
    RedixMock.reset()
    Application.delete_env(:cistern, :mock_pipeline_error)

    on_exit(fn -> Application.delete_env(:cistern, :mock_pipeline_error) end)

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

  test "validate_key preserves integer elements in an iodata key (bug 1)", %{value: value} do
    # A distinct id must yield a distinct key. On the old code the integer was
    # filtered out, so both keys collapsed to "user:" and collided.
    key_1 = ["user:", 1]
    key_2 = ["user:", 2]

    assert {:ok, ^value} = Cistern.set(key_1, value)
    assert {:ok, "other"} = Cistern.set(key_2, "other")

    assert {:ok, ^value} = Cistern.get(key_1)
    assert {:ok, "other"} = Cistern.get(key_2)
  end

  test "set_many/2 dedups duplicate keys with last-write-wins (bug 2)" do
    assert :ok = Cistern.set_many([{"dup", 1}, {"b", 2}, {"dup", 3}])

    # Last write for "dup" wins; "b" is untouched. On the old code the reversed,
    # non-deduped MSET produced a malformed command and the wrong final value.
    assert {:ok, 3} = Cistern.get("dup")
    assert {:ok, 2} = Cistern.get("b")
  end

  test "set_many/2 surfaces a TTL pipeline failure (bug 3)" do
    Application.put_env(:cistern, :mock_pipeline_error, %Redix.Error{message: "boom"})

    assert {:error, %Redix.Error{message: "boom"}} =
             Cistern.set_many([{"k1", 1}, {"k2", 2}], ttl: 1_000)
  end

  test "get/2 with coerce: false returns the raw string", %{key: key} do
    assert {:ok, _} = Cistern.set(key, "01001")

    assert {:ok, 1001} = Cistern.get(key)
    assert {:ok, "01001"} = Cistern.get(key, coerce: false)
  end

  test "set/3 raises on a non-positive-integer ttl", %{key: key, value: value} do
    assert_raise ArgumentError, fn -> Cistern.set(key, value, ttl: "1000") end
    assert_raise ArgumentError, fn -> Cistern.set(key, value, ttl: 0) end
    assert_raise ArgumentError, fn -> Cistern.set(key, value, ttl: 1.5) end
  end

  test "command/1 executes a Redis command and returns a result" do
    assert {:ok, "PONG"} == Cistern.command(["PING"])
  end

  test "noreply_pipeline/1 executes a Redis command and does not return a result" do
    assert :ok == Cistern.noreply_pipeline([["PING"], ["DEL", "any_key"]])
  end
end
