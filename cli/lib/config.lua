-- lib/config.lua
-- Runtime configuration for lpm.
-- Values can be overridden via environment variables.

local M = {}

-- Base URL of the LuaMadePackages API.
M.api_base_url = os.getenv("LPM_REGISTRY_URL") or "https://luamadepkgs-prod-func.azurewebsites.net/api"

-- Directory where packages are installed.
-- Defaults to a "packages" folder next to the lpm.lua script.
M.install_dir = os.getenv("LPM_INSTALL_DIR") or (
  (arg and arg[0] and arg[0]:match("^(.*[/\\])") or "./") .. "packages"
)

return M
