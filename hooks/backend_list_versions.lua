-- Expand short tool name to full OCI reference using env vars
local function expand_oci_ref(tool)
  -- If already contains registry/namespace (has /), use as-is
  if tool:find("/") then
    return tool
  end

  -- Get defaults from env vars (with sensible defaults)
  local registry = os.getenv("MISE_OCI_REGISTRY") or "docker.io"
  local namespace = os.getenv("MISE_OCI_NAMESPACE") or "jbadeau"

  return registry .. "/" .. namespace .. "/" .. tool
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
  local cmd = string.format("oras repo tags --registry-config %s %s > %s 2>/dev/null",
    registry_config, registry_url, temp_file)
  os.execute(cmd)

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
