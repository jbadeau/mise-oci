function PLUGIN:BackendExecEnv(ctx)
  -- ctx.install_path: path where the tool is installed
  local install_path = ctx.install_path
  local env_vars = {}
  
  -- Always add bin directory to PATH
  table.insert(env_vars, { key = "PATH", value = install_path .. "/bin" })
  
  -- Try to read MTA config for environment variables
  local config_file = install_path .. "/.mta-config.json"
  local config_handle = io.open(config_file, "r")
  if config_handle then
    -- If MTA config exists, use it for environment setup
    config_handle:close()
    -- For now, use simple template substitution
  end
  
  -- Default environment setup based on tool type
  if ctx.tool then
    -- For Java tools, set JAVA_HOME
    if ctx.tool:match("java") or ctx.tool:match("jdk") or ctx.tool:match("zulu") then
      table.insert(env_vars, { key = "JAVA_HOME", value = install_path })
    end
    
    -- For Node.js tools, set NODE_HOME (if applicable)
    if ctx.tool:match("node") then
      table.insert(env_vars, { key = "NODE_HOME", value = install_path })
    end
    
    -- For Go tools, set GOROOT (if applicable)  
    if ctx.tool:match("go") then
      table.insert(env_vars, { key = "GOROOT", value = install_path })
    end
  end
  
  return {
    env_vars = env_vars
  }
end
