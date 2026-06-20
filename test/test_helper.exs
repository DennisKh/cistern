ExUnit.start()

# Start the mock's Registry once for the whole suite so per-worker
# `RedixMock.start_link/1` calls don't race to start it (and don't hide
# state leakage behind an `{:already_started, _}` swallow).
{:ok, _} = Registry.start_link(keys: :unique, name: RedixMock.Registry)

Cistern.start_link()
