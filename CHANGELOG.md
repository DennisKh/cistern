# Changelog

## [0.1.0](https://github.com/DennisKh/cistern/releases/tag/v0.1.0) (2024-01-01)

### Initial release

* `Cistern` public API: `get/1`, `set/3`, `multiple/1`, `set_many/2`, `delete/1`, `delete_many/1`, `increment/1`
* Low-level escape hatches: `command/2`, `pipeline/2`, `noreply_pipeline/2`
* Poolboy-backed connection pool with configurable size, overflow, and timeout
* Automatic type coercion on reads: `"true"`/`"false"` → boolean, numeric strings → integer
* Iodata key support: pass `["prefix:", id]` anywhere a key is accepted
* `RedixMock` test double for unit testing without a live Redis instance
