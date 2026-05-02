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
