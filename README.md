# session.nvim

Typed logical session metadata for the Neovim plugin orchestration workspace.

## Status

Early development. The current slice provides a standalone repo, typed setup/config, a local session metadata registry with save/load/list/delete behavior, contributor-owned capture hooks, a restore-plan surface, and an opt-in continuous live-session tracker with debounced persistence. Full replay remains future work.

## Installation

Example local `lazy.nvim` spec:

```lua
{
    dir = vim.fn.expand('~/projects/neovim-plugin-orchestration/session.nvim'),
    name = 'session.nvim',
    opts = {
        continuous = {
            enabled = true,
            write_debounce_ms = 250,
        },
    },
}
```

## Current API

- `session.api.save(opts)`
- `session.api.capture(opts)`
- `session.api.load(id)`
- `session.api.list()`
- `session.api.delete(id)`
- `session.api.plan_restore(id_or_record)`
- `session.api.register_contributor(name, contributor)`
- `session.api.live_state()`
- `session.api.sync_live_state()`
- `session.api.notify_contributor_changed(name)`

## Development

- tests live in `tests/`
- formatting is enforced with Stylua
- Lua modules should carry LuaLS annotations and doc comments
- CI lives in `.github/workflows/ci.yml`
