-- /lib/request_manager.lua
-- CargoControl Request Manager
-- Manages the lifecycle of cargo/logistics requests:
--   PENDING -> ASSIGNED -> IN_TRANSIT -> COMPLETE | FAILED
-- Requests are persisted to disk so they survive computer restarts.

local RequestManager = {}
RequestManager.__index = RequestManager

local REQUESTS_FILE = "/home/cargocontrol/requests.json"

-- Request status constants.
RequestManager.STATUS = {
    PENDING   = "PENDING",
    ASSIGNED  = "ASSIGNED",
    IN_TRANSIT = "IN_TRANSIT",
    COMPLETE  = "COMPLETE",
    FAILED    = "FAILED",
    CANCELLED = "CANCELLED",
}

-- Request type constants.
RequestManager.TYPE = {
    CARGO    = "CARGO",    -- Move cargo from source to destination.
    REPAIR   = "REPAIR",   -- Send ship to shipyard for repairs.
    RESUPPLY = "RESUPPLY", -- Replenish a base's inventory.
    CUSTOM   = "CUSTOM",   -- Free-form command issued to a fleet.
}

-- ============================================================================
-- Internal helpers
-- ============================================================================

local function readJSON(path)
    if not fs.exists(path) then
        return nil
    end
    local raw = fs.read(path)
    if not raw or raw == "" then
        return nil
    end
    local ok, data = pcall(json.decode, raw)
    if ok then
        return data
    end
    return nil
end

local function writeJSON(path, data)
    if not fs.exists("/home/cargocontrol") then
        fs.makeDir("/home/cargocontrol")
    end
    local ok, encoded = pcall(json.encode, data)
    if ok then
        fs.write(path, encoded)
        return true
    end
    return false
end

local function nextId(rm)
    rm._nextId = (rm._nextId or 0) + 1
    return rm._nextId
end

-- ============================================================================
-- Constructor
-- ============================================================================

function RequestManager.new(historyLimit)
    local self = setmetatable({}, RequestManager)
    self.requests    = {}   -- id -> request table (active + recent history)
    self._nextId     = 0
    self.historyLimit = historyLimit or 50
    self:load()
    return self
end

-- ============================================================================
-- Persistence
-- ============================================================================

function RequestManager:save()
    -- Persist all non-completed requests plus up to historyLimit completed ones.
    local toSave  = {}
    local history = {}

    for _, req in pairs(self.requests) do
        local s = req.status
        if s == RequestManager.STATUS.COMPLETE
        or s == RequestManager.STATUS.FAILED
        or s == RequestManager.STATUS.CANCELLED then
            table.insert(history, req)
        else
            table.insert(toSave, req)
        end
    end

    -- Sort history by completedAt descending, keep most recent up to limit.
    table.sort(history, function(a, b)
        return (a.completedAt or 0) > (b.completedAt or 0)
    end)
    for i = 1, math.min(#history, self.historyLimit) do
        table.insert(toSave, history[i])
    end

    writeJSON(REQUESTS_FILE, { nextId = self._nextId, requests = toSave })
end

function RequestManager:load()
    local data = readJSON(REQUESTS_FILE)
    if not data then
        return
    end
    self._nextId = data.nextId or 0
    if data.requests then
        for _, req in ipairs(data.requests) do
            self.requests[req.id] = req
        end
    end
end

-- ============================================================================
-- Request creation
-- ============================================================================

-- Creates and queues a new request. Returns the request table.
-- params: { type, source, destination, cargo, fleetId, notes }
function RequestManager:createRequest(params)
    local id = nextId(self)
    local req = {
        id          = id,
        type        = params.type        or RequestManager.TYPE.CARGO,
        status      = RequestManager.STATUS.PENDING,
        source      = params.source      or nil,
        destination = params.destination or nil,
        -- cargo: list of { itemId, targetCount } for CARGO/RESUPPLY requests.
        cargo       = params.cargo       or {},
        -- fleetId: assigned after fleet_manager picks up the request.
        fleetId     = params.fleetId     or nil,
        notes       = params.notes       or "",
        createdAt   = os.time and os.time() or 0,
        updatedAt   = os.time and os.time() or 0,
        completedAt = nil,
    }
    self.requests[id] = req
    self:save()
    return req
end

-- ============================================================================
-- Status transitions
-- ============================================================================

function RequestManager:_transition(id, newStatus, extraFields)
    local req = self.requests[id]
    if not req then
        return false, "request not found: " .. tostring(id)
    end
    req.status    = newStatus
    req.updatedAt = os.time and os.time() or 0
    if newStatus == RequestManager.STATUS.COMPLETE
    or newStatus == RequestManager.STATUS.FAILED
    or newStatus == RequestManager.STATUS.CANCELLED then
        req.completedAt = req.updatedAt
    end
    if extraFields then
        for k, v in pairs(extraFields) do
            req[k] = v
        end
    end
    self:save()
    return true
end

function RequestManager:assign(id, fleetId)
    return self:_transition(id, RequestManager.STATUS.ASSIGNED, { fleetId = fleetId })
end

function RequestManager:markInTransit(id)
    return self:_transition(id, RequestManager.STATUS.IN_TRANSIT)
end

function RequestManager:complete(id)
    return self:_transition(id, RequestManager.STATUS.COMPLETE)
end

function RequestManager:fail(id, reason)
    return self:_transition(id, RequestManager.STATUS.FAILED, { failReason = reason })
end

function RequestManager:cancel(id)
    return self:_transition(id, RequestManager.STATUS.CANCELLED)
end

-- ============================================================================
-- Queries
-- ============================================================================

function RequestManager:get(id)
    return self.requests[id]
end

-- Returns all requests matching optional filter { status, type, fleetId }.
function RequestManager:query(filter)
    local results = {}
    for _, req in pairs(self.requests) do
        local match = true
        if filter then
            if filter.status  and req.status  ~= filter.status  then match = false end
            if filter.type    and req.type    ~= filter.type    then match = false end
            if filter.fleetId and req.fleetId ~= filter.fleetId then match = false end
        end
        if match then
            table.insert(results, req)
        end
    end
    -- Newest first.
    table.sort(results, function(a, b) return a.createdAt > b.createdAt end)
    return results
end

function RequestManager:getPending()
    return self:query({ status = RequestManager.STATUS.PENDING })
end

function RequestManager:getActive()
    local active = {}
    for _, req in pairs(self.requests) do
        local s = req.status
        if s == RequestManager.STATUS.ASSIGNED
        or s == RequestManager.STATUS.IN_TRANSIT then
            table.insert(active, req)
        end
    end
    table.sort(active, function(a, b) return a.createdAt > b.createdAt end)
    return active
end

function RequestManager:countByStatus()
    local counts = {}
    for _, s in pairs(RequestManager.STATUS) do
        counts[s] = 0
    end
    for _, req in pairs(self.requests) do
        counts[req.status] = (counts[req.status] or 0) + 1
    end
    return counts
end

return RequestManager
