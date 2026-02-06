function PLUGIN:BackendExecEnv(ctx)
  -- ctx.install_path: path where the tool is installed
  local install_path = ctx.install_path
  local env_vars = {}

  -- Always add bin directory to PATH
  table.insert(env_vars, { key = "PATH", value = install_path .. "/bin" })

  -- Try to read MTA config for environment variables
  local config_path = install_path .. "/.mta-config.json"
  local config_handle = io.open(config_path, "r")
  if config_handle then
    local config_json = config_handle:read("*all")
    config_handle:close()

    -- Parse env section using jq
    local jq_cmd = string.format("echo '%s' | jq -r '.env // {} | to_entries[] | \"\\(.key)=\\(.value)\"' 2>/dev/null", config_json:gsub("'", "'\\''"))
    local jq_handle = io.popen(jq_cmd)
    if jq_handle then
      for line in jq_handle:lines() do
        local key, value = line:match("^([^=]+)=(.*)$")
        if key and value then
          -- Template substitution for install_path
          value = value:gsub("{{%s*install_path%s*}}", install_path)

          -- Template substitution for any env var reference like {{ VAR_NAME }}
          value = value:gsub("{{%s*([%w_]+)%s*}}", function(var_name)
            return os.getenv(var_name) or ""
          end)

          -- Clean up empty path segments (from undefined env vars)
          value = value:gsub(":+", ":")
          value = value:gsub("^:", "")
          value = value:gsub(":$", "")

          -- Skip PATH entries (already handled above)
          if key ~= "PATH" then
            table.insert(env_vars, { key = key, value = value })
          end
        end
      end
      jq_handle:close()
    end
  end

  return {
    env_vars = env_vars
  }
end
