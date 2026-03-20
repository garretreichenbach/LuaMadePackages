-- /lib/network.lua
-- CargoControl Network Layer
-- Builds a typed message protocol on top of the LuaMade net API.
-- The dashboard computer uses this as a hub; ship computers use the same
-- protocol to send heartbeats and receive commands.
--
-- Protocol:  all messages are JSON-encoded tables with a top-level "type" key.
-- Transport: global channel (multi-sector) for control/status,
--            direct net.send() for node-to-node unicast,
--            private channels for fleet and shipyard command streams.

local Network = {}
Network.__index = Network

-- ============================================================================
-- Message type constants
-- ============================================================================

Network.MSG = {
    -- Ship -> Hub
    HEARTBEAT          = "HEARTBEAT",           -- Periodic status report from a ship computer.
    SHIPYARD_HEARTBEAT = "SHIPYARD_HEARTBEAT",  -- Periodic status report from a shipyard computer.
    -- Hub -> Node
    CMD_MOVE           = "CMD_MOVE",            -- Legacy direct ship move command.
    CMD_DOCK           = "CMD_DOCK",            -- Legacy direct ship dock command.
    CMD_REPAIR         = "CMD_REPAIR",          -- Legacy direct ship repair command.
    CMD_IDLE           = "CMD_IDLE",            -- Legacy direct ship idle command.
    CMD_CARGO          = "CMD_CARGO",           -- Legacy direct ship cargo command.
    CMD_FLEET          = "CMD_FLEET",           -- { command, args }
    CMD_SHIPYARD       = "CMD_SHIPYARD",        -- { command, args }
    -- Bidirectional
    ACK                = "ACK",                 -- { refMsgType, ok, reason }
    DISCOVERY          = "DISCOVERY",           -- Hub broadcasts; ships reply with HEARTBEAT.
}

-- ============================================================================
-- Constructor
-- ============================================================================

-- cfg: config table with .hostname and .broadcastChannel
function Network.new(cfg)
    local self = setmetatable({}, Network)
    self.hostname = cfg.hostname or "cargocontrol-hub"
    self.channel  = cfg.broadcastChannel or "cargocontrol"

    net.setHostname(self.hostname)
    net.openChannel(self.channel, "")

    return self
end

-- ============================================================================
-- Internal helpers
-- ============================================================================

local function encode(msgType, payload)
    local envelope = { type = msgType, payload = payload or {} }
    local ok, encoded = pcall(json.encode, envelope)
    if ok then
        return encoded
    end
    return nil
end

local function decode(raw)
    if not raw then
        return nil
    end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == "table" and data.type then
        return data
    end
    return nil
end

-- ============================================================================
-- Sending
-- ============================================================================

-- Broadcast to all nodes on the shared channel.
function Network:broadcast(msgType, payload)
    local encoded = encode(msgType, payload)
    if encoded then
        net.sendChannel(self.channel, "", encoded)
    end
end

-- Send directly to a named host.
function Network:send(targetHostname, msgType, payload)
    local encoded = encode(msgType, payload)
    if encoded then
        net.send(targetHostname, "cc", encoded)
    end
end

-- Send to a private channel used by a fleet or shipyard node app.
function Network:sendPrivate(channelName, password, msgType, payload)
    local encoded = encode(msgType, payload)
    if encoded then
        net.sendChannel(channelName, password or "", encoded)
    end
end

-- Broadcast a DISCOVERY ping so all ships send back a HEARTBEAT.
function Network:discover()
    self:broadcast(Network.MSG.DISCOVERY, { from = self.hostname })
end

-- Send a movement command to a specific ship.
function Network:cmdMove(hostname, sector)
    self:send(hostname, Network.MSG.CMD_MOVE, { sector = sector })
end

function Network:cmdDock(hostname, stationHostname)
    self:send(hostname, Network.MSG.CMD_DOCK, { stationHostname = stationHostname })
end

function Network:cmdRepair(hostname)
    self:send(hostname, Network.MSG.CMD_REPAIR, {})
end

function Network:cmdIdle(hostname)
    self:send(hostname, Network.MSG.CMD_IDLE, {})
end

function Network:cmdCargo(hostname, pickupHostname, dropHostname)
    self:send(hostname, Network.MSG.CMD_CARGO, {
        pickup = pickupHostname,
        drop   = dropHostname,
    })
end

function Network:cmdFleet(channelName, password, command, args)
    self:sendPrivate(channelName, password, Network.MSG.CMD_FLEET, {
        command = command,
        args    = args or {},
    })
end

function Network:cmdShipyard(channelName, password, command, args)
    self:sendPrivate(channelName, password, Network.MSG.CMD_SHIPYARD, {
        command = command,
        args    = args or {},
    })
end

-- ============================================================================
-- Receiving (non-blocking poll, call each frame or on timer)
-- ============================================================================

-- Returns the next decoded message from the broadcast channel, or nil.
function Network:receiveChannel()
    if net.hasChannelMessage(self.channel) then
        local msg = net.receiveChannel(self.channel)
        if msg then
            return decode(msg.getContent())
        end
    end
    return nil
end

-- Returns the next decoded direct message (protocol "cc"), or nil.
function Network:receiveDirect()
    if net.hasMessage("cc") then
        local msg = net.receive("cc")
        if msg then
            local data = decode(msg.getContent())
            if data then
                data._sender = msg.getSender()
            end
            return data
        end
    end
    return nil
end

-- Drains all pending messages, returns them as a list.
-- Handles both channel and direct messages.
function Network:drainMessages()
    local messages = {}

    local maxPerCall = 32  -- safety cap per frame to avoid starvation
    local count = 0

    while count < maxPerCall do
        local msg = self:receiveChannel()
        if msg then
            table.insert(messages, msg)
            count = count + 1
        else
            break
        end
    end

    count = 0
    while count < maxPerCall do
        local msg = self:receiveDirect()
        if msg then
            table.insert(messages, msg)
            count = count + 1
        else
            break
        end
    end

    return messages
end

-- ============================================================================
-- Message dispatch helper
-- ============================================================================

-- Calls handler(msg) for each message whose type matches the handlers table.
-- handlers: { [MSG_TYPE] = function(msg) ... end }
function Network:dispatch(messages, handlers)
    for _, msg in ipairs(messages) do
        local handler = handlers[msg.type]
        if handler then
            handler(msg)
        end
    end
end

return Network
