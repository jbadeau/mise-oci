-- Check required environment variables
local function check_required_env()
  local required = {
    "MISE_OCI_REGISTRY",
    "MISE_OCI_REPOSITORY"
  }
  local missing = {}
  for _, var in ipairs(required) do
    if not os.getenv(var) or os.getenv(var) == "" then
      table.insert(missing, var)
    end
  end
  if #missing > 0 then
    error("Missing required environment variables: " .. table.concat(missing, ", "))
  end
end

-- Expand short tool name to full OCI reference using env vars
local function expand_oci_ref(tool)
  check_required_env()

  -- If already contains registry/namespace (has /), use as-is
  if tool:find("/") then
    return tool
  end

  local registry = os.getenv("MISE_OCI_REGISTRY")
  local repository = os.getenv("MISE_OCI_REPOSITORY")

  return registry .. "/" .. repository .. "/" .. tool
end

-- Get registry config path, creating empty config for anonymous access if needed
-- This avoids Docker Desktop credential store contention with parallel jobs
local function get_registry_config()
  local config_path = os.getenv("MISE_OCI_REGISTRY_CONFIG")
  if config_path then
    return config_path
  end

  -- Create empty config for anonymous access to public registries
  local mise_data = os.getenv("MISE_DATA_DIR") or (os.getenv("HOME") .. "/.local/share/mise")
  local oci_config_dir = mise_data .. "/oci"
  local empty_config = oci_config_dir .. "/registry-config.json"

  -- Create config dir and empty config if not exists
  os.execute("mkdir -p " .. oci_config_dir)
  local f = io.open(empty_config, "r")
  if not f then
    f = io.open(empty_config, "w")
    if f then
      f:write("{}")
      f:close()
    end
  else
    f:close()
  end

  return empty_config
end

function PLUGIN:BackendListVersions(ctx)
  -- ctx.tool contains the OCI reference like "docker.io/jbadeau/azul-zulu" or short name like "pnpm"
  local registry_url = expand_oci_ref(ctx.tool)
  local registry_config = get_registry_config()

  -- Create unique temp file for output
  local temp_file = string.format("/tmp/oci_tags_%d_%d.txt", os.time(), math.random(100000, 999999))

  -- Use oras to list tags from the OCI registry for MTA artifacts
  local cmd = string.format("oras repo tags --registry-config %s %s > %s 2>&1",
    registry_config, registry_url, temp_file)
  local result = os.execute(cmd)

  -- Check if oras command succeeded
  if result ~= 0 then
    -- Read error output for debugging
    local err_file = io.open(temp_file, "r")
    local err_msg = err_file and err_file:read("*all") or "oras command failed"
    if err_file then err_file:close() end
    os.remove(temp_file)
    -- Log error but return empty versions (mise will show "No versions found" warning)
    io.stderr:write("mise-oci: Failed to list tags for " .. registry_url .. ": " .. (err_msg or "unknown error") .. "\n")
    return { versions = {} }
  end

  local versions = {}
  local f = io.open(temp_file, "r")
  if f then
    for line in f:lines() do
      -- Skip empty lines and add versions
      if line and line:match("%S") then
        local version = line:match("^%s*(.-)%s*$") -- trim whitespace
        table.insert(versions, version)
      end
    end
    f:close()
  end

  -- Clean up temp file
  os.remove(temp_file)

  -- Sort versions in reverse order (newest first)
  table.sort(versions, function(a, b) return a > b end)

  return { versions = versions }
end
