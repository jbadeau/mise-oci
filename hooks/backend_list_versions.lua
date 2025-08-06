function PLUGIN:BackendListVersions(ctx)
  -- ctx.tool contains the OCI reference like "docker.io/jbadeau/azul-zulu"
  local registry_url = ctx.tool
  
  -- Use oras to list tags from the OCI registry for MTA artifacts
  local cmd = "oras repo tags " .. registry_url .. " 2>/dev/null"
  local handle = io.popen(cmd)
  if not handle then
    return { versions = {} }
  end
  
  local versions = {}
  for line in handle:lines() do
    -- Skip empty lines and add versions
    if line and line:match("%S") then
      local version = line:match("^%s*(.-)%s*$") -- trim whitespace
      
      -- Optionally validate that this is an MTA artifact by checking manifest
      -- For now, include all tags as potential versions
      table.insert(versions, version)
    end
  end
  handle:close()
  
  -- Sort versions in reverse order (newest first)
  table.sort(versions, function(a, b) return a > b end)
  
  return { versions = versions }
end
