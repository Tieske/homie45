--- Device class that represents a Homie 4 device discovered, and mirrors it
-- to Homie v5.
-- @classmod Device

local Device = {}
Device.__index = Device

local mqtt = require "mqtt"
local utils = require "pl.utils"
local copas = require "copas"
local socket = require "socket"
local json = require "cjson.safe"
local tablex = require "pl.tablex"

local GO_ONLINE_DELAY = 5  -- after device "seems" complete, wat X secs to ensure we're complete
local PROP_VALUE_KEY = "_value" -- key to use for property value updates

--- Creates a new device instance.
-- @tparam table opts options table
-- @tparam logger opts.log the logger instance to use.
-- @tparam string opts.id MQTT device id of the device to create
-- @tparam mqtt-client opts.mqtt the mqtt client to use
-- @tparam string opts.domain4 the Homie domain for v4
-- @tparam string opts.domain5 the Homie domain for v5
-- @treturn Device the newly created instance.
function Device.new(opts, empty)
  if empty ~= nil then error("do not call 'new' with colon-notation", 2) end
  assert(type(opts) == "table", "expected an options table as argument")
  assert(opts.log, "expected opts.log to be a logger")
  assert(opts.id, "expected opts.id to be a homie 4 device id")
  assert(opts.mqtt, "expected opts.mqtt to be an mqtt device instance")
  assert(opts.domain4, "expected opts.domain4 to be a string")
  assert(opts.domain5, "expected opts.domain5 to be a string")

  local self = setmetatable(opts, Device)
  opts = nil -- luacheck: ignore

  -- structure to store received data
  self.device4 = {}
  self.description_complete = false
  self.device5 = {} -- table representation of v5 device
  self.go_online_at = nil
  self.go_online_timer = nil
  self.started = nil

  -- create patterns for message matching
  self.DEVICE_MESSAGE = mqtt.compile_topic_pattern(self.domain4 .. "/" .. self.id .. "/+")
  self.NODE_MESSAGE = mqtt.compile_topic_pattern(self.domain4 .. "/" .. self.id .. "/+/+")
  self.PROPERTY_MESSAGE = mqtt.compile_topic_pattern(self.domain4 .. "/" .. self.id .. "/+/+/+")
  self.SET_V5_PATTERN = mqtt.compile_topic_pattern(self.domain5 .. "/5/" .. self.id .."/+/+/set")

  self.log:info("[homie45] bridged device '%s' instantiated", self.id)
  return self
end



--- Starts the device.
-- Will subscribe to the device topics (v4) to build the description, and start.
function Device:start()
  -- subscribe to the device topics
  self.mqtt:subscribe {
    topic = self.domain4 .. "/" .. self.id .."/#",
    qos = 1,
    -- callback = function(...) -- TODO: add for error checking
    -- end,
  }
  self.started = true
  self:check_complete()
end



function Device:get_node(node_name)
  local nodes = self.device4.nodes
  if not nodes then
    nodes = {}
    self.device4.nodes = nodes
  end

  local node = nodes[node_name]
  if not node then
    node = {}
    nodes[node_name] = node
    self.description_complete = false
  end
  return node
end



function Device:get_property(node_name, property_name)
  local node = self:get_node(node_name)
  local properties = node.properties
  if not properties then
    properties = {}
    node.properties = properties
  end

  local property = properties[property_name]
  if not property then
    property = {}
    properties[property_name] = property
    self.description_complete = false
  end
  return property
end



function Device:handle_message(msg)
  local topic = msg.topic

  local device_key = topic:match(self.DEVICE_MESSAGE)
  if device_key then
    return self:handle_device_message(device_key, msg)
  end

  local node_name, node_key = topic:match(self.NODE_MESSAGE)
  if node_name then
    if node_key:sub(1,1) == "$" then
      return self:handle_node_message(node_name, node_key, msg)
    else
      return self:handle_property_message(node_name, node_key, PROP_VALUE_KEY, msg)
    end
  end

  local node_name, property_name, property_key = topic:match(self.PROPERTY_MESSAGE)
  if node_name then
    if property_key == "set" then
      return -- we're not copying 'set' commands from v4 to v5 (creates a loop)
    end
    return self:handle_property_message(node_name, property_name, property_key, msg)
  end

  local node_name, property_name = topic:match(self.SET_V5_PATTERN)
  if node_name then
    return self:set_property_value(node_name, property_name, msg)
  end

  self.log:warn("[homie45] '%s' don't know how to handle topic '%s'", self.domain4 .. "/" .. self.id, msg.topic)
end



function Device:handle_device_message(key, msg)
  self.device4[key] = msg.payload
  if key == "$state" then
    self:check_complete()
  end
end



function Device:handle_node_message(node_name, key, msg)
  local node = self:get_node(node_name)
  node[key] = msg.payload
end



function Device:handle_property_message(node_name, property_name, key, msg)
  local property = self:get_property(node_name, property_name)
  property[key] = msg.payload
  if key == PROP_VALUE_KEY then
    self:property_value_update(node_name, property_name, msg)
  elseif key == "set" then
    self:set_property_value(node_name, property_name, msg)
  else
    self:check_complete()
  end
end



