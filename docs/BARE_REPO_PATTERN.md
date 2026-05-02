# BARE_REPO_PATTERN — sibling layout vs bare-repo layout

The bbe-worktree-toolkit ships **sibling layout** in v0.1.0: one regular
git repository alongside its worktree base directory. v0.2.0 will
support **bare-repo layout** as a first-class option. This document
explains both, when to pick which, and what the migration costs.

## The two layouts at a glance

### Sibling layout (v0.1.0)

```
~/projects/
├── myrepo/                       <- regular working tree (the "main" checkout)
│   ├── .git/                     <- shared git directory
│   │   ├── HEAD
│   │   ├── refs/
│   │   ├── objects/
│   │   └── worktrees/
│   │       ├── track_a-T-001/    <- admin metadata for worktree A
│   │       └── track_b-T-001/    <- admin metadata for worktree B
│   └── ...source files for main branch...
│
└── myrepo-worktrees/
    ├── track_a-T-001/            <- worktree on branch feature/A
    │   ├── .git                  <- POINTER FILE: gitdir: ../../myrepo/.git/worktrees/track_a-T-001
    │   └── ...source files for feature/A...
    └── track_b-T-001/            <- worktree on branch feature/B
        ├── .git                  <- POINTER FILE: gitdir: ../../myrepo/.git/worktrees/track_b-T-001
        └── ...source files for feature/B...
```

The repo at `~/projects/myrepo` is the canonical "main" checkout.
Branches that are not currently checked out anywhere live as refs
inside that repo's `.git/refs/heads/`. Each worktree carries a tiny
`.git` pointer file back to the main repo.

### Bare-repo layout (v0.2.0+)

```
~/projects/
└── myrepo/
    ├── .bare/                    <- bare git directory (NO working tree here)
    │   ├── HEAD
    │   ├── refs/
    │   ├── objects/
    │   └── worktrees/
    │       ├── main/             <- admin metadata for main worktree
    │       ├── track_a-T-001/
    │       └── track_b-T-001/
    │
    ├── .git                      <- POINTER FILE: gitdir: ./.bare
    │
    ├── main/                     <- worktree on main branch
    │   ├── .git                  <- POINTER FILE: gitdir: ../.bare/worktrees/main
    │   └── ...source files for main...
    │
    ├── track_a-T-001/            <- worktree on branch feature/A
    │   ├── .git
    │   └── ...source files...
    │
    └── track_b-T-001/
        ├── .git
        └── ...source files...
```

There is no canonical "main" checkout. Every branch is a peer
worktree of every other. The git repository itself lives in
`.bare/` as a bare clone — the directory has no associated working
tree of its own. Each worktree (including `main/`) is a sibling
directory.

## Side-by-side comparison

| Aspect | Sibling layout (v0.1.0) | Bare-repo layout (v0.2.0+) |
|---|---|---|
| **Mental model** | "main repo plus its worktrees" | "all branches are equal worktrees" |
| **`cd ~/projects/myrepo`** | drops you on the main branch | drops you in a directory listing of all worktrees |
| **`git worktree list` from any path** | works | works |
| **Removing the main checkout** | breaks worktrees (they point into its `.git/`) | safe; the main checkout is just another worktree |
| **`git checkout` on the main repo** | switches the main checkout's branch | not applicable; you `cd` into the worktree you want |
| **Disk overhead** | 1× repo + 1× per worktree | 1× bare + 1× per worktree (incl. main) |
| **IDE / editor** | most IDEs handle worktrees fine if the main repo is opened first | some IDEs treat the bare-only directory as "not a git repo"; open a worktree, not the parent |
| **Cloning fresh** | `git clone <url> myrepo` then run install.sh | `git clone --bare <url> myrepo/.bare` plus initial `git worktree add main main` |
| **Backup** | back up `myrepo/` and `myrepo-worktrees/` together | back up `myrepo/.bare/` plus, optionally, uncommitted worktree state |
| **Stash list** | shared (single `.git/refs/stash`) | shared (single `.bare/refs/stash`) |
| **Toolkit support** | first-class in v0.1.0 | scaffolded by v0.1.1 `migrate-to-bare.sh`; first-class in v0.2.0 |

## When to pick which

### Choose **sibling layout** when

- The repo is small to medium (< 500 MB working tree).
- You rarely have more than 2 concurrent worktrees.
- Your IDE struggles with bare layouts.
- You came from a "normal" git workflow and want the smallest
  cognitive shift. The main repo is still "the repo".
- You want zero-effort backup: tar.gz `myrepo/` and you have
  everything that matters.

### Choose **bare-repo layout** when

- You routinely have 3+ worktrees alive at once.
- Workflows treat branches as peers (multi-agent automation, parallel
  CI, long-lived feature branches).
