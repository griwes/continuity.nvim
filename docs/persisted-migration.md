# Migrating from persisted.nvim

Continuity can replace the common `persisted.nvim` setup where sessions are
autoloaded by cwd plus Git branch. Unlike persisted.nvim, Continuity does not
use `:mksession` as its normal substrate; it stores an opinionated structured
JSON model and restores that model directly.

## Persisted Configuration

The current live-config shape is:

```lua
return {
    {
        'olimorris/persisted.nvim',
        lazy = false,
        config = function()
            require('persisted').setup({
                use_git_branch = true,
                autoload = true,
            })
        end,
    },
}
```

## Continuity Configuration

The matching Continuity shape is:

```lua
return {
    {
        dir = vim.fn.expand('~/projects/neovim-plugin-orchestration/continuity.nvim'),
        name = 'continuity.nvim',
        main = 'continuity',
        lazy = false,
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
            shada = {
                external_policy = 'warn',
            },
        },
    },
}
```

There is no `sessionoptions` migration step. Continuity captures buffers, tabs,
windows, layout, views, and selected editor history directly into its session
record.

## Behavior Mapping

| persisted.nvim | continuity.nvim |
| --- | --- |
| `use_git_branch = true` | `session_key.use_git_branch = true` |
| `autoload = true` | `autoload.policy = 'cwd_branch'` |
| global `vim.o.sessionoptions = ...` | not needed; Continuity does not use `:mksession` |
| manual save/load commands | `:ContinuitySave`, `:ContinuityLoad`, `:ContinuityList`, `:ContinuityDelete`, `:ContinuityCurrent` |
| one session per cwd/branch | derived `session:<cwd-name>:<branch>:<digest>` keys |

Continuity's `cwd_branch` autoload policy restores the exact session id derived
from the current cwd and Git branch. If that exact session does not exist,
startup records the miss in `require('continuity').last_autoload` instead of
failing. Use `autoload.policy = 'cwd'` when the desired behavior is "newest saved
session for this cwd regardless of branch".

## Storage

Continuity stores session metadata at:

```text
stdpath('state')/continuity.nvim/sessions.json
```

That file is only a compact index with session metadata, the last session id,
and the next sequential id. Full Continuity records, including builtin editor
state and contributor payloads, are stored one file per session under:

```text
stdpath('state')/continuity.nvim/sessions/
```

If a config overrides only `state_file`, Continuity derives the record directory
as `state_file .. '.d'` so tests and custom setups remain isolated. It does not
reuse or import persisted.nvim's storage format, so old persisted.nvim session
files can be kept for rollback while new Continuity records are created.

## Live Session Semantics

`continuous.enabled = true` keeps a debounced live session record updated from
editor autocmds and plugin contributor notifications. With
`continuous.session_id = 'auto'`, the live session key is derived from the
current cwd and Git branch.

Live and named sessions use the same fragmented JSON substrate. No Vim session
files are written.

## Plugin-Owned State

Continuity is not a `:mksession` wrapper. Plugins can register contributors
that capture and replay logical state:

- `terminalia.nvim` reopens canonical terminal URIs after workspace context is
  restored.
- `arboretum.nvim`, `consulate.nvim`, and `laboratory.nvim` restore worktree,
  remote, and devcontainer context before terminal reopen.
- `tabulature.nvim` restores selected nested tab hierarchy state.

This means dogfood sessions can recover logical terminal and tab state that
would be fragile or missing in plain Vim session files.

## Operational Notes

- Keep `lazy = false` for Continuity when autoloading on startup.
- Use `:ContinuityCurrent` to inspect the derived session key and active live
  session.
- Use `:ContinuityList` to inspect saved records before deleting old sessions.
- Rollback is straightforward: disable the Continuity lazy spec and re-enable
  persisted.nvim. The storage locations are separate.
