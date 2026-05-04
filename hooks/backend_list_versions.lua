local cmd = require("cmd")

-- Resolve full path to oras via mise
local function oras_bin()
  local ok, path = pcall(cmd.exec, "mise which oras")
  if ok and path then
    path = path:match("^%s*(.-)%s*$")
    if path ~= "" then
      return path
    end
  end
  error("mise-oci requires 'oras'. Install it with mise.")
end

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
  if tool:find("/") then
    return tool
  end
  local registry = os.getenv("MISE_OCI_REGISTRY")
  local repository = os.getenv("MISE_OCI_REPOSITORY")
  return registry .. "/" .. repository .. "/" .. tool
end

-- Build oras flags string
local function oras_flags()
  if os.getenv("MISE_OCI_INSECURE") == "true" then
    return "--insecure "
  end
  return ""
end

-- Check if a tag is a platform-specific tag (e.g., "17.60.17-linux-amd64")
local function is_platform_tag(tag)
  local platform_suffixes = {
    "%-linux%-amd64$", "%-linux%-arm64$", "%-linux%-arm$", "%-linux%-386$",
    "%-darwin%-amd64$", "%-darwin%-arm64$",
    "%-windows%-amd64$", "%-windows%-arm64$", "%-windows%-386$"
  }
  for _, pattern in ipairs(platform_suffixes) do
    if tag:match(pattern) then
      return true
    end
  end
  return false
end

function PLUGIN:BackendListVersions(ctx)
  local registry_url = expand_oci_ref(ctx.tool)
  local flags = oras_flags()

  local ok, output = pcall(cmd.exec, oras_bin() .. " repo tags " .. flags .. registry_url)
  if not ok then
    io.stderr:write("mise-oci: Failed to list tags for " .. registry_url .. ": " .. tostring(output) .. "\n")
    return { versions = {} }
  end

  local versions = {}
  for line in output:gmatch("[^\r\n]+") do
    local tag = line:match("^%s*(.-)%s*$")
    if tag and tag ~= "" and not is_platform_tag(tag) then
      table.insert(versions, tag)
    end
  end

  -- Sort versions in reverse order (newest first)
  table.sort(versions, function(a, b) return a > b end)

  return { versions = versions }
end
