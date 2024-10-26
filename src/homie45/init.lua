--- This Bridge class.
--
-- The bridge will subscribe to all Homie v4 devices, and create equivalent
-- Homie v5 devices. It is designed to work with the Copas scheduler, but will
-- not start the scheduler.
--
-- @classmod Bridge
-- @copyright Copyright (c) 2023-2024 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE.md`.

local Bridge = {}
Bridge._VERSION = "0.2.0"
Bridge._COPYRIGHT = "Copyright (c) 2023-2024 Thijs Schreijer"
Bridge._DESCRIPTION = "Homie bridge for Homie 4 devices to Homie 5"
Bridge.__index = Bridge

local copas = require("copas") -- load first to have mqtt detect Copas as the loop
local socket = require "socket"
local mqtt = require "mqtt"
local log = require("logging").defaultLogger()
local Device = require "homie45.device"

--- Creates a new bridge instance.
-- @tparam table opts options table
-- @tparam string opts.uri MQTT connection uri, eg. `mqtt://usr:pwd@mqttserver.local:1234`
-- @tparam[opt="homie"] string opts.domain4 The homie domain for Homie v4
-- @tparam[opt="homie"] string opts.domain5 The homie domain for Homie v5
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
    domain4 = opts.domain4 or "homie",
    domain5 = opts.domain5 or "homie",
    id = opts.id or ("homie45-bridge-%07x"):format(math.random(1, 0xFFFFFFF)),
    started = false,
    devices = nil, -- table; device-object indexed by its id
    subscribe_queue = nil,
    subscribe_delay = (opts.subscribe_delay or 1000)/1000,
    desc_update_delay = (opts.subscribe_delay or 1000)/1000 + 0.5, -- delay for description update
    queue_worker = nil,
    device_id = "homie45-bridge",
  }

  -- ensure domains have no trailing slash
  if self.domain4:sub(-1,-1) == "/" then
    self.domain4 = self.domain4:sub(1,-2)
  end
  if self.domain5:sub(-1,-1) == "/" then
    self.domain5 = self.domain5:sub(1,-2)
  end

  -- create patterns for message matching
  self.DISCOVERY_PATTERN = mqtt.compile_topic_pattern(self.domain4 .. "/+/$state")
  self.MESSAGE_PATTERN = mqtt.compile_topic_pattern(self.domain4 .. "/+/#")
  self.SET_V5_PATTERN = mqtt.compile_topic_pattern(self.domain5 .. "/5/+/+/+/set")

  self.mqtt = mqtt.client {
    uri = self.uri,
    id = self.id,
    clean = true, -- set to false after first connection
    reconnect = true,
    will = {
      topic = self.domain5 .. "/5/" .. self.device_id .. "/$state",
      payload = "lost",
      qos = 1,
      retain = true,
    }
  }

  return setmetatable(self, Bridge)
end



--- Starts the bridge.
function Bridge:start()
  if self.started then
    return nil, "already started"
  end

  self.devices = {} -- clean device list
  self.description_changed = true
  self.description = {
    name = "Homie v4 to v5 bridge",
    homie = "5.0",
    version = nil, -- will be set on publishing
    children = {}
  }
  log:info("[homie45] starting mqtt client '%s'", self.id)

  local queue = copas.queue.new { name = "subscribe_queue_" .. self.id }
  self.subscribe_queue = queue
  queue:add_worker(function(device_id)
    -- honor delay, to prevent overrunning queue mqtt-server side. There is only
    -- one queue worker, so just sleeping will do.
    copas.pause(self.subscribe_delay)
    self.devices[device_id]:start() -- start the device
    -- add device to our child list
    self.description.children[#self.description.children + 1] = device_id
    self.description_changed = true
    self:updateDescription()
  end)

  self.mqtt:on {
    connect = function(connack)
      if connack.rc ~= 0 then
        return -- connection failed, exit and wait for reconnect
      end

      -- subscribe to the device discovery topic
      self.mqtt:subscribe {
        topic = self.domain4 .. "/+/$state",
        qos = 1,
        -- callback = function(msg)
        -- end,
      }
      return self:updateDescription()
    end,

    message = function(msg)
      self:message_handler(msg)
    end,
  }

  self.mqtt.opts.clean = "first" -- only start clean on first connect, not reconnects
  require("mqtt.loop").add(self.mqtt)

  return true
end



function Bridge:updateDescription()
  if not self.description_changed then
    return
  end

  -- post description delayed, to catch multiple updates in one go
  log:info("[homie45] initiating root-device description update (if stable for %.1f seconds)", self.desc_update_delay)
  self.descriptionPostTime = socket.gettime() + self.desc_update_delay

  -- set state to "init", because we're updating our description
  self.mqtt:publish {
    topic = self.domain5 .. "/5/" .. self.device_id .. "/$state",
    payload = "init",
    qos = 1,
    retain = true,
  }

  if not self.descriptionPostTimer then
    -- create a new timer, since we do not have one yet
    self.descriptionPostTimer = copas.timer.new {
      delay = self.desc_update_delay,
      callback = function()
        -- if postTime was updated, then reschedule timer
        if self.descriptionPostTime > socket.gettime() then
          self.descriptionPostTimer:arm(self.descriptionPostTime - socket.gettime()) -- postpone execution
          return
        end
        -- we're up, execute it
        self.descriptionPostTimer = nil
        self.descriptionPostTime = nil
        self:postDescription()
      end
    }
  end
end



function Bridge:updateVersion()
  local v = tonumber(self.description.version)
  if not v then
    local b1, b2 = string.byte(require("system").random(2), 1, 2)
    v = b1 * 256 + b2
  else
    v = (v + 1) % 65536
  end
  self.description.version = string.format("%d", v)
end



-- Unconditionally posts the device description, and sets state to Ready.
function Bridge:postDescription()
  self:updateVersion()
  local payload = require("cjson").encode(self.description)

  -- publish description
  self.description_changed = false  -- before publishing, since publishing might yield!!
  self.mqtt:publish {
    topic = self.domain5 .. "/5/" .. self.device_id .. "/$description",
    payload = payload,
    qos = 1,
    retain = true,
  }

  log:info("[homie45] root-device '%s' description update posted, version %s",
            self.device_id, self.description.version)

  -- set state to "ready"
  self.mqtt:publish {
    topic = self.domain5 .. "/5/" .. self.device_id .. "/$state",
    payload = "ready",
    qos = 1,
    retain = true,
  }
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

  if discovery_id and not msg.payload then
    -- device is being deleted, since $state topic is empty
    local device = self.devices[discovery_id]
    if device then
      log:info("[homie45] Homie 4 device '%s' is being deleted", discovery_id)
      for i, child_id in ipairs(device.description.children) do
        if child_id == discovery_id then
          table.remove(device.description.children) -- remove device from our child list
          self.description_changed = true
          break
        end
      end
      self:updateDescription()
      device:destroy()
      self.devices[discovery_id] = nil
    end
    return
  end

  if discovery_id and not self.devices[discovery_id] then
    -- a discovery message ($state), of a device we don't know yet, queue it for creation
    log:info("[homie45] new Homie 4 device found: '%s'", discovery_id)
    self.devices[discovery_id] = Device.new {
      id = discovery_id,
      mqtt = self.mqtt,
      log = log,
      domain4 = self.domain4,
      domain5 = self.domain5,
      parent_id = self.device_id,
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
    log:warn("[homie45] received message for unknown device id: '%s'", device_id)
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
