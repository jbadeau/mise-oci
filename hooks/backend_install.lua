function PLUGIN:BackendInstall(ctx)
  -- ctx.tool: OCI reference like "docker.io/jbadeau/azul-zulu"
  -- ctx.version: version/tag like "17.60.17"
  -- ctx.install_path: where to install the tool
  
  local oci_ref = ctx.tool .. ":" .. ctx.version
  local install_path = ctx.install_path
  
  -- Create install directory
  os.execute("mkdir -p " .. install_path)
  
  -- Create temp directory for extraction
  local temp_dir = os.tmpname() .. "_oci_extract"
  os.execute("mkdir -p " .. temp_dir)
  
  -- Detect current platform using mise's RUNTIME API
  local os_name = "linux"
  local arch = "x64"
  
  -- Get OS using mise's RUNTIME API
  if RUNTIME.osType == "darwin" then
    os_name = "macosx"
  elseif RUNTIME.osType == "windows" then
    os_name = "win"
  elseif RUNTIME.osType == "linux" then
    os_name = "linux"
  end
  
  -- Get architecture using mise's RUNTIME API
  if RUNTIME.archType == "arm64" or RUNTIME.archType == "aarch64" then
    arch = "aarch64"
  elseif RUNTIME.archType == "amd64" or RUNTIME.archType == "x86_64" then
    arch = "x64"
  end
  
  local platform_key = os_name .. "_" .. arch
  
  -- First, get the manifest to find the correct layer for our platform
  local manifest_cmd = string.format("oras manifest fetch %s", oci_ref)
  local manifest_handle = io.popen(manifest_cmd)
  if not manifest_handle then
    os.execute("rm -rf " .. temp_dir)
    error("Failed to fetch manifest for: " .. oci_ref)
  end
  
  local manifest_json = manifest_handle:read("*all")
  manifest_handle:close()
  
  if not manifest_json or manifest_json == "" then
    os.execute("rm -rf " .. temp_dir)
    error("Empty manifest for: " .. oci_ref)
  end
  
  -- Parse manifest to find platform-specific layer
  local manifest_file = temp_dir .. "/manifest.json"
  local mf = io.open(manifest_file, "w")
  mf:write(manifest_json)
  mf:close()
  
  -- Use jq to find the layer digest for our platform
  local platform_key = os_name .. "_" .. arch
  local jq_cmd = string.format("jq -r '.layers[] | select(.annotations.\"org.opencontainers.image.title\" | test(\"%s\")) | .digest' %s", platform_key, manifest_file)
  local jq_handle = io.popen(jq_cmd)
  local layer_digest = nil
  if jq_handle then
    layer_digest = jq_handle:read("*l")
    jq_handle:close()
  end
  
  if not layer_digest or layer_digest == "null" or layer_digest == "" then
    -- Fallback: try pattern matching on filename
    local fallback_jq = string.format("jq -r '.layers[] | select(.annotations.\"org.opencontainers.image.title\" | contains(\"%s\")) | .digest' %s", platform_key, manifest_file)
    local fallback_handle = io.popen(fallback_jq)
    if fallback_handle then
      layer_digest = fallback_handle:read("*l")
      fallback_handle:close()
    end
  end
  
  if not layer_digest or layer_digest == "null" or layer_digest == "" then
    os.execute("rm -rf " .. temp_dir)
    error("No layer found for platform: " .. platform_key .. " in MTA artifact")
  end
  
  -- Pull only the specific layer and config we need
  local repo_digest = oci_ref:match("^(.+):")
  local pull_cmd = string.format("cd %s && oras blob fetch %s@%s --output blob.tar.gz 2>/dev/null", temp_dir, repo_digest, layer_digest)
  local pull_result = os.execute(pull_cmd)
  
  if pull_result ~= 0 then
    os.execute("rm -rf " .. temp_dir)
    error("Failed to pull platform-specific layer: " .. layer_digest)
  end
  
  -- Get the config for metadata
  local config_digest_cmd = string.format("jq -r '.config.digest' %s", manifest_file)
  local config_handle = io.popen(config_digest_cmd)
  local config_digest = config_handle:read("*l")
  config_handle:close()
  
  local mta_config = nil
  if config_digest and config_digest ~= "null" then
    local config_cmd = string.format("oras blob fetch %s %s 2>/dev/null", oci_ref, config_digest)
    local cfg_handle = io.popen(config_cmd)
    if cfg_handle then
      mta_config = cfg_handle:read("*all")
      cfg_handle:close()
    end
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
  
  if magic_bytes and magic_bytes:sub(1,2) == "PK" then
    -- ZIP file
    extract_cmd = string.format("cd %s && unzip -q %s && find . -maxdepth 1 -type d ! -name '.' -exec mv {} temp_extracted \\; && mv temp_extracted/* . && rmdir temp_extracted", install_path, platform_file)
  elseif magic_bytes and magic_bytes:sub(1,2) == "\x1f\x8b" then
    -- GZIP file (tar.gz)
    extract_cmd = string.format("cd %s && tar -xzf %s --strip-components=1", install_path, platform_file)
  elseif magic_bytes and magic_bytes:sub(1,6) == "\xfd7zXZ\x00" then
    -- XZ file (tar.xz)
    extract_cmd = string.format("cd %s && tar -xJf %s --strip-components=1", install_path, platform_file)
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
  
  -- Execute post-install commands from MTA config
  if mta_config then
    -- Simple post-install: make binaries executable
    local chmod_cmd = string.format("chmod +x %s/bin/* 2>/dev/null || true", install_path)
    os.execute(chmod_cmd)
  end
  
  return {}
end
