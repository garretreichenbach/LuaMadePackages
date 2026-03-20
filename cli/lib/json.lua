-- lib/json.lua
-- Thin wrapper around dkjson (https://dkolf.de/src/dkjson-lua.fsl/).
-- Install via: luarocks install dkjson
--
-- Exposes:
--   json.encode(value)        -> string
--   json.decode(string)       -> value

local ok, dkjson = pcall(require, "dkjson")
if not ok then
  error(
    "dkjson is required for JSON support.\n" ..
    "Install it with:  luarocks install dkjson"
  )
end

local M = {}

function M.encode(value)
  return dkjson.encode(value, { indent = true })
end

function M.decode(str)
  local value, pos, err = dkjson.decode(str, 1, nil)
  if err then
    error("JSON decode error: " .. tostring(err) .. " at position " .. tostring(pos))
  end
  return value
end

return M
