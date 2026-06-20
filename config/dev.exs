import Config

config :cistern,
  host: "localhost",
  port: 6379,
  password: "",
  sync_connect: true,
  exit_on_disconnection: true,
  pool_timeout: 1_000
