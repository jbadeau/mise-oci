local json = require("json")
local file = require("file")

function PLUGIN:BackendExecEnv(ctx)
  local install_path = ctx.install_path
  local env_vars = {}

  -- Always add bin directory to PATH
  table.insert(env_vars, { key = "PATH", value = file.join_path(install_path, "bin") })

  -- Try to read MTA config for environment variables
  local config_path = file.join_path(install_path, ".mta-config.json")
  local config_handle = io.open(config_path, "r")
  if config_handle then
    local config_raw = config_handle:read("*all")
    config_handle:close()

    local ok, config = pcall(json.decode, config_raw)
    if ok and config and config.env then
      for key, value in pairs(config.env) do
        -- Template substitution: {{ install_path }}
        value = value:gsub("{{%s*install_path%s*}}", install_path)

        -- Template substitution: {{ path_list_sep }}
        local sep = (RUNTIME.osType == "windows") and ";" or ":"
        value = value:gsub("{{%s*path_list_sep%s*}}", sep)

        -- Template substitution: {{ VAR_NAME }} for any env var
        value = value:gsub("{{%s*([%w_]+)%s*}}", function(var_name)
          return os.getenv(var_name) or ""
        end)

        -- Clean up empty path segments
        value = value:gsub(":+", ":")
        value = value:gsub("^:", "")
        value = value:gsub(":$", "")

        -- Skip PATH entries (already handled above)
        if key ~= "PATH" then
          table.insert(env_vars, { key = key, value = value })
        end
      end
    end
  end

  return {
    env_vars = env_vars
  }
end
