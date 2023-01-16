--- This Bridge class.
--
-- The bridge will subscribe to all Homie v4 devices, and create equivalent
-- Homie v5 devices. It is designed to work with the Copas scheduler, but will
-- not start the scheduler.
--
-- @classmod Bridge
-- @copyright Copyright (c) 2023-2023 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE.md`.

local Bridge = {}
Bridge._VERSION = "0.0.1"
Bridge._COPYRIGHT = "Copyright (c) 2023-2023 Thijs Schreijer"
Bridge._DESCRIPTION = "Homie bridge for Homie 4 devices to Homie 5"
Bridge.__index = Bridge

require "copas" -- load to have mqtt detect Copas as the loop
local mqtt = require "mqtt"
local log = require("logging").defaultLogger()
local Device = require "homie45.device"
local copas = require "copas"

--- Creates a new bridge instance.
-- @tparam table opts options table
-- @tparam string opts.uri MQTT connection uri, eg. `mqtt://usr:pwd@mqttserver.local:1234`
-- @tparam[opt="homie/"] string opts.domain4 The homie domain for Homie v4
-- @tparam[opt="homie5/"] string opts.domain5 The homie domain for Homie v5
-- @tparam[opt] string opts.id MQTT device id. Defaults to `homie45-bridge-xxxxxxx` randomized.
-- @tparam[opt=1000] number opts.subscribe_delay Delay (milliseconds) between subscribing to
-- discovered devices. This prevents too many topics being queued at once MQTT-server-side such
-- that they might get dropped.
-- @treturn Bridge the newly created instance.
function Bridge.new(opts, empty)
  if empty ~= nil then error("do not call 'new' with colon-notation", 2) end
  assert(type(opts) == "table", "expected an options table as argument")
  assert(type(opts.uri) == "string", "expected opts.uri to be a string")

  local self = {
    uri = opts.uri,
    domain4 = opts.domain4 or "homie/",
    domain5 = opts.domain5 or "homie5/",
    id = opts.id or ("homie45-bridge-%07x"):format(math.random(1, 0xFFFFFFF)),
    started = false,
    devices = nil, -- table; device-object indexed by its id
    subscribe_queue = nil,
    subscribe_delay = (opts.subscribe_delay or 1000)/1000,
    queue_worker = nil,
  }

  -- ensure domains have a trailing slash
  if self.domain4:sub(-1,-1) ~= "/" then
    self.domain4 = self.domain4 .. "/"
  end
  if self.domain5:sub(-1,-1) ~= "/" then
    self.domain5 = self.domain5 .. "/"
  end

  -- create patterns for message matching
  self.DISCOVERY_PATTERN = mqtt.compile_topic_pattern(self.domain4.."+/$state")
  self.MESSAGE_PATTERN = mqtt.compile_topic_pattern(self.domain4.."+/#")
  self.SET_V5_PATTERN = mqtt.compile_topic_pattern(self.domain5.."+/+/+/set")

  self.mqtt = mqtt.client {
    uri = self.uri,
    id = self.id,
    clean = true,
    reconnect = true, -- set to false after first connection
    -- will = {
    --   topic = self.base_topic .. "$state",
    --   payload = self.states.lost,
    --   qos = 1,
    --   retain = true,
    -- }
  }

  return setmetatable(self, Bridge)
end



--- Starts the bridge.
function Bridge:start()
  if self.started then
    return nil, "already started"
  end

  self.clean = true -- restart should be clean
  self.devices = {} -- clean device list
  log:info("[homie45] starting mqtt client '%s'", self.id)

  local queue = copas.queue.new { name = "subscribe_queue_" .. self.id }
  self.subscribe_queue = queue
  queue:add_worker(function(device_id)
    -- honor delay, to prevent overrunning queue mqtt-server side. There is only
    -- one queue worker, so just sleeping will do.
    copas.pause(self.subscribe_delay)
    self.devices[device_id]:start() -- start the device
  end)

  self.mqtt:on {
    connect = function(connack)
      if connack.rc ~= 0 then
        return -- connection failed, exit and wait for reconnect
      end

      -- subscribe to the device discovery topic
      self.mqtt:subscribe {
        topic = self.domain4 .. "+/$state",
        qos = 1,
        -- callback = function(msg)
        -- end,
      }

      self.clean = false -- reconnects should continue and no longer be clean
    end,

    message = function(msg)
      self:message_handler(msg)
    end,
  }

  self.mqtt.opts.clean = self.clean
  require("mqtt.loop").add(self.mqtt)

  return true
end



--- Stops the bridge, disconnects the MQTT client.
function Bridge:stop()
  if not self.started then
    return nil, "not started"
  end

  log:info("[homie45] stopping mqtt client '%s'", self.id)
  self.mqtt:shutdown()
  self.started = false
  return true
end



-- Deal with incomming messages.
function Bridge:message_handler(msg)
  self.mqtt:acknowledge(msg)

  local discovery_id = msg.topic:match(self.DISCOVERY_PATTERN)
  if discovery_id and not self.devices[discovery_id] then
    -- a discovery message ($state), of a device we don't know yet, queue it for creation
    log:info("[homie45] new Homie 4 device found: '%s'", discovery_id)
    self.devices[discovery_id] = Device.new {
      id = discovery_id,
      mqtt = self.mqtt,
      log = log,
      domain4 = self.domain4,
      domain5 = self.domain5,
    }
    self.subscribe_queue:push(discovery_id) -- queue it for starting
  end

  local device_id = msg.topic:match(self.MESSAGE_PATTERN)
  if not device_id then
    device_id = msg.topic:match(self.SET_V5_PATTERN)
  end
  if not device_id then
    log:warn("[homie45] received unknown topic: '%s'", msg.topic)
    return
  end

  local device = self.devices[device_id]
  if not device then
    log:warn("[homie45] received message for unknown device id: '%s'", device)
    return
  end

  device:handle_message(msg)
end



-- calling module table returns a new instance
return setmetatable(Bridge, {
  __call = function(self, ...)
    return self.new(...)
  end,
})
