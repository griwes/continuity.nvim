# Continuity

Continuous logical session state for the Neovim plugin orchestration workspace.

## Status

Early development. The current slice provides a standalone repo, typed setup/config, a local session registry with save/load/list/delete behavior, opt-in cwd/Git-branch session keys, explicit startup autoload policies, contributor-owned capture hooks, a restore-plan surface, an opt-in continuous live-session tracker with debounced persistence, and a first narrow restore executor with an optional `mksession` substrate for builtin view/layout state. Post-`mksession` replay is contributor-driven through `restore_phase` rather than hardcoded by provider name. Broader replay remains future work.

## Installation

Example local `lazy.nvim` spec:

```lua
{
    dir = vim.fn.expand('~/projects/neovim-plugin-orchestration/continuity.nvim'),
    name = 'continuity.nvim',
    opts = {
        continuous = {
            enabled = true,
            session_id = 'auto',
            write_debounce_ms = 250,
        },
        session_key = {
            use_git_branch = true,
        },
        autoload = {
            policy = 'cwd_branch',
        },
        mksession = {
            enabled = true,
            capture_live = false,
            sessionoptions = {
                'blank',
                'buffers',
                'curdir',
                'folds',
                'help',
                'tabpages',
                'winsize',
                'winpos',
                'terminal',
                'globals',
            },
        },
    },
}
```

For a direct replacement of the current persisted.nvim-style setup, see
[`docs/persisted-migration.md`](docs/persisted-migration.md).

By default, `mksession` capture is used for named saved sessions only. The continuous live session keeps its logical state coherent in memory and on disk without writing a Vim session file unless `mksession.capture_live = true` is set explicitly.

Set `mksession.sessionoptions` to a comma-separated string or a list of option
names when Continuity should capture Vim session files with a known option set.
When unset, Continuity preserves Neovim's ambient `sessionoptions` behavior. A
configured value is applied only for the `:mksession` capture call and the
previous editor option is restored afterward. An explicitly empty string or
empty list captures with empty `sessionoptions`; use `nil`/omit the key for
ambient behavior.

Set `session_key.use_git_branch = true` to derive new implicit session IDs
from the current cwd and Git branch instead of allocating sequential
`session:N` IDs. Set `continuous.session_id = 'auto'` to use that same derived
session key for live session persistence.

Set `autoload.policy` to choose startup restore behavior. The default is
`'disabled'`; other supported policies are `'cwd'`, `'cwd_branch'`, and
`'last'`. Startup autoload records misses or restore failures in
`require('continuity').last_autoload` instead of failing Neovim startup.

Continuous saving is opt-in. Set `continuous.enabled = true` to keep one live
session record updated through editor autocmds and contributor notifications,
debounced by `continuous.write_debounce_ms`. Named sessions are still saved
explicitly through `continuity.api.save()`, `continuity.api.capture()`, or
`:ContinuitySave`.

When this repo is used inside the full workspace, the test suite also exercises real sibling-provider registrations for:
- `arboretum.nvim + consulate.nvim + terminalia.nvim`
- `arboretum.nvim + laboratory.nvim + terminalia.nvim`
- `arboretum.nvim + consulate.nvim + laboratory.nvim + tabulature.nvim + terminalia.nvim`

Those integration checks degrade cleanly when the sibling repos are not present, so standalone `continuity.nvim` runs remain valid.

## Current API

- `continuity.api.save(opts)`
- `continuity.api.capture(opts)`
- `continuity.api.autoload()`
- `continuity.api.current_session_key(opts)`
- `continuity.api.load(id)`
- `continuity.api.list()`
- `continuity.api.session_items()`
- `continuity.api.session_lines()`
- `continuity.api.delete(id)`
- `continuity.api.plan_restore(id_or_record)`
- `continuity.api.execute_restore(id_or_record, opts)`
- `continuity.api.register_contributor(name, contributor)`
- `continuity.api.live_state()`
- `continuity.api.sync_live_state()`
- `continuity.api.notify_contributor_changed(name)`

## Commands

- `:ContinuitySave [name]` captures the current session and registered contributors.
- `:ContinuityList` opens a `vim.ui.select` picker to inspect saved sessions.
- `:ContinuityLoad [id]` restores a session directly, or opens a picker when no id is provided.
- `:ContinuityDelete [id]` deletes a session directly, or opens a picker when no id is provided.
- `:ContinuityCurrent` shows the current derived session key and active live session.

Picker integrations can use `continuity.api.session_items()` directly. Items
include stable fields such as `id`, `value`, `name`, `cwd`, `branch`,
`is_current`, `is_last`, `label`, `detail`, `ordinal`, and `record`.

## Development

- tests live in `tests/`
- formatting is enforced with Stylua
- Lua modules should carry LuaLS annotations and doc comments
- CI lives in `.github/workflows/ci.yml`
