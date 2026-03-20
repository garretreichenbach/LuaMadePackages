-- lib/http.lua
-- HTTP utilities for lpm.
-- Wraps LuaSocket/LuaSec to provide GET, DELETE, and multipart POST.

local M = {}

-- Attempt to load LuaSocket.  Provide clear error if missing.
local socket_http = require("socket.http") or error(
  "LuaSocket is required: luarocks install luasocket"
)
local ltn12 = require("ltn12") or error(
  "ltn12 is required (bundled with LuaSocket)"
)

-- Try to load LuaSec for HTTPS; fall back to http (dev only).
local https_ok, https = pcall(require, "ssl.https")
if not https_ok then
  https = socket_http
  io.stderr:write("[lpm] WARNING: LuaSec not found; falling back to plain HTTP.\n")
  io.stderr:write("               Install LuaSec: luarocks install luasec\n")
end

-- ---------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------

local function choose_client(url)
  if url:sub(1, 8) == "https://" then return https end
  return socket_http
end

-- ---------------------------------------------------------------------------
-- url_encode
-- ---------------------------------------------------------------------------

function M.url_encode(str)
  if not str then return "" end
  return str:gsub("[^A-Za-z0-9%-_.~]", function(c)
    return string.format("%%%02X", c:byte())
  end)
end

-- ---------------------------------------------------------------------------
-- GET
-- ---------------------------------------------------------------------------

function M.get(url)
  local response_body = {}
  local client = choose_client(url)
  local _, status, headers = client.request({
    url     = url,
    method  = "GET",
    sink    = ltn12.sink.table(response_body),
  })
  return {
    status  = status or 0,
    headers = headers or {},
    body    = table.concat(response_body),
  }
end

-- ---------------------------------------------------------------------------
-- DELETE (with Bearer auth)
-- ---------------------------------------------------------------------------

function M.delete(url, api_key)
  local response_body = {}
  local client = choose_client(url)
  local _, status, headers = client.request({
    url     = url,
    method  = "DELETE",
    headers = {
      ["Authorization"] = "Bearer " .. (api_key or ""),
    },
    sink    = ltn12.sink.table(response_body),
  })
  return {
    status  = status or 0,
    headers = headers or {},
    body    = table.concat(response_body),
  }
end

-- ---------------------------------------------------------------------------
-- download – streams a GET response directly to a file
-- ---------------------------------------------------------------------------

function M.download(url, dest_path)
  local f, err = io.open(dest_path, "wb")
  if not f then return false, err end

  local client = choose_client(url)
  local ok, status = client.request({
    url        = url,
    method     = "GET",
    sink       = ltn12.sink.file(f),
    redirect   = true,
  })

  -- LuaSocket closes the file after sinking, so no explicit f:close() is needed.
  if not ok then return false, tostring(status) end
  return true
end

-- ---------------------------------------------------------------------------
-- multipart_post – POST multipart/form-data with manifest + package file
-- ---------------------------------------------------------------------------

function M.multipart_post(url, api_key, manifest_text, package_path)
  local boundary = "----LuaMadePackagesBoundary" .. tostring(math.random(1e9))
  local CRLF = "\r\n"

  -- Build body parts.
  local parts = {}

  -- manifest field
  table.insert(parts,
    "--" .. boundary .. CRLF ..
    'Content-Disposition: form-data; name="manifest"' .. CRLF ..
    "Content-Type: application/json" .. CRLF .. CRLF ..
    manifest_text .. CRLF
  )

  -- package file
  local pf, err = io.open(package_path, "rb")
  if not pf then return false, "Cannot open package file: " .. tostring(err) end
  local pkg_data = pf:read("*a")
  pf:close()

  local filename = package_path:match("[^/\\]+$") or "package.tar.gz"
  table.insert(parts,
    "--" .. boundary .. CRLF ..
    'Content-Disposition: form-data; name="package"; filename="' .. filename .. '"' .. CRLF ..
    "Content-Type: application/gzip" .. CRLF .. CRLF ..
    pkg_data .. CRLF
  )

  table.insert(parts, "--" .. boundary .. "--" .. CRLF)

  local body = table.concat(parts)
  local response_body = {}
  local client = choose_client(url)

  local _, status, headers = client.request({
    url     = url,
    method  = "POST",
    headers = {
      ["Authorization"]  = "Bearer " .. (api_key or ""),
      ["Content-Type"]   = "multipart/form-data; boundary=" .. boundary,
      ["Content-Length"] = tostring(#body),
    },
    source  = ltn12.source.string(body),
    sink    = ltn12.sink.table(response_body),
  })

  if not status then
    return false, tostring(headers)
  end

  return true, {
    status  = status,
    headers = headers or {},
    body    = table.concat(response_body),
  }
end

return M
