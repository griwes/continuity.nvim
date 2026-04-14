# Continuity

Continuous logical session state for the Neovim plugin orchestration workspace.

## Status

Early development. The current slice provides a standalone repo, typed setup/config, a local session registry with save/load/list/delete behavior, contributor-owned capture hooks, a restore-plan surface, an opt-in continuous live-session tracker with debounced persistence, and a first narrow restore executor with an optional `mksession` substrate for builtin view/layout state. Post-`mksession` replay is contributor-driven through `restore_phase` rather than hardcoded by provider name. Broader replay remains future work.

## Installation

Example local `lazy.nvim` spec:

```lua
{
    dir = vim.fn.expand('~/projects/neovim-plugin-orchestration/continuity.nvim'),
    name = 'continuity.nvim',
    opts = {
        continuous = {
            enabled = true,
            write_debounce_ms = 250,
        },
        mksession = {
            enabled = true,
            capture_live = false,
        },
    },
}
```

By default, `mksession` capture is used for named saved sessions only. The continuous live session keeps its logical state coherent in memory and on disk without writing a Vim session file unless `mksession.capture_live = true` is set explicitly.

When this repo is used inside the full workspace, the test suite also exercises real sibling-provider registrations for:
- `arboretum.nvim + consulate.nvim + terminalia.nvim`
- `arboretum.nvim + laboratory.nvim + terminalia.nvim`

Those integration checks degrade cleanly when the sibling repos are not present, so standalone `continuity.nvim` runs remain valid.

## Current API

- `continuity.api.save(opts)`
- `continuity.api.capture(opts)`
- `continuity.api.load(id)`
- `continuity.api.list()`
- `continuity.api.delete(id)`
- `continuity.api.plan_restore(id_or_record)`
- `continuity.api.execute_restore(id_or_record, opts)`
- `continuity.api.register_contributor(name, contributor)`
- `continuity.api.live_state()`
- `continuity.api.sync_live_state()`
- `continuity.api.notify_contributor_changed(name)`

## Development

- tests live in `tests/`
- formatting is enforced with Stylua
- Lua modules should carry LuaLS annotations and doc comments
- CI lives in `.github/workflows/ci.yml`
