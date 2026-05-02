# bbe-worktree-toolkit

Plug-and-play scaffolding that turns any git repository into a multi-
agent-friendly workspace using **per-agent git worktrees**. Generalises
the pattern that emerged from BBE-DBE's `bbe-coord` T-003 sprint into
a portable toolkit any project can install.

> **Status:** v0.1.0 (initial release). License: MIT.

## Why

When two or more agents (or developers) work concurrently on the same
git repository through the same working directory, their `git checkout`
calls and unconditional file writes silently overwrite each other's
edits. The race conditions don't show up in test suites because they
depend on session timing.

Per-agent git worktrees solve this structurally: each agent operates on
its own filesystem path, the branches stay shared in the single
repository, and the operating system enforces isolation that no test
fixture can accidentally violate.

Industry adopted the pattern in 2026 (Augment Code, MindStudio, pnpm
parallel builds). This toolkit packages it for any repo and ships
optional Doctrine integration so projects can make the requirement
formal.

## Install

From inside the repository you want to scaffold:

```bash
git clone https://github.com/BBE-DBE/bbe-worktree-toolkit.git ~/.bbe-worktree-toolkit
cd /path/to/your/repo
~/.bbe-worktree-toolkit/install.sh
```

That creates `.worktrees/WORKTREE_LAYOUT.yaml`, drops the three scripts
(`worktree-setup.sh`, `worktree-cleanup.sh`, `worktree-status.sh`) into
`.worktrees/scripts/`, and — if your repo already has
`.worktrees/DOCTRINE.yaml` plus `DOCTRINE_RATIONALE.md` — appends the
required rule and its rationale.

A second `install.sh` run is a safe no-op.

For a different layout dir (e.g. bbe-coord uses `.bbe-coord/`):

```bash
~/.bbe-worktree-toolkit/install.sh --layout-dir .bbe-coord
```

## Daily use

```bash
# Spin up a worktree for a new task
.worktrees/scripts/worktree-setup.sh create track_a T-042 feature/new-thing

# See what's active
.worktrees/scripts/worktree-status.sh

# Clean up merged worktrees (dry-run by default)
.worktrees/scripts/worktree-cleanup.sh
.worktrees/scripts/worktree-cleanup.sh --execute
```

## Files this toolkit ships

| File | Purpose |
|---|---|
| `install.sh` | scaffolds the layout into a target repo |
| `templates/WORKTREE_LAYOUT.yaml.tmpl` | per-repo layout config |
| `templates/worktree-setup.sh` | `create` / `list` / `remove` |
| `templates/worktree-cleanup.sh` | merged-worktree + 24h-stash GC |
| `templates/worktree-status.sh` | read-only summary, table or JSON |
| `templates/doctrine-snippet.yaml` | optional Doctrine rule + rationale |
| `docs/QUICKSTART.md` | five-minute walkthrough |
| `docs/ADVANCED.md` | bare-repo and CI patterns (planned) |
| `docs/MIGRATION.md` | moving from ad-hoc worktrees |
| `docs/TROUBLESHOOTING.md` | common errors |
| `tests/run-all.sh` | runs every test in `tests/` |

## Read next

- [`docs/QUICKSTART.md`](docs/QUICKSTART.md) for first-time setup.
- [`PATTERN.md`](PATTERN.md) for the architectural argument and the
  T-001 / T-002 / T-003 incident that motivated this toolkit.
- [`CHANGELOG.md`](CHANGELOG.md) for version history.

## Design constraints (v0.1.0)

- Bash 4+, GNU sed/awk. Tested on Linux. Not yet validated on
  macOS / BSD (see [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)).
- `git` ≥ 2.5 (worktree subcommand).
- `yq` and `jq` are recommended but only `git` and a POSIX shell are
  strict requirements. Optional tools are detected via `command -v`
  and degrade gracefully.
- All toolkit-installed scripts pass `shellcheck` clean.
- `install.sh` is idempotent: safe to re-run.

## License

MIT — see [`LICENSE`](LICENSE).
