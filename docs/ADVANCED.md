# ADVANCED — patterns beyond the quickstart

This document collects patterns that aren't needed for first-time
installation but become relevant as the toolkit gets used in larger
projects.

## Bare-repo layout (v0.2.0, first-class)

A bare git repo is the cleanest way to host many worktrees: no "main"
working tree to be confused with the worktree base, every worktree is
peer to every other. v0.2.0 makes this layout a first-class option in
`install.sh` alongside the v0.1.x sibling layout.

The on-disk shape:

```
~/projects/
  myrepo/
    .bare/                     # bare clone (the "git database")
    .git                       # pointer file: gitdir: ./.bare
    main/                      # worktree on main branch
    track_a-T-001/             # worktree, peer of main
    track_b-T-001/             # worktree, peer of main
```

Compare with sibling:

```
~/projects/
  myrepo/                      # regular checkout
    .git/                      # standard git directory
  myrepo-worktrees/
    track_a-T-001/             # worktree
    track_b-T-001/             # worktree
```

### Auto-detection

Run `install.sh` from anywhere inside the repo and it picks the right
mode:

```bash
cd ~/projects/myrepo            # sibling root, or
cd ~/projects/myrepo/main       # bare root → main worktree
~/.bbe-worktree-toolkit/install.sh
```

The layout YAML's `layout_mode` field records the decision so the
lifecycle scripts behave consistently from any worktree. The
`worktree-status.sh --info` subcommand reports the resolved mode:

```bash
$ .worktrees/scripts/worktree-status.sh --info
{"layout_mode":"bare","layout_file":"...","main_root":"..."}
```

### Forcing a mode

```bash
~/.bbe-worktree-toolkit/install.sh --layout sibling   # always sibling
~/.bbe-worktree-toolkit/install.sh --layout bare      # requires bare
~/.bbe-worktree-toolkit/install.sh --layout auto      # default
```

`--layout bare` on a non-bare repo exits 1 and points at
`scripts/migrate-to-bare.sh` for conversion. See
[`docs/MIGRATION.md`](MIGRATION.md) for the migration walkthrough.

### Why bare layout

- **No primary checkout.** `main/` is just another worktree; nothing
  is "the repo". Useful when most work happens in feature worktrees
  and `main/` is only ever read.
- **Disk locality.** All worktrees live under one directory, so
  `~/projects/myrepo/` is a complete picture of the repo's state.
- **Safer cleanup.** A defensive guard in
  `worktree-cleanup.sh` (v0.2.0+) refuses to remove worktrees on
  `main` or `master`, so cleanup-from-feature-worktree cannot
  accidentally drop the primary checkout.

## CI gating with `--check`

In a GitHub Actions or other CI pipeline, refuse to build code that
wasn't authored in an isolated worktree:

```yaml
- name: enforce multi-worktree mode
  run: ./.worktrees/scripts/worktree-status.sh --check
```

`--check` exits 0 when:
- the layout YAML exists, AND
- at least one worktree besides the main checkout is registered.

In a single-developer repo where multi-worktree mode is overkill, the
gate is unnecessary; remove the step or invert it with `||`.

## JSON output for tooling

`worktree-status.sh --json` emits one object per worktree:

```json
[
  {
    "branch": "main",
    "path": "/home/dev/projects/myrepo",
    "head": "a1b2c3d4e5f6789012345678901234567890abcd",
    "kind": "worktree",
    "is_main_checkout": true
  },
  {
    "branch": "feature/x",
    "path": "/home/dev/projects/myrepo-worktrees/track_a-T-042",
    "head": "fedcba0987654321...",
    "kind": "worktree",
    "is_main_checkout": false
  }
]
```

Pipe through `jq` for ad-hoc queries:

```bash
.worktrees/scripts/worktree-status.sh --json \
  | jq '.[] | select(.is_main_checkout == false) | .branch'
```

## Doctrine integration on existing projects

If your repo already maintains a `DOCTRINE.yaml` (BBE-DBE format):

1. Run `install.sh --layout-dir <wherever-doctrine-lives>`. The
   installer detects `DOCTRINE.yaml` and `DOCTRINE_RATIONALE.md` and
   appends a marked block to each.
2. Inspect the diff. The block is delimited by
   `# >>> bbe-worktree-toolkit T-030 BEGIN <<<` /
   `# >>> bbe-worktree-toolkit T-030 END <<<`.
3. If your existing structure is exotic (nested mappings, anchors,
   non-standard sections), you may prefer to copy the snippet from
   `templates/doctrine-snippet.yaml` and paste it manually under your
   own `mandatory_for_every_sprint:` mapping. Either way, keep the
   markers — the installer uses them to detect prior installation.

To remove the block later: `install.sh --uninstall`. Marked block is
stripped in place; surrounding content is untouched.

## Custom track names

Tracks are restricted to `track_a`, `track_b`, `track_c` in v0.1.0 to
match the BBE-DBE multi-agent convention. If you need different names
(`team_alpha`, `worker_42`), edit `worktree-setup.sh:cmd_create` to
relax the case match. A future toolkit version may make this
configurable in the layout YAML.

## Shared state outside any worktree

Set `central_state_dir` in your layout YAML to a path *outside* the
worktree base, e.g. `../<name>-state`. `worktree-setup.sh create` will
create this directory on first run and seed `<central_state_file>`
from the worktree's committed copy. Multiple worktrees then read and
write the same file — single source of truth.

For BBE-DBE-style projects this is where `SPRINT_STATE.json` lives. For
other projects it's a useful place for any "what is the global view of
the project right now" file that should not be branch-versioned.

## Disk-space management

Each worktree adds roughly the size of a clean checkout. For a 500 MB
codebase, three worktrees cost ~1.5 GB. Mitigation:

- `git gc --auto` runs in each worktree but compacts the shared
  `.git/objects` once.
- `worktree-cleanup.sh --execute` removes worktrees whose branches are
  merged or deleted. Run weekly or via a cron.
- `git worktree prune` (run from any worktree) removes administrative
  remnants of worktrees that were deleted via `rm -rf` rather than
  `worktree remove`.

## Roadmap

- v0.2.0: bare-repo layout
- v0.2.x: macOS / BSD compatibility (date-format probe, `mapfile`
  fallback)
- v0.3.0: layout-driven track-name customisation
- v0.4.0: integration with `tmux-bootstrap.sh` (one tmux session per
  worktree)

Open issues / requests: see the GitHub repo.
