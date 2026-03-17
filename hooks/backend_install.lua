local cmd = require("cmd")
local json = require("json")
local file = require("file")

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

-- Normalize RUNTIME.osType to OCI platform os (lowercase)
local function detect_os()
  local os_type = RUNTIME.osType or "linux"
  return os_type:lower()
end

-- Detect architecture
local function detect_arch()
  return RUNTIME.archType or "amd64"
end

function PLUGIN:BackendInstall(ctx)
  local tool = expand_oci_ref(ctx.tool)
  local oci_ref = tool .. ":" .. ctx.version
  local install_path = ctx.install_path
  local download_path = ctx.download_path
  local flags = oras_flags()

  os.execute("mkdir -p " .. install_path)
  os.execute("mkdir -p " .. download_path)

  local os_name = detect_os()
  local arch = detect_arch()

  -- Step 1: Fetch the OCI Image Index
  local index_raw = cmd.exec("oras manifest fetch " .. flags .. oci_ref)
  local index = json.decode(index_raw)

  -- Step 2: Find matching platform manifest from the Image Index
  local manifest_digest = nil
  for _, m in ipairs(index.manifests or {}) do
    local p = m.platform or {}
    if p.os == os_name and p.architecture == arch then
      manifest_digest = m.digest
      break
    end
  end

  if not manifest_digest then
    error("No platform manifest found for " .. os_name .. "/" .. arch .. " in: " .. oci_ref)
  end

  -- Step 3: Fetch the platform-specific manifest
  local manifest_raw = cmd.exec("oras manifest fetch " .. flags .. tool .. "@" .. manifest_digest)
  local manifest = json.decode(manifest_raw)

  -- Step 4: Get config and layer digests
  local config_digest = manifest.config and manifest.config.digest
  local layer_digest = manifest.layers and manifest.layers[1] and manifest.layers[1].digest

  if not layer_digest then
    error("No payload layer found in platform manifest for " .. os_name .. "/" .. arch)
  end

  -- Step 5: Fetch the config blob
  local mta_config = nil
  if config_digest then
    local config_file = file.join_path(download_path, "mta_config.json")
    cmd.exec("oras blob fetch " .. flags .. tool .. "@" .. config_digest .. " --output " .. config_file)
    local f = io.open(config_file, "r")
    if f then
      mta_config = f:read("*all")
      f:close()
    end
  end

  -- Step 6: Fetch the payload layer
  local layer_media_type = manifest.layers[1].mediaType or ""
  local layer_file = file.join_path(download_path, "payload")
  cmd.exec("oras blob fetch " .. flags .. tool .. "@" .. layer_digest .. " --output " .. layer_file)

  -- Parse config for stripComponents
  local strip = 0
  local config_obj = nil
  if mta_config then
    local ok, cfg = pcall(json.decode, mta_config)
    if ok and cfg then
      config_obj = cfg
      strip = cfg.stripComponents or 0
    end
  end

  -- Step 7: Extract based on media type, with magic byte fallback
  local fh = io.open(layer_file, "rb")
  if not fh then
    error("Payload layer not found after download")
  end
  local magic = fh:read(4)
  fh:close()

  local b1, b2, b3, b4 = magic:byte(1, 4)
  local is_zip = (b1 == 0x50 and b2 == 0x4b)
  local is_gzip = (b1 == 0x1f and b2 == 0x8b)
  local is_xz = (b1 == 0xfd and b2 == 0x37 and b3 == 0x7a and b4 == 0x58)
  local is_elf = (b1 == 0x7f and b2 == 0x45 and b3 == 0x4c and b4 == 0x46)
  local is_macho = (b1 == 0xcf and b2 == 0xfa and b3 == 0xed and b4 == 0xfe) or
                   (b1 == 0xfe and b2 == 0xed and b3 == 0xfa and b4 == 0xcf) or
                   (b1 == 0xca and b2 == 0xfe and b3 == 0xba and b4 == 0xbe)
  local is_binary = is_elf or is_macho

  local strip_flag = ""
  if strip > 0 then
    strip_flag = " --strip-components=" .. strip
  end

  if layer_media_type == "application/zip" or is_zip then
    if strip > 0 then
      -- Zip has no --strip-components; extract to temp then move contents
      local zip_tmp = file.join_path(download_path, "zip_extract")
      cmd.exec("unzip -q " .. layer_file .. " -d " .. zip_tmp)
      cmd.exec("sh -c 'mv " .. zip_tmp .. "/*/* " .. install_path .. "/'")
    else
      cmd.exec("unzip -q " .. layer_file .. " -d " .. install_path)
    end
  elseif layer_media_type == "application/octet-stream" or is_binary then
    -- Standalone binary: place at first bin entry from config
    local bin_path = "bin/" .. ctx.tool:match("([^/]+)$")
    if config_obj and config_obj.bin and config_obj.bin[1] then
      bin_path = config_obj.bin[1]
    end
    local bin_dir = file.join_path(install_path, bin_path:match("(.*/)" ) or "bin/")
    os.execute("mkdir -p " .. bin_dir)
    local dest = file.join_path(install_path, bin_path)
    cmd.exec("cp " .. layer_file .. " " .. dest)
    cmd.exec("chmod +x " .. dest)
  elseif is_xz then
    cmd.exec("tar -xJf " .. layer_file .. strip_flag .. " -C " .. install_path)
  else
    -- Default: tar+gzip
    cmd.exec("tar -xzf " .. layer_file .. strip_flag .. " -C " .. install_path)
  end

  -- Make binaries executable
  os.execute("chmod +x " .. install_path .. "/bin/* 2>/dev/null || true")

  -- Save MTA config for use by backend_exec_env.lua
  if mta_config and mta_config ~= "" then
    local config_path = file.join_path(install_path, ".mta-config.json")
    local config_out = io.open(config_path, "w")
    if config_out then
      config_out:write(mta_config)
      config_out:close()
    end
  end

  return {}
end
