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

Requires [LazyVim][lazyvim] and Neovim 0.11+.

```lua
-- lua/plugins/uv-workspace.lua
return {
  "neovim/nvim-lspconfig",
  dependencies = { "Tshimanga/uv-workspace.nvim" },
  opts = function(_, opts)
    require("uv-workspace").configure_pyright(opts)
    return opts
  end,
}
```

## Requirements

- Neovim 0.11+
- [LazyVim][lazyvim]
- [Pyright][pyright] language server

## License

[MIT](LICENSE)

[pyright]: https://github.com/microsoft/pyright
[uv-workspaces]: https://docs.astral.sh/uv/concepts/projects/workspaces/
[lazyvim]: https://www.lazyvim.org/
