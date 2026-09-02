# Continuity

Continuous logical session state for Neovim.

## Status

Early development. The current slice provides a standalone repo, typed setup/config, a local session registry with save/load/list/delete behavior, opt-in cwd/Git-branch session keys, explicit startup autoload policies, contributor-owned capture hooks, a restore-plan surface, an opt-in continuous live-session tracker with debounced persistence, and a structured JSON restore executor for builtin editor layout. Contributor replay is ordered around the structured layout boundary through `restore_phase`, and jump/change contents are restored through Continuity-owned synthetic ShaDa fragments where Neovim lacks public setters.

## Requirements

- Neovim 0.11 or newer
- optional provider plugins such as `terminalia.nvim` for contributor-owned
  state

Linux is the primary supported and CI-tested platform. The project is in early
development and currently publishes from `main` without a stable release tag.

## Installation

With `lazy.nvim`:

```lua
{
    'griwes/continuity.nvim',
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
            -- "warn" warns if external ShaDa is configured during restore.
            -- Use "error" for strict Continuity-owned sessions.
            external_policy = 'warn',
        },
    },
}
```

Run `:checkhealth continuity` after installation. See `:help continuity` for a
compact command and API reference.

For a direct replacement of the current persisted.nvim-style setup, see
[`docs/persisted-migration.md`](docs/persisted-migration.md).

Continuity does not use `:mksession` for normal save or restore. Builtin editor
state is captured into the JSON record as buffers, tabs, windows, layout trees,
views, jumplists, and changelists. Restore recreates that structure directly
through Neovim APIs. Jump/change contents are restored by generating minimal
temporary ShaDa fragments that contain only Continuity-owned entries.

Set `shada.external_policy = 'error'` for strict sessions that must not run
while external user ShaDa is configured. The default `warn` mode allows restore
but reports that user ShaDa may affect fidelity; `ignore` is useful in tests or
when another part of the config already controls ShaDa isolation.

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
`:ContinuitySave`. Live writes do not replace the last deliberate clean
snapshot: explicit captures and clean Neovim exits also write a `::clean`
snapshot for the same live session, and that snapshot appears as its own
loadable picker item. Branch-specific autoload also prefers the clean snapshot
when it exists.

Continuity keeps `state_file` as a small index and writes full records as
one JSON file per session under `state_dir`. When only `state_file` is
overridden, `state_dir` defaults to `state_file .. '.d'`; the built-in default
uses `stdpath('state')/continuity.nvim/sessions/`.

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
`is_current`, `is_last`, `snapshot_kind`, `base_id`, `label`, `detail`,
`ordinal`, and `record`.

## Development

Run `scripts/ci/run.sh` for the repository-local Stylua, test, and clean-install
smoke checks. GitHub Actions runs the tests and clean-install smoke checks on
Neovim 0.11.5, stable, and nightly. A separate lint job runs Stylua and
validates workflow syntax with actionlint. Tests live under `tests/`; the
workflow is `.github/workflows/ci.yml`.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
