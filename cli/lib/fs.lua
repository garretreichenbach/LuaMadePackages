-- lib/fs.lua
-- Minimal filesystem utilities for lpm.

local M = {}

local is_windows = package.config:sub(1,1) == "\\"

-- ---------------------------------------------------------------------------
-- join – join path segments using the OS separator
-- ---------------------------------------------------------------------------
function M.join(...)
  local sep = is_windows and "\\" or "/"
  local parts = { ... }
  local result = ""
  for i, part in ipairs(parts) do
    if i == 1 then
      result = part
    else
      -- Strip trailing separator from result and leading separator from part.
      result = result:gsub("[/\\]$", "") .. sep .. part:gsub("^[/\\]", "")
    end
  end
  return result
end

-- ---------------------------------------------------------------------------
-- mkdir – creates a directory and any missing parents
-- ---------------------------------------------------------------------------
function M.mkdir(path)
  if is_windows then
    os.execute('mkdir "' .. path .. '" 2>NUL')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

-- ---------------------------------------------------------------------------
-- exists – returns true if a path exists
-- ---------------------------------------------------------------------------
function M.exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

return M
