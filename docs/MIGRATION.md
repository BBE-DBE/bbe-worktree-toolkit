# MIGRATION — moving an existing project to the toolkit

If you've been creating worktrees by hand (`git worktree add ../foo
some-branch`) and want to standardise on the toolkit's conventions,
this is for you.

## What changes

| Before | After |
|---|---|
| Worktree paths are ad-hoc | `<base_path>/<track>-<task_id>` |
| Lifecycle is manual `git worktree` invocations | `worktree-setup.sh create / list / remove` |
| No central state convention | Optional `central_state_dir` in layout YAML |
| No GC for stale worktrees / stashes | `worktree-cleanup.sh` with 24h+ stash threshold |

Nothing requires migration on day one — the toolkit's scripts work
alongside any existing worktrees you already have. You can adopt
incrementally.

## Step-by-step

### 1. Inventory existing worktrees

```bash
git worktree list
```

Decide which ones are still active and which can be cleaned up. The
toolkit will not delete them automatically.

### 2. Install

```bash
~/.bbe-worktree-toolkit/install.sh
```

This adds `.worktrees/WORKTREE_LAYOUT.yaml` and the three lifecycle
scripts. It does not touch your existing worktrees.

### 3. Adjust the layout YAML to match what you already have

Open `.worktrees/WORKTREE_LAYOUT.yaml`. The default `base_path` is
`../<repo>-worktrees`. If your existing worktrees live elsewhere
(e.g. `../scratch/`), update `base_path` so the lifecycle scripts can
find and manage them.

If your existing path naming differs from `<track>-<task_id>` (e.g.
plain branch names), update the `pattern` field. Available
substitutions: `{track}`, `{task_id}`.

### 4. Decide on tracks

Pick a 2- or 3-letter convention. The default scripts accept
`track_a`, `track_b`, `track_c`. Common choices:

- BBE-DBE / multi-agent: `track_a` (codex), `track_b` (claude),
  `track_c` (reserved).
- Pair programming: `track_a`, `track_b`.
- Solo with parallel branches: `track_a` only — see
  [doctrine integration](#doctrine-integration-optional) for the
  solo-sprint exemption.

### 5. Optional: rename existing worktrees to the convention

If you want existing worktrees to participate in `worktree-setup.sh
list` and `worktree-cleanup.sh`, rename their directories to match:

```bash
mv ../scratch/feature-x ../<repo>-worktrees/track_a-T-042
git -C ../<repo>-worktrees/track_a-T-042 status   # confirm
```

Then `git worktree repair` from the main repo so git updates its
administrative records.

### 6. Migrate central state (if any)

If you have a "shared" file across worktrees (a sprint state, a
config, a queue), move it to a directory *outside* the worktree base
and set `central_state_dir` in the layout YAML to that path. The
toolkit's `worktree-setup.sh create` will then seed new worktrees from
it.

Example BBE-DBE migration:

```bash
mkdir -p ../bbe-coord-state
mv .bbe-coord/SPRINT_STATE.json ../bbe-coord-state/
yq -i '.central_state_dir = "../bbe-coord-state"' .bbe-coord/WORKTREE_LAYOUT.yaml
yq -i '.central_state_file = "SPRINT_STATE.json"' .bbe-coord/WORKTREE_LAYOUT.yaml
```

### 7. Doctrine integration (optional)

If your repo already has a `DOCTRINE.yaml` plus `DOCTRINE_RATIONALE.md`,
re-run install:

```bash
~/.bbe-worktree-toolkit/install.sh --layout-dir .bbe-coord
```

The installer detects existing doctrine files and appends a marked
block. The block is idempotent — safe to re-run.

If the doctrine integration produces a rule you don't want, run
`install.sh --uninstall` to remove the marked block (rest of doctrine
stays intact).

## What you do NOT have to do

- You do **not** have to delete existing worktrees. They keep working.
  `worktree-setup.sh list` simply may not show them with structured
  track/task columns until you rename them to the convention.
- You do **not** have to switch all branches at once. Adopt the
  pattern for new sprints; existing branches finish in their existing
  worktrees.
- You do **not** have to use central state. Leave `central_state_dir`
  empty and the lifecycle scripts won't seed or share anything.

## Rollback

If you decide the toolkit isn't a good fit:

```bash
~/.bbe-worktree-toolkit/install.sh --uninstall
```

This removes `.worktrees/scripts/*` and the layout YAML, plus any
marked doctrine blocks. Your worktrees themselves are not touched.

---

## From Sibling to Bare-Repo

Sibling layout (the toolkit's v0.1.0 default) treats one repo as the
"main" checkout and lays its worktrees out in a sibling directory
(`<repo>-worktrees/`). Bare-repo layout treats every branch as a
peer worktree under one parent directory, with the git data in a
nested `.bare/` directory. See
[`BARE_REPO_PATTERN.md`](BARE_REPO_PATTERN.md) for the full
comparison and trade-offs.

This section documents the migration path from sibling layout
(v0.1.x install) to bare-repo layout. The toolkit ships
`scripts/migrate-to-bare.sh` to automate the steps.

**Status (v0.2.0):** the migration script is the supported path to
move a sibling-layout repo to bare layout. The
`--i-understand-the-risk` gate is **deliberately retained** in
v0.2.0 — the v0.1.1 changelog announced its removal, but the
migration is irreversible at the `.git`-layout level and a typo on
a production repo is unrecoverable. CI environments that need an
unattended migration set `WTT_MIGRATE_CONFIRM=1`.

After migration, run `install.sh --layout bare` (or the default
`--layout auto`, which detects the new layout) to refresh the
templates with bare-mode awareness.

### What the migration does, conceptually

| Before | After |
|---|---|
| `~/projects/myrepo/` is the main repo (working tree + `.git/`) | `~/projects/myrepo/.bare/` is the bare git directory; `~/projects/myrepo/main/` is the main branch as a worktree |
| `~/projects/myrepo-worktrees/track_a-T-001/` is a worktree | `~/projects/myrepo/track_a-T-001/` is a worktree (moved one level up) |
| Removing `myrepo/` breaks worktrees | Removing any single worktree leaves the others intact |

Refs, branches, tags, stashes, reflog, and config survive intact.
Uncommitted changes per worktree survive — the script does not
checkout-overwrite them. What's preserved:

- `.git/refs/heads/*` (all branch tips)
- `.git/refs/tags/*`
- `.git/refs/stash` (current stashes)
- `.git/config`
- per-worktree HEAD reflog (`.git/worktrees/<name>/HEAD`)
- per-worktree uncommitted changes

What's NOT preserved automatically:

- Hooks under `.git/hooks/` that you've manually edited (the bare
  clone gets default hooks; the script copies your customised
  hooks into `.bare/hooks/` if they exist)
- IDE-specific caches under `.git/<ide-name>/` (e.g.
  `.git/jetbrains/`) — recreated on next IDE open
- Per-worktree config (`.git/worktrees/<name>/config.worktree`) —
  re-derived from the new bare layout, settings revert to defaults

### Step-by-step migration

#### 1. Pre-flight checks

```bash
cd ~/projects/myrepo
git status                           # commit or stash anything you want preserved
git fetch --all
.worktrees/scripts/worktree-status.sh
```

Verify every worktree shows up. Note any branch with uncommitted
changes — those will survive but you may want a clean slate first.

#### 2. Run the migration in dry-run mode

```bash
~/.bbe-worktree-toolkit/scripts/migrate-to-bare.sh
```

This prints the plan in five stages — Backup, Detect, Convert,
Reattach, Verify — without modifying anything. Read every line.
The output ends with a summary of what would change.

#### 3. Take a backup

The script's default `--execute` path includes a compact backup
(`.git/` + stash bundle + uncommitted-changes summary, written to
`.bbe-worktree-toolkit-backup/<timestamp>/`). For peace of mind:

```bash
cp -r ~/projects/myrepo /tmp/myrepo-pre-migration-backup
```

Or use `--full-backup` to make the script tar.gz everything.

#### 4. Execute

```bash
~/.bbe-worktree-toolkit/scripts/migrate-to-bare.sh \
  --execute \
  --i-understand-the-risk
```

(or set `WTT_MIGRATE_CONFIRM=1` instead of the flag.) The script
walks through the five stages, printing each step. The Convert
stage runs `git clone --bare`, the Reattach stage adds each
worktree to the new bare directory.

#### 5. Verify

```bash
cd ~/projects/myrepo
ls                                   # you should see main/, track_a-T-001/, etc., AND .bare/
git -C main worktree list           # all worktrees registered
.worktrees/scripts/worktree-status.sh --check
```

Open one of your worktrees in your IDE and check uncommitted
changes survived.

#### 6. Update the toolkit layout file

The layout file's `base_path` was `../myrepo-worktrees/` under
sibling layout. Under bare-repo layout, all worktrees live under
the parent directory. Update:

```yaml
# Old (sibling)
base_path: "../myrepo-worktrees"
# New (bare)
base_path: "."
```

The script does this automatically when run with `--execute
--i-understand-the-risk`. Double-check the layout file is what you
expect.

### Risks

#### Lost worktrees

If the script aborts after the Convert stage but before Reattach,
the bare repo exists but worktrees haven't been re-added. Recovery:

```bash
cd ~/projects/myrepo/.bare
git worktree add ../main main
git worktree add ../track_a-T-001 feature/A
# ... etc, one per branch you had a worktree for
```

The list of branches that had worktrees is in
`.bbe-worktree-toolkit-backup/<timestamp>/worktrees.txt` (created by
the Detect stage).

#### Broken refs

If the bare clone misses any refs (e.g. namespaced refs not
exported by `git clone --bare`), they won't appear in the new
layout. Recovery: the backup `.git/` is preserved; you can
`git fetch <backup_path>` from the new bare layout to pick up any
missed refs.

#### IDE cache

VS Code and JetBrains IDEs cache file metadata keyed off the
`.git/` directory. After migration, the path to `.git/` changes
(it's now `.bare/`). The IDEs will re-index on next open — slow
but not destructive.

#### Disk space spike

During migration the script holds:
- The original repo
- The compact backup (or full tar.gz with `--full-backup`)
- The new bare clone
- The reattached worktrees

Peak disk usage is ~3× the original repo size for a few minutes.
Make sure you have headroom.

### Rollback

If migration goes wrong, the backup is your friend:

```bash
mv ~/projects/myrepo ~/projects/myrepo-broken
cp -r /tmp/myrepo-pre-migration-backup ~/projects/myrepo
```

Or, if you used the script's built-in backup:

```bash
mv ~/projects/myrepo ~/projects/myrepo-broken
mv ~/projects/myrepo-broken/.bbe-worktree-toolkit-backup/<ts> ~/projects/myrepo
```

The backup directory contains the original `.git/` and the stash
bundle. Restore by overlaying onto a fresh clone if necessary.

### When NOT to migrate

- Repo is small (single-developer, one or two branches at a time):
  sibling layout is simpler. Cost of migration > benefit.
- IDE doesn't handle bare layouts well and you don't want to fight
  it.
- You're on a deadline. Migration is a 5-minute task on a clean
  repo and a multi-hour task on a complex one. Pick a quiet
  afternoon.

### After migration

- Existing branches continue to work; their worktrees are now under
  the parent directory.
- New worktrees: `worktree-setup.sh create track_a T-042 feature/x`
  creates them under the parent directory using the updated
  `base_path: "."` layout.
- `worktree-cleanup.sh` works against the new layout transparently —
  no script changes required for v0.2.0+.
- The `migrate-to-bare.sh` script is idempotent: a second run
  detects the bare layout already exists and exits cleanly.
