-- /lib/fleet_manager.lua
-- CargoControl Fleet Manager
-- Tracks known fleets and ships, polls live status from the game API,
-- and assigns fleets to pending requests.
-- Relies on: Entity API, Fleet API, Shipyard API, request_manager.lua

local Config = require("/LuaMade/CargoControl/config")

local FleetManager = {}
FleetManager.__index = FleetManager

-- Ship/fleet status values surfaced to the dashboard.
FleetManager.SHIP_STATUS = {
    UNKNOWN   = "UNKNOWN",
    IDLE      = "IDLE",
    IN_TRANSIT = "IN_TRANSIT",
    DOCKED    = "DOCKED",
    REPAIRING = "REPAIRING",
    ASSIGNED  = "ASSIGNED",
}

-- ============================================================================
-- Constructor
-- ============================================================================

-- entity: the Entity object for the station/ship this computer lives on.
-- requestManager: RequestManager instance.
-- network: Network instance used to dispatch remote commands to ships.
function FleetManager.new(entity, requestManager, network)
    local self = setmetatable({}, FleetManager)
    self.entity         = entity
    self.requestManager = requestManager
    self.network        = network  -- may be nil; set later via :setNetwork()
    self.fleetBindings  = Config.loadFleetBindings()

    -- id -> { id, name, sector, members, status, assignedRequestId,
    --         flagship, reactorHP, reactorMaxHP, homeBaseName }
    self.fleets = {}

    -- hostname -> { hostname, fleetId, status, sector, cargoInventory }
    -- Populated by network heartbeats from ship-side computers.
    self.ships  = {}

    -- hostname -> { hostname, baseName, sector, isDocked, completion, needed }
    -- Populated by network heartbeats from shipyard computers.
    self.shipyards = {}

    return self
end

-- ============================================================================
-- Fleet polling (call periodically from main loop)
-- ============================================================================

-- Refreshes fleet data by querying nearby entities through the game API.
-- Only fleets/ships belonging to the same faction as the host entity are tracked.
function FleetManager:poll()
    if not self.entity then
        return
    end

    local nearby    = self.entity.getNearbyEntities(3) or {}

    -- Collect all fleet IDs we can see.
    local seenFleets = {}
    for _, remote in ipairs(nearby) do
        if remote.isInFleet and remote.isInFleet() then
            local fleet = remote.getFleet and remote.getFleet()
            if fleet then
                local fid = fleet.getId()
                if not seenFleets[fid] then
                    seenFleets[fid] = fleet
                end
            end
        end
    end

    -- Update internal fleet records.
    for fid, fleet in pairs(seenFleets) do
        local flagship = fleet.getFlagship()
        local record   = self.fleets[fid] or { id = fid, assignedRequestId = nil }
        local binding  = self.fleetBindings[tostring(fid)] or {}

        record.name    = fleet.getName()
        record.sector  = fleet.getSector()
        record.homeBaseName = binding.homeBaseName
        record.commandChannel = binding.commandChannel

        -- Collect member summaries.
        local members = {}
        for _, member in ipairs(fleet.getMembers() or {}) do
            table.insert(members, {
                name    = member.getName and member.getName() or "?",
                sector  = member.getSector and member.getSector() or nil,
            })
        end
        record.members = members

        -- Flagship reactor health if available.
        if flagship then
            record.flagship = flagship.getName and flagship.getName() or nil
            -- RemoteEntity does not expose systems directly; reactor HP comes
            -- from network heartbeats when a ship computer reports in.
        end

        -- Derive a coarse status from command.
        local cmd = fleet.getCurrentCommand and fleet.getCurrentCommand()
        if cmd then
            local cmdName = type(cmd) == "table" and (cmd.getCommand and cmd.getCommand() or tostring(cmd)) or tostring(cmd)
            if cmdName == "IDLE" then
                record.status = FleetManager.SHIP_STATUS.IDLE
            elseif cmdName == "REPAIR" then
                record.status = FleetManager.SHIP_STATUS.REPAIRING
            else
                record.status = FleetManager.SHIP_STATUS.IN_TRANSIT
            end
        elseif record.assignedRequestId then
            record.status = FleetManager.SHIP_STATUS.ASSIGNED
        else
            record.status = FleetManager.SHIP_STATUS.IDLE
        end

        self.fleets[fid] = record
    end
end

-- ============================================================================
-- Ship heartbeat (called by network layer when a ship reports in)
-- ============================================================================

-- data: { hostname, fleetId, status, sector, reactorHP, reactorMaxHP,
--         cargoVolume, cargoFull }
function FleetManager:applyHeartbeat(data)
    if not data or not data.hostname then
        return
    end

    if data.nodeType == "SHIPYARD" then
        local record = self.shipyards[data.hostname] or {}
        for k, v in pairs(data) do
            record[k] = v
        end
        record.lastSeen = os.time and os.time() or 0
        self.shipyards[data.hostname] = record
        return
    end

    local record = self.ships[data.hostname] or {}
    for k, v in pairs(data) do
        record[k] = v
    end
    record.lastSeen = os.time and os.time() or 0
    self.ships[data.hostname] = record
end

-- ============================================================================
-- Shipyard polling
-- ============================================================================

-- Returns the most recent shipyard heartbeats received from remote shipyard
-- controller nodes.
function FleetManager:getShipyardStatus()
    local results = {}
    for _, yard in pairs(self.shipyards) do
        table.insert(results, yard)
    end
    table.sort(results, function(a, b)
        local left = a.baseName or a.hostname or ""
        local right = b.baseName or b.hostname or ""
        return left < right
    end)
    return results