- You want to delete the main checkout without breaking other
  worktrees (e.g. you only ever work in `track_a-` / `track_b-`).
- You want a cleaner top-level directory: every branch you currently
  have is one `ls` away.
- You want to fetch into the bare clone (cheap) and then re-check-out
  worktrees (expensive only when needed).

## Trade-offs in detail

### Backup strategy

Sibling layout: one rsync/tar of `~/projects/myrepo/` plus
`~/projects/myrepo-worktrees/` and you're done. The main repo's
`.git/` carries every branch and ref; the worktrees can be
recreated from refs after a restore.

Bare-repo layout: the canonical content is `~/projects/myrepo/.bare/`.
Worktrees can be recreated from refs after restore. Backups are
smaller because you can skip the per-worktree files (which are
recoverable from refs); only uncommitted-changes-per-worktree need
attention.

### IDE support

VS Code, IntelliJ, and Sublime detect a `.git` pointer file in any
worktree fine. The catch with bare-repo layout: opening the *parent*
directory (`~/projects/myrepo/`) confuses some IDEs because the
direct child `.git` is a pointer file referencing `.bare/`, but the
parent contains no source files of its own. Workaround: open a
specific worktree (`~/projects/myrepo/main/`) instead of the parent.

VS Code's "Multi-root Workspaces" feature works well with
bare-repo layout — list each worktree as a workspace folder.

### Disk space

Both layouts share the same `objects/` directory across all
worktrees, so the cost of a new worktree is roughly the size of the
checked-out files, not the full repo history. The two layouts have
the same disk profile in practice.

### `git stash`

Stash list lives in `refs/stash`, a single ref shared by all
worktrees in either layout. **You cannot have a per-worktree stash
list.** Treat stashes as a process-shared resource. The toolkit's
`migrate-to-bare.sh` preserves the stash list across migration.

### Reflog

Each worktree has its own per-worktree reflog under
`.git/worktrees/<name>/HEAD` (sibling) or `.bare/worktrees/<name>/HEAD`
(bare). The migration script preserves these by reattaching the
worktrees rather than recreating them — refs and reflog stay intact.

## Industry references (2026)

- **pnpm** (v10+) recommends bare-repo layout for monorepo CI
  pipelines that build many branches in parallel.
- **MindStudio** uses bare-repo layout as the default scaffolding for
  multi-agent workspaces in their public template.
- **dev.to** has multiple 2026 articles arguing for bare-repo layout
  as the "AI-coding-agent default", citing the same race conditions
  documented in the toolkit's [PATTERN.md](../PATTERN.md).
- **Augment Code** documents both layouts and recommends bare for
  any team that runs ≥ 3 concurrent agentic sessions per repo.

The pattern is no longer experimental. The toolkit's v0.2.0 will
make bare-repo layout a one-flag install (`install.sh --bare`),
rendering this document the historical record of the transition.

## Migration path summary

If you start on sibling layout and want to switch to bare:

1. Run `scripts/migrate-to-bare.sh` (default `--dry-run`) to see the
   plan.
2. Verify the plan, take a backup if you don't trust the script's
   built-in backup stage.
3. Run with `--execute --i-understand-the-risk` (or set
   `WTT_MIGRATE_CONFIRM=1`).
4. Verify with `worktree-status.sh` that all worktrees survived.

Detailed step-by-step lives in [`docs/MIGRATION.md`](MIGRATION.md)
under the "From Sibling to Bare-Repo" section. Rollback path is also
documented there.

## Why v0.1.1 ships only a skeleton

`migrate-to-bare.sh` in v0.1.1 is intentionally conservative:

- `--execute` is gated behind a second flag (`--i-understand-the-risk`)
  or environment variable (`WTT_MIGRATE_CONFIRM=1`). The default
  behaviour is `--dry-run` even when `--execute` is passed without
  the confirmation.
- Backup defaults to compact (`.git/` + stash bundle + uncommitted
  summary). Full tar.gz of all worktrees is opt-in with `--full-backup`.
- Stage skip flags (`--skip-backup`, `--skip-detect`, etc.) exist for
  recovery scenarios but are not advertised in `--help`.

v0.2.0 will:

- Drop the `--i-understand-the-risk` gate (the script will be
  considered production-ready).
- Add `install.sh --bare` for fresh bare-repo installs.
- Add bare-repo-aware variants of `worktree-setup.sh` and
  `worktree-cleanup.sh` so the lifecycle stays consistent across
  layouts.

For now, treat `migrate-to-bare.sh` as a documented walkthrough that
also runs end-to-end in a sandbox. Don't run it on a repo whose loss
would matter without taking your own backup first.
