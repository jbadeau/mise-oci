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

-- Read file contents (replacement for io.popen to avoid parallel execution issues)
local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*all")
  f:close()
  return content
end

-- Read first line of file
local function read_file_line(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local line = f:read("*l")
  f:close()
  return line
end

function PLUGIN:BackendInstall(ctx)
  -- ctx.tool: OCI reference like "docker.io/jbadeau/azul-zulu" or short name like "pnpm"
  -- ctx.version: version/tag like "17.60.17"
  -- ctx.install_path: where to install the tool

  local tool = expand_oci_ref(ctx.tool)
  local oci_ref = tool .. ":" .. ctx.version
  local install_path = ctx.install_path

  -- Create install directory
  os.execute("mkdir -p " .. install_path)

  -- Create unique temp directory for extraction (use PID and random for uniqueness)
  local temp_dir = string.format("/tmp/oci_extract_%d_%d", os.time(), math.random(100000, 999999))
  os.execute("mkdir -p " .. temp_dir)

  -- Detect current platform using mise's RUNTIME API (use native mise names)
  local os_name = RUNTIME.osType or "linux"
  local arch = RUNTIME.archType or "amd64"

  local platform_key = os_name .. "_" .. arch

  -- First, get the manifest to find the correct layer for our platform
  local manifest_file = temp_dir .. "/manifest.json"
  local manifest_cmd = string.format("oras manifest fetch %s > %s 2>&1",
    oci_ref, manifest_file)
  local manifest_result = os.execute(manifest_cmd)

  if manifest_result ~= 0 then
    -- Read the error output before cleanup
    local error_msg = read_file(manifest_file) or "unknown error"
    os.execute("rm -rf " .. temp_dir)
    error("Failed to fetch manifest for: " .. oci_ref .. " - " .. error_msg)
  end

  local manifest_json = read_file(manifest_file)
  if not manifest_json or manifest_json == "" then
    os.execute("rm -rf " .. temp_dir)
    error("Empty manifest for: " .. oci_ref)
  end

  -- Use jq to find the layer digest for our platform (write to temp file)
  local digest_file = temp_dir .. "/digest.txt"
  local jq_cmd = string.format(
    "jq -r '.layers[] | select(.annotations.\"org.opencontainers.image.title\" | test(\"%s\")) | .digest' %s > %s 2>/dev/null",
    platform_key, manifest_file, digest_file)
  os.execute(jq_cmd)

  local layer_digest = read_file_line(digest_file)

  if not layer_digest or layer_digest == "null" or layer_digest == "" then
    -- Fallback: try pattern matching on filename
    local fallback_jq = string.format(
      "jq -r '.layers[] | select(.annotations.\"org.opencontainers.image.title\" | contains(\"%s\")) | .digest' %s > %s 2>/dev/null",
      platform_key, manifest_file, digest_file)
    os.execute(fallback_jq)
    layer_digest = read_file_line(digest_file)
  end

  if not layer_digest or layer_digest == "null" or layer_digest == "" then
    os.execute("rm -rf " .. temp_dir)
    error("No layer found for platform: " .. platform_key .. " in MTA artifact")
  end

  -- Pull only the specific layer and config we need
  local repo_digest = oci_ref:match("^(.+):")
  local pull_cmd = string.format("oras blob fetch %s@%s --output %s/blob.tar.gz",
    repo_digest, layer_digest, temp_dir)
  local pull_result = os.execute(pull_cmd)

  if pull_result ~= 0 then
    os.execute("rm -rf " .. temp_dir)
    error("Failed to pull platform-specific layer: " .. layer_digest)
  end

  -- Get the config for metadata
  local config_digest_file = temp_dir .. "/config_digest.txt"
  local config_digest_cmd = string.format("jq -r '.config.digest' %s > %s 2>/dev/null", manifest_file, config_digest_file)
  os.execute(config_digest_cmd)
  local config_digest = read_file_line(config_digest_file)

  local mta_config = nil
  if config_digest and config_digest ~= "null" and config_digest ~= "" then
    -- Extract repo without tag for blob fetch
    local repo = oci_ref:match("^(.+):")
    local config_file = temp_dir .. "/mta_config.json"
    local config_cmd = string.format("oras blob fetch %s@%s --output %s 2>/dev/null",
      repo, config_digest, config_file)
    os.execute(config_cmd)
    mta_config = read_file(config_file)
  end

  -- The blob we pulled is our platform file
  local platform_file = temp_dir .. "/blob.tar.gz"

  -- Check if file exists
  local file_check = io.open(platform_file, "r")
  if not file_check then
    os.execute("rm -rf " .. temp_dir)
    error("Platform-specific layer not found after download")
  end
  file_check:close()

  -- Determine extraction method from layer annotations or file signature
  local extract_cmd

  -- Check if it's a zip file by trying to read the magic bytes
  local file_handle = io.open(platform_file, "rb")
  local magic_bytes = file_handle:read(4)
  file_handle:close()

  -- Check magic bytes as hex for reliable comparison
  local b1, b2, b3, b4 = magic_bytes:byte(1, 4)
  local is_zip = (b1 == 0x50 and b2 == 0x4b)  -- PK
  local is_gzip = (b1 == 0x1f and b2 == 0x8b)
  local is_xz = (b1 == 0xfd and b2 == 0x37 and b3 == 0x7a and b4 == 0x58)  -- 0xfd 7zXZ
  local is_elf = (b1 == 0x7f and b2 == 0x45 and b3 == 0x4c and b4 == 0x46)  -- 0x7f ELF
  local is_macho = (b1 == 0xcf and b2 == 0xfa and b3 == 0xed and b4 == 0xfe) or  -- Mach-O 64-bit
                   (b1 == 0xfe and b2 == 0xed and b3 == 0xfa and b4 == 0xcf) or  -- Mach-O 64-bit (swapped)
                   (b1 == 0xca and b2 == 0xfe and b3 == 0xba and b4 == 0xbe)     -- Mach-O universal

  if is_zip then
    -- ZIP file
    extract_cmd = string.format("cd %s && unzip -q %s && find . -maxdepth 1 -type d ! -name '.' -exec mv {} temp_extracted \\; && mv temp_extracted/* . && rmdir temp_extracted", install_path, platform_file)
  elseif is_gzip then
    -- GZIP file (tar.gz)
    extract_cmd = string.format("cd %s && tar -xzf %s --strip-components=1", install_path, platform_file)
  elseif is_xz then
    -- XZ file (tar.xz)
    extract_cmd = string.format("cd %s && tar -xJf %s --strip-components=1", install_path, platform_file)
  elseif is_elf or is_macho then
    -- Standalone binary (ELF or Mach-O)
    local tool_name = oci_ref:match("/([^/:]+):")
    extract_cmd = string.format("mkdir -p %s/bin && cp %s %s/bin/%s && chmod +x %s/bin/%s", install_path, platform_file, install_path, tool_name, install_path, tool_name)
  else
    -- Default to tar.gz
    extract_cmd = string.format("cd %s && tar -xzf %s --strip-components=1", install_path, platform_file)
  end

  local extract_result = os.execute(extract_cmd)

  -- Clean up temp directory
  os.execute("rm -rf " .. temp_dir)

  if extract_result ~= 0 then
    error("Failed to extract archive: " .. platform_file)
  end

  -- Make binaries executable
  local chmod_cmd = string.format("chmod +x %s/bin/* 2>/dev/null || true", install_path)
  os.execute(chmod_cmd)

  -- Save MTA config for use by backend_exec_env.lua
  if mta_config and mta_config ~= "" then
    local config_path = install_path .. "/.mta-config.json"
    local config_file = io.open(config_path, "w")
    if config_file then
      config_file:write(mta_config)
      config_file:close()
    end
  end

  return {}
end