end

-- ============================================================================
-- Assignment
-- ============================================================================

-- Finds the first idle fleet and assigns it to requestId.
-- Returns the fleet record on success, nil otherwise.
function FleetManager:assignFleet(requestId)
    for fid, fleet in pairs(self.fleets) do
        if fleet.status == FleetManager.SHIP_STATUS.IDLE
        and not fleet.assignedRequestId then
            fleet.assignedRequestId = requestId
            fleet.status            = FleetManager.SHIP_STATUS.ASSIGNED
            self.requestManager:assign(requestId, fid)
            return fleet
        end
    end
    return nil
end

-- Releases a fleet back to IDLE and clears its request association.
function FleetManager:releaseFleet(fleetId)
    local fleet = self.fleets[fleetId]
    if fleet then
        fleet.assignedRequestId = nil
        fleet.status            = FleetManager.SHIP_STATUS.IDLE
    end
end

-- ============================================================================
-- Command dispatch
-- ============================================================================

-- Allows late injection of the Network instance (e.g. after construction).
function FleetManager:setNetwork(network)
    self.network = network
end

local function _fleetBindingKey(fleetId)
    return tostring(fleetId)
end

function FleetManager:_saveFleetBindings()
    return Config.saveFleetBindings(self.fleetBindings)
end

function FleetManager:_ensureFleetBinding(fleetId)
    local key = _fleetBindingKey(fleetId)
    local binding = self.fleetBindings[key]
    if not binding then
        binding = { fleetId = fleetId }
        self.fleetBindings[key] = binding
    end
    return binding
end

function FleetManager:getFleetBinding(fleetId)
    return self.fleetBindings[_fleetBindingKey(fleetId)]
end

function FleetManager:setFleetCommandChannel(fleetId, channelName, password)
    local binding = self:_ensureFleetBinding(fleetId)
    binding.commandChannel = channelName
    binding.commandPassword = password or ""
    if self.fleets[fleetId] then
        self.fleets[fleetId].commandChannel = channelName
    end
    return self:_saveFleetBindings()
end

function FleetManager:setFleetHomeBase(fleetId, baseName)
    local binding = self:_ensureFleetBinding(fleetId)
    binding.homeBaseName = baseName
    if self.fleets[fleetId] then
        self.fleets[fleetId].homeBaseName = baseName
    end
    return self:_saveFleetBindings()
end

function FleetManager:clearFleetHomeBase(fleetId)
    local binding = self:_ensureFleetBinding(fleetId)
    binding.homeBaseName = nil
    if self.fleets[fleetId] then
        self.fleets[fleetId].homeBaseName = nil
    end
    return self:_saveFleetBindings()
end

function FleetManager:getFleetHomeBase(fleetId)
    local binding = self:getFleetBinding(fleetId)
    return binding and binding.homeBaseName or nil
end

local function _resolveHomeBase(fleetBindings, fleetId)
    local binding = fleetBindings[_fleetBindingKey(fleetId)]
    if not binding or not binding.homeBaseName then
        return nil, "no home base configured"
    end

    local bases = Config.loadBases()
    local base = bases[binding.homeBaseName]
    if not base then
        return nil, "home base not found"
    end
    return base
end

function FleetManager:_fleetCommandEndpoint(fleetId)
    local binding = self:getFleetBinding(fleetId)
    if not binding or not binding.commandChannel then
        return nil, nil, "no fleet command channel configured"
    end
    return binding.commandChannel, binding.commandPassword or ""
end

function FleetManager:sendFleetCommand(fleetId, command, args)
    if not self.network then
        return false, "no network"
    end
    local channelName, password, err = self:_fleetCommandEndpoint(fleetId)
    if not channelName then
        return false, err
    end
    self.network:cmdFleet(channelName, password, command, args)
    return true
end

function FleetManager:sendFleetToSector(fleetId, sector)
    return self:sendFleetCommand(fleetId, "MOVE_FLEET", { sector = sector })
end

function FleetManager:sendFleetRepair(fleetId)
    local base, err = _resolveHomeBase(self.fleetBindings, fleetId)
    if not base then
        return false, err
    end

    local ok, reason = self:sendFleetCommand(fleetId, "REPAIR", {
        mode = "SHIPYARD",
        homeBaseName = base.name,
        targetSector = base.sector,
        shipyardHostname = base.hostname,
    })
    if not ok then
        return false, reason
    end

    if base.commandChannel then
        self.network:cmdShipyard(base.commandChannel, base.commandPassword or "", "PREPARE_FLEET_SERVICE", {
            fleetId = fleetId,
            fleetName = self.fleets[fleetId] and self.fleets[fleetId].name or nil,
            homeBaseName = base.name,
        })
    end

    return true
end

function FleetManager:sendFleetIdle(fleetId)
    return self:sendFleetCommand(fleetId, "IDLE", {})
end

-- ============================================================================
-- Queries
-- ============================================================================

function FleetManager:getFleetList()
    local list = {}
    for _, f in pairs(self.fleets) do
        table.insert(list, f)
    end
    table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return list
end

function FleetManager:countByStatus()
    local counts = {}
    for _, s in pairs(FleetManager.SHIP_STATUS) do
        counts[s] = 0
    end
    for _, f in pairs(self.fleets) do
        counts[f.status] = (counts[f.status] or 0) + 1
    end
    return counts
end

function FleetManager:getIdleCount()
    return self:countByStatus()[FleetManager.SHIP_STATUS.IDLE] or 0
end

return FleetManager
