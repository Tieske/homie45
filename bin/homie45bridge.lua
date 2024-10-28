#!/usr/bin/env lua

--- Main CLI application.
-- A Homie v4 to Homie v5 bridge application. The v4 devices will be collected
-- and converted and published as v5 devices. Any values `set` on the v5 version
-- will be passed back to the v4 version.
--
-- For configuring the log, use LuaLogging environment variable prefix `"HOMIE_LOG_"`, see
-- "logLevel" in the example below.
--
-- If device descriptions are incomplete then try increasing the `subscribe_delay`.
-- This is the delay (in milliseconds) between subscribing to
-- discovered devices. This prevents too many topics being queued at once MQTT-server-side such
-- that they might get dropped.
--
-- A clean option to quickly try the bridge is to use Docker. The git repo
-- has a `Dockerfile` and a `docker.sh` script to try this.
--
-- @script homie45bridge
-- @usage
-- # configure parameters as environment variables
-- export HOMIE_MQTT_URI="mqtt://synology"    # format: "mqtt(s)://user:pass@hostname:port"
-- export HOMIE_MQTT_ID="homie45-bridge"      # default: "homie45-bridge-xxxxxxx"
-- export HOMIE_DEVICE_ID="homie45-bridge"    # default: "homie45-bridge-xxxxxxx"
-- export HOMIE_DOMAIN4="homie"               # default: "homie"
-- export HOMIE_DOMAIN5="homie"               # default: "homie"
-- export HOMIE_SUBSCRIBE_DELAY=5000          # default: 1000
-- export HOMIE_LOG_LOGLEVEL="debug"          # default: "info"
--
-- # start the application
-- homie45bridge



local ll = require "logging"
local copas = require "copas"
require("logging.rsyslog").copas() -- ensure copas, if rsyslog is used
local logger = assert(require("logging.envconfig").set_default_logger("HOMIE_LOG"))


do -- set Copas errorhandler
  local lines = require("pl.stringx").lines

  copas.setErrorHandler(function(msg, co, skt)
    msg = copas.gettraceback(msg, co, skt)
    for line in lines(msg) do
      ll.defaultLogger():error(line)
    end
  end , true)
end


print("starting Homie 4-to-5 bridge")
logger:info("starting Homie 4-to-5 bridge")


local opts = {
  uri = assert(os.getenv("HOMIE_MQTT_URI"), "environment variable HOMIE_MQTT_URI not set"),
  domain4 = os.getenv("HOMIE_DOMAIN4") or "homie",
  domain5 = os.getenv("HOMIE_DOMAIN5") or "homie",
  id = os.getenv("HOMIE_MQTT_ID") or ("homie45-bridge-%07x"):format(math.random(1, 0xFFFFFFF)),
  subscribe_delay = os.getenv("HOMIE_SUBSCRIBE_DELAY") or 1000,
  device_id = os.getenv("HOMIE_DEVICE_ID") or ("homie45bridge-%07x"):format(math.random(1, 0xFFFFFFF)),
}

logger:info("Bridge configuration:")
logger:info("HOMIE_MQTT_URI: %s", opts.uri)
logger:info("HOMIE_DOMAIN4: %s", opts.domain4)
logger:info("HOMIE_DOMAIN5: %s", opts.domain5)
logger:info("HOMIE_MQTT_ID: %s", opts.id)
logger:info("HOMIE_DEVICE_ID: %s", opts.device_id)
logger:info("HOMIE_SUBSCRIBE_DELAY: %s", tostring(opts.subscribe_delay))


copas(function()
  require("homie45")(opts):start()
end)

ll.defaultLogger():info("Homie 4-to-5 bridge exited")
