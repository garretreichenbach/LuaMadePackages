-- lpm – LuaMade Package Manager CLI
-- A minimal command-line tool for interacting with the LuaMadePackages registry.
--
-- Requirements:
--   Lua 5.3+ (or LuaJIT)
--   LuaSocket  (luarocks install luasocket)
--   LuaSec     (luarocks install luasec)  – for HTTPS
--   ltn12      (bundled with LuaSocket)
--   dkjson     (luarocks install dkjson)  – JSON encode/decode
--
-- Usage:
--   lua lpm.lua <command> [arguments]
--
-- Commands:
--   search  <query>                Search for packages
--   info    <name>                 Show package metadata
--   install <name> [version]       Download and install a package
--   publish <manifest.json> <pkg.tar.gz>  Publish a package (requires API_KEY env var)
--   delete  <name> <version>       Delete a package version (requires API_KEY env var)
--   help                           Show this help message

local config = require("lib.config")
local http   = require("lib.http")
local json   = require("lib.json")
local fs     = require("lib.fs")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function printf(fmt, ...)
  io.write(string.format(fmt, ...))
end

local function die(msg)
  io.stderr:write("[lpm] Error: " .. tostring(msg) .. "\n")
  os.exit(1)
end

local function assert_ok(response, context)
  if response.status >= 400 then
    local body = response.body or ""
    local ok, parsed = pcall(json.decode, body)
    local msg = (ok and parsed and parsed.error) or body
    die(string.format("%s: HTTP %d – %s", context, response.status, msg))
  end
end

-- ---------------------------------------------------------------------------
-- Command implementations
-- ---------------------------------------------------------------------------