function Device:property_value_update(node_name, property_name, msg)
  self.mqtt:publish{
    topic = self.domain5 .. "/5/" .. self.id .. "/" .. node_name .. "/" .. property_name,
    payload = msg.payload,
    qos = msg.qos,
    retain = msg.retain,
  }
end



function Device:set_property_value(node_name, property_name, msg)
  if not msg.payload then -- clearing a topic (see below) then 'payload == nil'
    -- clearing the set topic.
    -- TODO: how to deal with "" payloads, empty strings.
    return
  end

  self.mqtt:publish{
    topic = self.domain4 .. "/" .. self.id .. "/" .. node_name .. "/" .. property_name .. "/set",
    payload = msg.payload,
    qos = msg.qos,
    retain = msg.retain,
  }
  -- clear the command topic
  self.mqtt:publish{
    topic = msg.topic,
    payload = nil,
    qos = msg.qos,
    retain = msg.retain,
  }
end



function Device:check_complete()
  if not self.started then
    return
  end

  local dev4 = self.device4

  if self.description_complete then
    return
  end

  local nodes_string = dev4["$nodes"] or ""
  local nodes = dev4.nodes or {}

  -- check individual nodes
  for _, node_name in ipairs(utils.split(nodes_string, ",")) do
    local node = nodes[node_name]
    if not node then
      return -- incomplete; the node entry is missing
    end

    local properties_string = node["$properties"] or ""
    local properties = node.properties or {}

    -- check individual properties
    for _, prop_name in ipairs(utils.split(properties_string, ",")) do
      local property = properties[prop_name]
      if not property then
        return -- incomplete; the property entry is missing
      end

    end -- property loop

  end -- node loop

  -- looks pretty complete, but not 100% sure, wait for extra delay
  self.go_online_at = socket.gettime() + GO_ONLINE_DELAY
  if not self.go_online_timer then
    self.go_online_timer = copas.timer.new {
      delay = GO_ONLINE_DELAY,
      callback = function(timer)
        if socket.gettime() < self.go_online_at then
          -- there was an update, wait for the new delay to expire
          return timer:arm(self.go_online_at - socket.gettime())
        end

        self:publish()
      end
    }
  end
end


--- Build and publish the v5 device
function Device:publish()
  local dev4 = self.device4
  local dev5 = {
    homie = "5.0",
    nodes = {}, -- will be removed later if it remains empty
    name = dev4["$name"] or self.id,
    parent = nil, -- always nil, since v4 devices have no parents
    children = nil, -- always nil, since v4 devices have no children
    extensions = utils.split(dev4["$extensions"] or "")
  }
  if not next(dev5.extensions) then
    dev5.extensions = nil -- no extensions, so remove it
  end

  local subscriptions = {} -- array with topics to subscribe to

  local nodes4_string = dev4["$nodes"] or ""
  local nodes4 = dev4.nodes or {}

  -- build individual nodes
  for _, node_id in ipairs(utils.split(nodes4_string, ",")) do
    local node4 = nodes4[node_id]
    local node5 = {
      id = node_id,
      name = node4.name or node_id,
      type = node4.type,
      properties = {},
    }
    dev5.nodes[#dev5.nodes + 1] = node5

    local properties4_string = node4["$properties"] or ""
    local properties4 = node4.properties or {}

    -- build individual properties
    for _, prop_id in ipairs(utils.split(properties4_string, ",")) do
      local property4 = properties4[prop_id]
      local property5 = {
        id = prop_id,
        name = property4["$name"] or prop_id,
        datatype = property4["$datatype"] or "string",
        format = property4["$format"],
        unit = property4["$unit"],
        settable = property4["$settable"] == "true",
        retained = property4["$retained"] == "true",
      }
      if not property5.settable then property5.settable = nil end -- don't specify defaults
      if property5.retained then property5.retained = nil end -- don't specify defaults

      if property5.settable then
        subscriptions[#subscriptions + 1] = self.domain5 .. "/5/" .. self.id .. "/" .. node_id .. "/" .. prop_id .. "/set"
      end

      node5.properties[#node5.properties + 1] = property5
    end -- property loop

    if not next(node5.properties) then
      node5.properties = nil -- no properties, so remove it
    end
  end -- node loop

  if not next(dev5.nodes) then
    dev5.nodes = nil -- no nodes, so remove it
  end

  if tablex.deepcompare(self.device5, dev5) then
    -- no changes, nothing to do
    return
  end
  self.device5 = dev5

  -- send device updates
  self.mqtt:publish{
    topic = self.domain5 .. "/5/" .. self.id .. "/$description",
    payload = json.encode(self.device5),
    qos = 1,
    retain = true,
    callback = function()
      -- after confirmation, send state update
      self.description_complete = true
      self.mqtt:publish{
        topic = self.domain5 .. "/5/" .. self.id .. "/$state",
        payload = dev4["$state"],
        qos = 1,
        retain = true,
      }
    end
  }

  -- subscribe to settable topics
  for _, topic in ipairs(subscriptions) do
    self.mqtt:subscribe {
      topic = topic,
      qos = 1,
    }
  end
end


-- calling module table returns a new instance
return setmetatable(Device, {
  __call = function(self, ...)
    return self.new(...)
  end,
})
