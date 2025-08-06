function PLUGIN:BackendListVersions(ctx)
  -- ctx.tool contains the OCI reference like "docker.io/jbadeau/azul-zulu"
  local registry_url = ctx.tool
  
  -- Use oras to list tags from the OCI registry
  local cmd = "oras repo tags " .. registry_url .. " 2>/dev/null"
  local handle = io.popen(cmd)
  if not handle then
    return { versions = {} }
  end
  
  local versions = {}
  for line in handle:lines() do
    -- Skip empty lines and add versions
    if line and line:match("%S") then
      table.insert(versions, line:match("^%s*(.-)%s*$")) -- trim whitespace
    end
  end
  handle:close()
  
  return { versions = versions }
end
