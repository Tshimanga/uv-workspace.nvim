-- Support for uv workspaces in Pyright
-- Automatically adds workspace member paths to extraPaths for proper import resolution

local M = {}

--- Find the uv workspace root by looking for pyproject.toml with [tool.uv.workspace]
--- Searches parent directories starting from start_path
---@param start_path string
---@return string|nil root_path, string|nil pyproject_content
function M.find_uv_workspace_root(start_path)
  local path = start_path
  while path and path ~= "/" do
    local pyproject_path = path .. "/pyproject.toml"
    local f = io.open(pyproject_path, "r")
    if f then
      local content = f:read("*all")
      f:close()
      if content:match("%[tool%.uv%.workspace%]") then
        return path, content
      end
    end
    path = vim.fn.fnamemodify(path, ":h")
  end
  return nil, nil
end

--- Parse workspace members from pyproject.toml content
---@param content string
---@return string[]
function M.parse_workspace_members(content)
  local members = {}
  -- Match the members array, handling multi-line
  local members_section = content:match("members%s*=%s*%[([^%]]+)%]")
  if members_section then
    -- Match both double and single quoted strings
    for member in members_section:gmatch('"([^"]+)"') do
      table.insert(members, member)
    end
    for member in members_section:gmatch("'([^']+)'") do
      table.insert(members, member)
    end
  end
  return members
end

--- Resolve glob patterns to actual directories
---@param root_path string
---@param patterns string[]
---@return string[]
function M.resolve_member_paths(root_path, patterns)
  local paths = {}
  local seen = {}
  for _, pattern in ipairs(patterns) do
    local full_pattern = root_path .. "/" .. pattern
    local matches = vim.fn.glob(full_pattern, false, true)
    for _, match in ipairs(matches) do
      if vim.fn.isdirectory(match) == 1 and not seen[match] then
        table.insert(paths, match)
        seen[match] = true
      end
    end
  end
  return paths
end

--- Compute relative path from one directory to another
---@param from_path string
---@param to_path string
---@return string
function M.relative_path(from_path, to_path)
  -- Normalize paths
  from_path = vim.fn.fnamemodify(from_path, ":p"):gsub("/$", "")
  to_path = vim.fn.fnamemodify(to_path, ":p"):gsub("/$", "")

  local from_parts = vim.split(from_path, "/", { plain = true })
  local to_parts = vim.split(to_path, "/", { plain = true })

  -- Find common prefix
  local common_len = 0
  for i = 1, math.min(#from_parts, #to_parts) do
    if from_parts[i] == to_parts[i] then
      common_len = i
    else
      break
    end
  end

  -- Build relative path
  local up_count = #from_parts - common_len
  local rel_parts = {}
  for _ = 1, up_count do
    table.insert(rel_parts, "..")
  end
  for i = common_len + 1, #to_parts do
    table.insert(rel_parts, to_parts[i])
  end

  return table.concat(rel_parts, "/")
end

--- Get extra paths for Pyright when in a uv workspace member
---@param member_root string The root directory of the current workspace member
---@return string[]
function M.get_workspace_extra_paths(member_root)
  local workspace_root, content = M.find_uv_workspace_root(member_root)
  if not workspace_root or not content then
    return {}
  end

  local member_patterns = M.parse_workspace_members(content)
  if #member_patterns == 0 then
    return {}
  end

  local all_members = M.resolve_member_paths(workspace_root, member_patterns)
  local extra_paths = {}

  -- Normalize member_root for comparison
  local normalized_member_root = vim.fn.fnamemodify(member_root, ":p"):gsub("/$", "")

  for _, member_path in ipairs(all_members) do
    local normalized_member = vim.fn.fnamemodify(member_path, ":p"):gsub("/$", "")
    -- Skip the current member
    if normalized_member ~= normalized_member_root then
      local rel_path = M.relative_path(member_root, member_path)
      table.insert(extra_paths, rel_path)
    end
  end

  return extra_paths
end

-- Plugin spec
return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    opts.servers = opts.servers or {}
    opts.servers.pyright = opts.servers.pyright or {}

    local original_before_init = opts.servers.pyright.before_init

    opts.servers.pyright.before_init = function(init_params, config)
      -- Call original if it exists
      if original_before_init then
        original_before_init(init_params, config)
      end

      local extra_paths = M.get_workspace_extra_paths(config.root_dir)
      if #extra_paths > 0 then
        -- Update config.settings
        config.settings = config.settings or {}
        config.settings.python = config.settings.python or {}
        config.settings.python.analysis = config.settings.python.analysis or {}

        local existing = config.settings.python.analysis.extraPaths or {}
        local all_paths = vim.list_extend({}, existing)

        for _, path in ipairs(extra_paths) do
          if not vim.tbl_contains(all_paths, path) then
            table.insert(all_paths, path)
          end
        end

        config.settings.python.analysis.extraPaths = all_paths

        -- Also update initializationOptions for pyright
        init_params.initializationOptions = init_params.initializationOptions or {}
        init_params.initializationOptions.python = init_params.initializationOptions.python or {}
        init_params.initializationOptions.python.analysis = init_params.initializationOptions.python.analysis or {}
        init_params.initializationOptions.python.analysis.extraPaths = all_paths
      end
    end

    return opts
  end,
}
