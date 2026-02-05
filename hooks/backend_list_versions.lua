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

-- Login to registry if credentials are provided
local function ensure_registry_login()
  local registry = os.getenv("MISE_OCI_REGISTRY")
  local username = os.getenv("MISE_OCI_USERNAME")
  local password = os.getenv("MISE_OCI_PASSWORD")

  if username and password and username ~= "" and password ~= "" and registry then
    local login_cmd = string.format("echo '%s' | oras login %s -u '%s' --password-stdin >/dev/null 2>&1",
      password, registry, username)
    os.execute(login_cmd)
  end
end

function PLUGIN:BackendListVersions(ctx)
  -- ctx.tool contains the OCI reference like "docker.io/jbadeau/azul-zulu" or short name like "pnpm"
  ensure_registry_login()

  local registry_url = expand_oci_ref(ctx.tool)

  -- Create unique temp file for output
  local temp_file = string.format("/tmp/oci_tags_%d_%d.txt", os.time(), math.random(100000, 999999))

  -- Use oras to list tags from the OCI registry for MTA artifacts
  local cmd = string.format("oras repo tags %s > %s 2>&1",
    registry_url, temp_file)
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
