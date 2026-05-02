# QUICKSTART — bbe-worktree-toolkit in 5 minutes

This walkthrough installs the toolkit into a fresh git repo and
demonstrates the create/status/cleanup lifecycle. Total time: ~5 min.

## Prerequisites

- bash ≥ 4
- git ≥ 2.5
- (optional) yq + jq — used by some lifecycle scripts; install via your
  package manager if you want full features.

## 1. Install the toolkit

Clone the toolkit somewhere you can reuse it:

```bash
git clone https://github.com/BBE-DBE/bbe-worktree-toolkit.git ~/.bbe-worktree-toolkit
```

## 2. Scaffold a target repo

From inside the repository you want to enable multi-worktree mode for:

```bash
cd /path/to/your/repo
~/.bbe-worktree-toolkit/install.sh
```

You should see output like:

```
install: installing into /path/to/your/repo
install:   layout dir   = .worktrees
install:   base path    = ../<repo-name>-worktrees
install:   toolkit ver  = 0.1.0
install:   /path/to/your/repo/.worktrees/scripts/worktree-setup.sh creating
install:   /path/to/your/repo/.worktrees/scripts/worktree-cleanup.sh creating
install:   /path/to/your/repo/.worktrees/scripts/worktree-status.sh creating
install:   /path/to/your/repo/.worktrees/WORKTREE_LAYOUT.yaml creating
install:   /path/to/your/repo/.worktrees/DOCTRINE.yaml absent — skipping doctrine integration (no error)
```

Inspect the layout file and tweak if you want a different `base_path`:

```bash
$EDITOR .worktrees/WORKTREE_LAYOUT.yaml
```

## 3. Create your first worktree

```bash
.worktrees/scripts/worktree-setup.sh create track_a T-001 feature/first-task
```

Output:

```
.../track_a-T-001
worktree-setup: created /path/to/repo/../<name>-worktrees/track_a-T-001 \
  on feature/first-task for track_a/T-001 at 2026-05-02T18:00:00Z
```

Move into it and start work:

```bash
cd ../<name>-worktrees/track_a-T-001
git status
```

The branch is `feature/first-task`, the working files are isolated, and
the original repo's working directory is untouched.

## 4. See everything that's active

From the main repo (or any worktree):

```bash
.worktrees/scripts/worktree-status.sh
```

Sample output:

```
BRANCH                                        HEAD          PATH
main                                          a1b2c3d4e5    /path/to/your/repo *
feature/first-task                            a1b2c3d4e5    /path/to/<name>-worktrees/track_a-T-001

Layout: /path/to/your/repo/.worktrees/WORKTREE_LAYOUT.yaml
```

`*` marks the main checkout. Add `--json` for machine-readable output.

## 5. Tear down when the branch is merged

After your PR is merged to `origin/main`:

```bash
# Always dry-run first
.worktrees/scripts/worktree-cleanup.sh

# When you're happy with the plan
.worktrees/scripts/worktree-cleanup.sh --execute
```

Cleanup also drops stashes older than 24h (configurable via
`WORKTREE_CLEANUP_STASH_HOURS`).

## 6. Optional: gate on multi-worktree mode in CI

```bash
.worktrees/scripts/worktree-status.sh --check && echo "multi-worktree active"
```

Exits 0 iff the layout file exists and at least one non-main worktree
is registered. Useful for refusing to ship code that wasn't built in an
isolated worktree.

## What just happened

You added a layout config plus three lifecycle scripts to your repo.
The `.git/` directory now sees multiple working trees as siblings;
git itself does the isolation. No process supervisor, no daemons, no
extra dependencies.

Read [`PATTERN.md`](../PATTERN.md) for the architectural argument and
[`MIGRATION.md`](MIGRATION.md) if you have an existing project with
ad-hoc worktrees you want to standardise.
