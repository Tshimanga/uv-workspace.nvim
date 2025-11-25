# uv-workspace.nvim

A Neovim plugin that enables [Pyright][pyright] to resolve imports between
[uv workspace][uv-workspaces] members.

## Problem

When using uv workspaces (Python monorepos), Pyright cannot resolve imports
between workspace members:

```text
my-workspace/
├── pyproject.toml          # [tool.uv.workspace] members = ["packages/*"]
└── packages/
    ├── foo/
    │   ├── pyproject.toml
    │   └── foo/__init__.py  # defines class Foo
    └── bar/
        ├── pyproject.toml
        └── bar/__init__.py  # from foo import Foo  ← Pyright error!
```

Opening `bar/__init__.py` shows: `Import "foo" could not be resolved`

## Why This Happens

Pyright roots its language server at each workspace member directory
individually. When you open a file in `packages/bar/`, Pyright's root is
`packages/bar/` - it has no knowledge of sibling members like `packages/foo/`.

## Solution

This plugin dynamically configures Pyright's `python.analysis.extraPaths` to
include relative paths to sibling workspace members. When Pyright starts for
`packages/bar/`, the plugin injects:

```json
{
  "python": {
    "analysis": {
      "extraPaths": ["../foo"]
    }
  }
}
```

## Installation

### lazy.nvim

```lua
{
  "Tshimanga/uv-workspace.nvim",
  config = function()
    require("uv-workspace").setup()
  end,
}
```

### lazy.nvim (LazyVim)

For LazyVim users who want to integrate with the existing lspconfig setup:

```lua
{
  "neovim/nvim-lspconfig",
  dependencies = { "Tshimanga/uv-workspace.nvim" },
  opts = function(_, opts)
    opts.servers = opts.servers or {}
    opts.servers.pyright = opts.servers.pyright or {}

    local uv_workspace = require("uv-workspace")
    local original_on_new_config = opts.servers.pyright.on_new_config

    opts.servers.pyright.on_new_config = function(config, root_dir)
      if original_on_new_config then
        original_on_new_config(config, root_dir)
      end

      local extra_paths = uv_workspace.get_workspace_extra_paths(root_dir)
      if #extra_paths > 0 then
        config.settings = config.settings or {}
        config.settings.python = config.settings.python or {}
        config.settings.python.analysis =
          config.settings.python.analysis or {}

        local existing =
          config.settings.python.analysis.extraPaths or {}
        local all_paths = vim.list_extend({}, existing)

        for _, path in ipairs(extra_paths) do
          if not vim.tbl_contains(all_paths, path) then
            table.insert(all_paths, path)
          end
        end

        config.settings.python.analysis.extraPaths = all_paths
      end
    end

    return opts
  end,
}
```

## API

### `setup(opts?)`

Hooks into nvim-lspconfig to automatically configure Pyright for uv workspaces.
Call after lspconfig is loaded.

```lua
require("uv-workspace").setup()
```

### `get_workspace_extra_paths(member_root)`

Returns a list of relative paths to sibling workspace members. Useful for
manual integration.

```lua
local paths = require("uv-workspace").get_workspace_extra_paths(
  "/path/to/packages/bar"
)
-- Returns: { "../foo", "../baz" }
```

### `find_uv_workspace_root(start_path)`

Finds the uv workspace root by searching parent directories for
`pyproject.toml` with `[tool.uv.workspace]`.

```lua
local root, content = require("uv-workspace").find_uv_workspace_root(
  "/path/to/packages/bar"
)
```

### `parse_workspace_members(content)`

Parses workspace member patterns from pyproject.toml content.

```lua
local members = require("uv-workspace").parse_workspace_members(
  pyproject_content
)
-- Returns: { "packages/*" }
```

### `resolve_member_paths(root_path, patterns)`

Resolves glob patterns to actual directory paths.

```lua
local paths = require("uv-workspace").resolve_member_paths(
  "/path/to/workspace",
  { "packages/*" }
)
-- Returns: { "/path/to/workspace/packages/foo", ... }
```

## Requirements

- [nvim-lspconfig][lspconfig]
- [Pyright][pyright] language server

## License

[MIT](LICENSE)

[pyright]: https://github.com/microsoft/pyright
[uv-workspaces]: https://docs.astral.sh/uv/concepts/projects/workspaces/
[lspconfig]: https://github.com/neovim/nvim-lspconfig
