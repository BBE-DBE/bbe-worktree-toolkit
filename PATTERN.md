# PATTERN — why per-agent git worktrees

## TL;DR

When N ≥ 2 agents share one git working directory, they fight at the
filesystem layer in ways no test suite can predict. Give each agent its
own `git worktree` and the contention disappears: the branches still
share the single git repository, but the working trees are isolated.
This document records the empirical history that led BBE-DBE to
formalise the pattern as a toolkit.

## The failure mode

Three concrete failure cases observed in the `bbe-coord` repo during
April–May 2026:

1. **`git checkout` clobbering mid-edit files.** Agent A edits
   `scripts/agent-relay.sh` on branch `T-001`, then agent B runs
   `git checkout T-002` in the same working directory. A's uncommitted
   changes are silently overwritten by the contents of `T-002`.
2. **Unconditional `rm` cleanups.** A test fixture deletes
   `.bbe-coord/SPRINT_STATE.json` in its `trap EXIT` handler, even
   when an unrelated agent created the file mid-test. The unrelated
   agent's data is silently lost.
3. **`git stash` collisions.** Agent A runs `git stash --include-untracked`
   to switch tasks; an unrelated untracked file from agent B is
   stashed, then later popped onto agent A's branch where it does
   not belong.

None of these are detectable by unit tests. They are produced by the
*scheduling* of session events, not by code paths. Reproducing one
requires recreating the timing of two parallel sessions — which is
exactly what production multi-agent workflows do every minute.

## The fix

`git worktree add ../bbe-coord-track-a builder/T-001` creates a second
checkout of the same repository at a different filesystem path. The
two worktrees share `.git/`, refs, hooks, and stash list — but they
have separate working files and separate `HEAD`. Agent A operates on
`/home/dev/projects/bbe-coord-track-a/`, agent B on
`/home/dev/projects/bbe-coord-track-b/`, and the operating system
enforces non-interference.

Tradeoffs:

- **Pro:** filesystem-level isolation; checkouts cannot stomp;
  stashes are still shared (same `.git/`) so they are still useful
  for cross-worktree handoff but not for per-agent state.
- **Pro:** existing scripts that resolve paths from `git rev-parse
  --show-toplevel` work unchanged.
- **Con:** disk space. Each worktree is roughly the size of a clean
  checkout. Mitigation: `git worktree add` only copies what's needed
  on first checkout; subsequent fetches are cheap.
- **Con:** branches are still shared. Two worktrees on the same
  branch are not allowed by git itself.
- **Con:** "central" state files (e.g. shared inbox, shared sprint
  state) need to live *outside* every worktree to remain a single
  source of truth. The toolkit's layout config exposes a
  `central_state_dir` for this — by default a sibling directory
  next to the worktree base.

## The incident that produced this toolkit

`bbe-coord` ran three sprints in parallel during a single day in
May 2026:

| Sprint | Goal |
|---|---|
| T-001 | inbox watcher + persistence |
| T-002 | PR automation |
| T-003 | git-worktree architecture |

T-001 and T-002 ran in `/home/dev/projects/bbe-coord` simultaneously.
Their agents repeatedly clobbered each other's edits to
`scripts/agent-relay.sh` and `tests/scripts/run-all.sh` — both files
were modified by all three sprints, but only the last writer "won".

T-003 was being built specifically to solve this. The agent authoring
T-003 had to use the very feature it was implementing — the final
commit on `builder/T-003-worktree-architecture` was authored from a
git worktree at `/home/dev/projects/bbe-coord-t003-wt/`, isolated from
T-001 and T-002. The PR body documented this with a single line that
became the toolkit's slogan: *"the structural fix shipped from inside
the very feature it implements"*.

Subsequent BBE-DBE sprints (T-010-PRE, T-021) used worktrees from the
start. None reported the clobbering failure mode again.

## Industry precedent (2026)

- **Augment Code** documents per-agent worktrees as the recommended
  setup for parallel agentic coding (their CLI `augment workspace add`
  wraps `git worktree add`).
- **MindStudio** uses worktrees as the default isolation primitive for
  their multi-agent workflows.
- **pnpm** ships worktree-aware caches in v10+ for parallel build
  pipelines.

The pattern is no longer experimental. This toolkit packages it as a
project-level scaffolding step so any repo can adopt it without
reinventing the layout, lifecycle scripts, or doctrine integration.

## Non-goals

- This toolkit does **not** replace `git worktree`; it wraps it with
  conventions and lifecycle scripts.
- It does **not** mediate inter-agent communication. Use a separate
  inbox / message queue / sprint-state mechanism (the toolkit's
  layout config has hooks for `central_state_dir` and
  `central_inbox_path` to point at one).
- It does **not** make `git stash` agent-aware. If you stash in one
  worktree, the stash is visible from every worktree because the
  stash list lives in `.git/`. Treat stashes as a shared resource.

## Read next

- [`README.md`](README.md) for install instructions.
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md) for a five-minute
  walkthrough.
- [`docs/MIGRATION.md`](docs/MIGRATION.md) for moving an existing
  project to the toolkit layout.