local function cmd_search(args)
  local query = args[1] or ""
  printf("Searching for \"%s\"…\n", query)
  local url = config.api_base_url .. "/packages?search=" .. http.url_encode(query)
  local response = http.get(url)
  assert_ok(response, "search")
  local data = json.decode(response.body)
  if not data.packages or #data.packages == 0 then
    printf("No packages found.\n")
    return
  end
  printf("Found %d package(s):\n\n", data.total or #data.packages)
  printf("  %-30s %-12s %s\n", "Name", "Latest", "Description")
  printf("  %s\n", string.rep("-", 72))
  for _, pkg in ipairs(data.packages) do
    printf("  %-30s %-12s %s\n",
      pkg.name or "",
      pkg.latestVersion or "?",
      (pkg.description or ""):sub(1, 40))
  end
  printf("\n")
end

local function cmd_info(args)
  local name = args[1] or die("Usage: lpm info <package-name>")
  local url = config.api_base_url .. "/packages/" .. http.url_encode(name)
  local response = http.get(url)
  assert_ok(response, "info")
  local pkg = json.decode(response.body)
  printf("\nPackage: %s\n", pkg.name)
  printf("Latest:  %s\n", pkg.latestVersion or "none")
  printf("Author:  %s\n", pkg.author or "unknown")
  printf("License: %s\n", pkg.license or "unknown")
  printf("Desc:    %s\n", pkg.description or "")
  if pkg.tags and #pkg.tags > 0 then
    printf("Tags:    %s\n", table.concat(pkg.tags, ", "))
  end
  printf("\nVersions:\n")
  if pkg.versions then
    local versions = {}
    for v in pairs(pkg.versions) do
      table.insert(versions, v)
    end
    table.sort(versions)
    for _, v in ipairs(versions) do
      local info = pkg.versions[v]
      printf("  %s  (published %s, %d bytes)\n",
        v,
        (info.publishedAt or ""):sub(1, 10),
        info.size or 0)
    end
  end
  printf("\n")
end

local function cmd_install(args)
  local name    = args[1] or die("Usage: lpm install <package-name> [version]")
  local version = args[2]

  -- Resolve version if not specified.
  if not version then
    local url = config.api_base_url .. "/packages/" .. http.url_encode(name)
    local response = http.get(url)
    assert_ok(response, "install (resolve version)")
    local pkg = json.decode(response.body)
    version = pkg.latestVersion or die(string.format("Package \"%s\" has no published versions.", name))
  end

  printf("Installing %s@%s…\n", name, version)

  local url = string.format("%s/packages/%s/%s/download",
    config.api_base_url, http.url_encode(name), http.url_encode(version))
  local dest_dir = fs.join(config.install_dir, name)
  local dest_file = fs.join(dest_dir, version .. ".tar.gz")

  fs.mkdir(dest_dir)
  local ok, err = http.download(url, dest_file)
  if not ok then
    die(string.format("Failed to download %s@%s: %s", name, version, err))
  end

  printf("Downloaded to %s\n", dest_file)
  printf("Extracting…\n")

  -- Extract the tarball.  Requires `tar` to be available on PATH.
  local extract_dir = fs.join(dest_dir, version)
  fs.mkdir(extract_dir)
  local cmd = string.format("tar -xzf %q -C %q", dest_file, extract_dir)
  local exit_code = os.execute(cmd)
  if exit_code ~= 0 then
    die("Extraction failed.  Is `tar` installed?")
  end

  -- Remove the downloaded archive.
  os.remove(dest_file)
  printf("Installed %s@%s → %s\n\n", name, version, extract_dir)
end

local function cmd_publish(args)
  local manifest_path = args[1] or die("Usage: lpm publish <manifest.json> <package.tar.gz>")
  local package_path  = args[2] or die("Usage: lpm publish <manifest.json> <package.tar.gz>")

  local api_key = os.getenv("LPM_API_KEY") or die(
    "LPM_API_KEY environment variable is not set.  Obtain a key from the registry administrator."
  )

  -- Read manifest.
  local f, err = io.open(manifest_path, "r")
  if not f then die("Cannot open manifest: " .. tostring(err)) end
  local manifest_text = f:read("*a")
  f:close()

  -- Validate manifest client-side (basic checks).
  local manifest = json.decode(manifest_text)
  if not manifest.name    then die("manifest.json missing \"name\".") end
  if not manifest.version then die("manifest.json missing \"version\".") end

  printf("Publishing %s@%s…\n", manifest.name, manifest.version)

  local url = config.api_base_url .. "/packages"
  local ok, result = http.multipart_post(url, api_key, manifest_text, package_path)
  if not ok then
    die("Publish failed: " .. tostring(result))
  end
  if result.status ~= 201 then
    local body = result.body or ""
    local pok, parsed = pcall(json.decode, body)
    die(string.format("HTTP %d – %s", result.status, (pok and parsed and parsed.error) or body))
  end

  printf("Published successfully!\n\n")
end

local function cmd_delete(args)
  local name    = args[1] or die("Usage: lpm delete <name> <version>")
  local version = args[2] or die("Usage: lpm delete <name> <version>")

  local api_key = os.getenv("LPM_API_KEY") or die(
    "LPM_API_KEY environment variable is not set."
  )

  printf("Deleting %s@%s…\n", name, version)

  local url = string.format("%s/packages/%s/%s",
    config.api_base_url, http.url_encode(name), http.url_encode(version))
  local response = http.delete(url, api_key)
  assert_ok(response, "delete")

  printf("Deleted %s@%s.\n\n", name, version)
end

local function cmd_help()
  printf([[
lpm – LuaMade Package Manager

Usage: lua lpm.lua <command> [arguments]

Commands:
  search  [query]                   Search the package registry
  info    <name>                    Show package details and versions
  install <name> [version]          Install a package (latest if version omitted)
  publish <manifest.json> <pkg.tar.gz>  Publish a package (requires LPM_API_KEY)
  delete  <name> <version>          Delete a package version (requires LPM_API_KEY)
  help                              Show this help message

Environment Variables:
  LPM_API_KEY       Bearer API key for authenticated operations (publish, delete)
  LPM_REGISTRY_URL  Override the default registry URL

Examples:
  lua lpm.lua search json
  lua lpm.lua info   my-library
  lua lpm.lua install my-library 1.2.0
  LPM_API_KEY=<key> lua lpm.lua publish manifest.json my-library-1.2.0.tar.gz

]])
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

local commands = {
  search  = cmd_search,
  info    = cmd_info,
  install = cmd_install,
  publish = cmd_publish,
  delete  = cmd_delete,
  help    = cmd_help,
}

local cmd_name = arg[1]
if not cmd_name or cmd_name == "" or cmd_name == "help" or cmd_name == "--help" or cmd_name == "-h" then
  cmd_help()
  os.exit(0)
end

local handler = commands[cmd_name]
if not handler then
  io.stderr:write(string.format("[lpm] Unknown command: %q\n\nRun 'lua lpm.lua help' for usage.\n", cmd_name))
  os.exit(1)
end

-- Shift arguments (drop the command name).
local sub_args = {}
for i = 2, #arg do
  table.insert(sub_args, arg[i])
end

handler(sub_args)
