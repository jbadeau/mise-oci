function PLUGIN:BackendExecEnv(ctx)
  -- ctx.install_path: path where the tool is installed
  local install_path = ctx.install_path
  local env_vars = {}
  
  -- Always add bin directory to PATH
  table.insert(env_vars, { key = "PATH", value = install_path .. "/bin" })
  
  -- For Java tools, set JAVA_HOME
  if ctx.tool and ctx.tool:match("java") or ctx.tool:match("jdk") or ctx.tool:match("zulu") then
    table.insert(env_vars, { key = "JAVA_HOME", value = install_path })
  end
  
  -- For Node.js tools, set NODE_HOME (if applicable)
  if ctx.tool and ctx.tool:match("node") then
    table.insert(env_vars, { key = "NODE_HOME", value = install_path })
  end
  
  -- For Go tools, set GOROOT (if applicable)  
  if ctx.tool and ctx.tool:match("go") then
    table.insert(env_vars, { key = "GOROOT", value = install_path })
  end
  
  return {
    env_vars = env_vars
  }
end
