# Changelog

## [0.1.1](https://github.com/DennisKh/cistern/compare/v0.1.0...v0.1.1) (2026-06-20)


### Features

* make read coercion configurable globally and per call ([73d9014](https://github.com/DennisKh/cistern/commit/73d90141d4c95d48c56a5f8d7923d2a448a65cc6))


### Bug Fixes

* add hex.pm link to readme ([2d6791f](https://github.com/DennisKh/cistern/commit/2d6791f20295d735df3c28c8d596d13da050aacb))
* add hex.pm link to readme ([0a3a324](https://github.com/DennisKh/cistern/commit/0a3a3246fc05d1b6f7ad2ce72e5325d45f9c6199))
* preserve integers in iodata keys and dedup set_many writes ([a86c3a4](https://github.com/DennisKh/cistern/commit/a86c3a49f708f10795a25bce7982cd761b9a5585))
* preserve integers in iodata keys and dedup set_many writes ([f591b2e](https://github.com/DennisKh/cistern/commit/f591b2eaabdd4aa2a9ef5a9a2533737d429e87a3))

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
