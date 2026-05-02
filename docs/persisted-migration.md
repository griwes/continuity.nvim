# Migrating from persisted.nvim

Continuity can replace the common `persisted.nvim` setup where sessions are
autoloaded by cwd plus Git branch and `sessionoptions` is configured globally.

## Persisted Configuration

The current live-config shape is:

```lua
vim.o.sessionoptions = 'blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,globals'

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
    },
}
```

This moves `sessionoptions` from a global editor mutation into Continuity's
`mksession.sessionoptions`. Continuity applies that value only while capturing a
Vim session file and restores the ambient option afterward.

## Behavior Mapping

| persisted.nvim | continuity.nvim |
| --- | --- |
| `use_git_branch = true` | `session_key.use_git_branch = true` |
| `autoload = true` | `autoload.policy = 'cwd_branch'` |
| global `vim.o.sessionoptions = ...` | `mksession.sessionoptions = { ... }` |
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

Optional Vim `:mksession` files are stored at:

```text
stdpath('state')/continuity.nvim/mksession/<sanitized-session-id>.vim
```

The metadata file stores Continuity records, contributor payloads, the last
session id, and the next sequential id. It does not reuse or import
persisted.nvim's storage format, so old persisted.nvim session files can be
kept for rollback while new Continuity records are created.

## Live Session Semantics

`continuous.enabled = true` keeps a debounced live session record updated from
editor autocmds and plugin contributor notifications. With
`continuous.session_id = 'auto'`, the live session key is derived from the
current cwd and Git branch.

By default, live sessions do not write `:mksession` files. This avoids rewriting
large Vim session files on every debounced update. Named sessions saved through
`:ContinuitySave` still capture `mksession` when `mksession.enabled = true`.
Set `mksession.capture_live = true` only if the live session itself should also
write Vim session files.

## Plugin-Owned State

Continuity is not just a `:mksession` wrapper. Plugins can register contributors
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
