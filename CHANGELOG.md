# Changelog

## [Unreleased] (2026-06-20)

### Fixed

* `validate_key/1` no longer drops non-binary elements of an iodata key.
  Elements are now stringified (not filtered), so `["prefix:", 42]` produces
  `"prefix:42"` and distinct ids no longer collide on the same key.
* `set_many/2` dedups repeated keys with last-write-wins before building the
  `MSET`, fixing a malformed command (duplicate fields, reversed order) when a
  key appeared more than once.
* `set_many/2` now surfaces TTL pipeline failures as `{:error, reason}` instead
  of unconditionally returning `:ok`; the spec widens to `:ok | {:error, term()}`.

### Added

* `get/2` accepts a `coerce: false` option to return the raw stored string
  without boolean/integer coercion (e.g. `"01001"` stays `"01001"`). Default
  behavior is unchanged.
* `set/3` now guards `:ttl` with `is_integer(ttl) and ttl > 0`, raising
  `ArgumentError` on an invalid TTL instead of emitting a raw Redis error.
* `config :cistern, :debug_commands, false` flag to gate the per-command debug
  log in `Cistern.Redis.Client` (off by default).

## [0.1.0](https://github.com/DennisKh/cistern/releases/tag/v0.1.0) (2024-01-01)

### Initial release

* `Cistern` public API: `get/2`, `set/3`, `multiple/1`, `set_many/2`, `delete/1`, `delete_many/1`, `increment/1`
* Low-level escape hatches: `command/2`, `pipeline/2`, `noreply_pipeline/2`
* Poolboy-backed connection pool with configurable size, overflow, and timeout
* Automatic type coercion on reads: `"true"`/`"false"` → boolean, numeric strings → integer
* Iodata key support: pass `["prefix:", id]` anywhere a key is accepted
* `RedixMock` test double for unit testing without a live Redis instance
