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
  
  -- Detect current platform
  local os_name = "linux"
  local arch = "amd64"
  
  -- Get OS
  local uname_s = io.popen("uname -s"):read("*l")
  if uname_s == "Darwin" then
    os_name = "darwin"
  elseif uname_s:match("MINGW") or uname_s:match("Windows") then
    os_name = "windows"
  end
  
  -- Get architecture
  local uname_m = io.popen("uname -m"):read("*l")
  if uname_m == "arm64" or uname_m == "aarch64" then
    arch = "arm64"
  elseif uname_m == "x86_64" or uname_m == "amd64" then
    arch = "amd64"
  end
  
  -- Pull OCI artifact to temp directory
  local pull_cmd = string.format("cd %s && oras pull %s 2>/dev/null", temp_dir, oci_ref)
  local pull_result = os.execute(pull_cmd)
  
  if pull_result ~= 0 then
    os.execute("rm -rf " .. temp_dir)
    error("Failed to pull OCI artifact: " .. oci_ref)
  end
  
  -- Find platform-specific file
  local platform_pattern = os_name .. ".*" .. arch
  local find_cmd = string.format("find %s -type f | grep -E '%s'", temp_dir, platform_pattern)
  local handle = io.popen(find_cmd)
  local platform_file = handle:read("*l")
  handle:close()
  
  if not platform_file then
    -- Fallback: try to find any archive file
    local fallback_cmd = string.format("find %s -type f -name '*.tar.gz' -o -name '*.zip' -o -name '*.tar.xz' | head -1", temp_dir)
    handle = io.popen(fallback_cmd)
    platform_file = handle:read("*l")
    handle:close()
  end
  
  if not platform_file then
    os.execute("rm -rf " .. temp_dir)
    error("No suitable platform file found in OCI artifact")
  end
  
  -- Extract the archive
  local extract_cmd
  if platform_file:match("%.tar%.gz$") then
    extract_cmd = string.format("cd %s && tar -xzf %s --strip-components=1", install_path, platform_file)
  elseif platform_file:match("%.tar%.xz$") then
    extract_cmd = string.format("cd %s && tar -xJf %s --strip-components=1", install_path, platform_file)
  elseif platform_file:match("%.zip$") then
    extract_cmd = string.format("cd %s && unzip -q %s && find . -maxdepth 1 -type d ! -name '.' -exec mv {} temp_extracted \\; && mv temp_extracted/* . && rmdir temp_extracted", install_path, platform_file)
  else
    os.execute("rm -rf " .. temp_dir)
    error("Unsupported archive format: " .. platform_file)
  end
  
  local extract_result = os.execute(extract_cmd)
  
  -- Clean up temp directory
  os.execute("rm -rf " .. temp_dir)
  
  if extract_result ~= 0 then
    error("Failed to extract archive: " .. platform_file)
  end
  
  return {}
end
