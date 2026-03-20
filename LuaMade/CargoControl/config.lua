-- /lib/config.lua
-- CargoControl Configuration Manager
-- Persists settings and named entity registries to the virtual filesystem.
-- All data is stored as JSON under /home/cargocontrol/.

local Config = {}

local CONFIG_DIR  = "/home/cargocontrol"
local CONFIG_FILE = CONFIG_DIR .. "/config.json"
local BASES_FILE  = CONFIG_DIR .. "/bases.json"
local ROUTES_FILE = CONFIG_DIR .. "/routes.json"
local FLEETS_FILE = CONFIG_DIR .. "/fleets.json"

-- ============================================================================
-- Defaults
-- ============================================================================

local DEFAULTS = {
    hostname       = "cargocontrol-01",
    -- Network channel that all CargoControl nodes subscribe to.
    broadcastChannel = "cargocontrol",
    -- How often (seconds) the fleet manager polls ship status.
    pollIntervalSec = 10,
    -- How many completed requests to keep in history before pruning.
    requestHistoryLimit = 50,
}

-- ============================================================================
-- Internal helpers
-- ============================================================================

local function ensureDir()
    if not fs.exists(CONFIG_DIR) then
        fs.makeDir(CONFIG_DIR)
    end
end

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
    ensureDir()
    local ok, encoded = pcall(json.encode, data)
    if ok then
        fs.write(path, encoded)
        return true
    end
    return false
end

-- ============================================================================
-- Config: general settings
-- ============================================================================

function Config.load()
    local saved = readJSON(CONFIG_FILE)
    if saved then
        -- Merge saved values over defaults so new keys always appear.
        for k, v in pairs(DEFAULTS) do
            if saved[k] == nil then
                saved[k] = v
            end
        end
        return saved
    end
    return Config.defaults()
end

function Config.defaults()
    local copy = {}
    for k, v in pairs(DEFAULTS) do
        copy[k] = v
    end
    return copy
end

function Config.save(cfg)
    return writeJSON(CONFIG_FILE, cfg)
end

-- ============================================================================
-- Bases: named entity registry
-- { name, entityId, sector, inventoryName, nodeType, hostname,
--   commandChannel, commandPassword }
-- ============================================================================

function Config.loadBases()
    return readJSON(BASES_FILE) or {}
end

function Config.saveBases(bases)
    return writeJSON(BASES_FILE, bases)
end

function Config.addBase(bases, name, entityId, sector, inventoryName, opts)
    if type(inventoryName) == "table" and opts == nil then
        opts = inventoryName
        inventoryName = nil
    end
    opts = opts or {}

    bases[name] = {
        name          = name,
        entityId      = entityId,
        sector        = sector,
        inventoryName = inventoryName or "Cargo",
        nodeType      = opts.nodeType or "STATION",
        hostname      = opts.hostname or nil,
        commandChannel = opts.commandChannel or nil,
        commandPassword = opts.commandPassword or nil,
    }
    return Config.saveBases(bases)
end

function Config.removeBase(bases, name)
    bases[name] = nil
    return Config.saveBases(bases)
end

-- ============================================================================
-- Fleet bindings: per-fleet remote control and home-base assignments
-- { [fleetId] = { fleetId, homeBaseName, commandChannel, commandPassword } }
-- ============================================================================

function Config.loadFleetBindings()
    return readJSON(FLEETS_FILE) or {}
end

function Config.saveFleetBindings(bindings)
    return writeJSON(FLEETS_FILE, bindings)
end

function Config.getFleetBinding(bindings, fleetId)
    return bindings[tostring(fleetId)]
end

function Config.setFleetBinding(bindings, fleetId, data)
    local key = tostring(fleetId)
    local binding = bindings[key] or { fleetId = fleetId }
    for k, v in pairs(data or {}) do
        binding[k] = v
    end
    binding.fleetId = binding.fleetId or fleetId
    bindings[key] = binding
    return Config.saveFleetBindings(bindings)
end

function Config.removeFleetBinding(bindings, fleetId)
    bindings[tostring(fleetId)] = nil
    return Config.saveFleetBindings(bindings)
end

-- ============================================================================
-- Routes: static source→destination pairs with optional cargo requirements
-- { name, source, destination, cargo = { {itemId, minCount}, ... } }
-- ============================================================================

function Config.loadRoutes()
    return readJSON(ROUTES_FILE) or {}
end

function Config.saveRoutes(routes)
    return writeJSON(ROUTES_FILE, routes)
end

function Config.addRoute(routes, name, source, destination, cargo)
    routes[name] = {
        name        = name,
        source      = source,
        destination = destination,
        cargo       = cargo or {},
    }
    return Config.saveRoutes(routes)
end

function Config.removeRoute(routes, name)
    routes[name] = nil
    return Config.saveRoutes(routes)
end

return Config
