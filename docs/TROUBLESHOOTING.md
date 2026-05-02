# TROUBLESHOOTING

Common errors and how to resolve them. If your problem isn't here,
open an issue on the toolkit repo with the output of:

```bash
.worktrees/scripts/worktree-status.sh --json
git worktree list --porcelain
git --version
bash --version
```

---

## `git worktree add` says "branch is already checked out"

git refuses two worktrees on the same branch. Either:

- Pick a different branch for the new worktree, or
- Remove the existing worktree first:
  `.worktrees/scripts/worktree-setup.sh remove <track> <task-id>`.

This is by design — two worktrees on the same branch would race on
the same files.

---

## "branch '...' not merged to origin/main; use --force to override"

`worktree-setup.sh remove` refuses to delete a worktree whose branch
hasn't landed in `origin/main` yet. Either:

- Wait for the branch to merge, then re-run `remove`. The cleanup
  script (`worktree-cleanup.sh --execute`) will pick it up
  automatically once the merge happens.
- Or pass `--force` if you really want to discard the branch's work
  along with the worktree.

If `origin/main` is out of date (you haven't fetched in a while),
`git fetch origin main` and try again.

---

## "layout file not found"

`worktree-setup.sh` requires `.worktrees/WORKTREE_LAYOUT.yaml` (or the
file at `WORKTREE_LAYOUT_FILE` if you set the env var). If you haven't
run `install.sh` yet, run it first. If you have, verify the layout dir
matches:

```bash
~/.bbe-worktree-toolkit/install.sh --check
```

---

## "malformed yaml: WORKTREE_LAYOUT.yaml"

You edited the layout YAML and broke the syntax. Run `yq .
.worktrees/WORKTREE_LAYOUT.yaml` to see the parse error. If yq is not
installed, `python3 -c 'import yaml,sys;yaml.safe_load(open(sys.argv[1]))'
.worktrees/WORKTREE_LAYOUT.yaml` will work.

---

## Doctrine snippet appears twice

Should not happen — the installer greps for the marker before
appending. If it does happen, remove the duplicate manually:

```bash
.worktrees/scripts/worktree-cleanup.sh   # not related, but a good time to GC
$EDITOR .bbe-coord/DOCTRINE.yaml         # delete one of the marked blocks
```

If you can reproduce the duplicate-append, please file an issue with
the install.sh output.

---

## "command not found: yq" or "jq"

Both are optional but recommended:

- Linux (Debian/Ubuntu): `sudo apt-get install jq python3-yq`
- macOS (Homebrew): `brew install jq yq`
- Other: install via your package manager or pip (`pipx install yq`).

The lifecycle scripts will warn and degrade — most operations work
without yq/jq, but the layout-aware `list` and the central-state
seeding require yq.

---

## macOS / BSD: "date: illegal option -- d"

The lifecycle scripts use GNU `date -d` for ISO-8601 parsing. macOS
and BSD ship a different `date(1)`. v0.1.0 has a fallback for `date -j
-f` but it has not been thoroughly tested. Workarounds:

- Install GNU coreutils: `brew install coreutils` (then `gdate` is
  available; the scripts won't auto-detect that yet — rename or
  symlink to `date` in your PATH).
- Wait for v0.2.x which adds explicit macOS support.

If you hit a specific failure, please file an issue with the OS,
`date --version`, and the failing command.

---

## "unknown format" warnings from ajv

The toolkit doesn't ship JSON Schema validation, but if the host
project uses `ajv` (e.g. for state validation) you may see
"unknown format date-time" warnings. Install `ajv-formats` and pass
`-c ajv-formats` to ajv. This is unrelated to the toolkit itself.

---

## The worktree is "broken" — `git status` errors

A worktree's `.git` file points at the main repo's
`.git/worktrees/<name>/`. If you `mv` the main repo or the worktree
directory, that link breaks. Repair with:

```bash
git -C <main_repo> worktree repair
```

This rewrites the administrative pointers. If `worktree repair`
doesn't help (administrative directory itself was deleted), the
fastest recovery is to remove the broken entry and re-add:

```bash
git -C <main_repo> worktree remove --force <broken_path>
.worktrees/scripts/worktree-setup.sh create <track> <task> <branch>
```

---

## "stash drop failed" during cleanup

A stash refers to an object that's no longer reachable, or another
process holds a lock on `.git/refs/stash`. Re-run with `git stash list`
manually and drop one at a time, then re-run `worktree-cleanup.sh
--execute`.

---

## Disk fills up

Each worktree is ~1× the size of a clean checkout. Check with:

```bash
du -sh .. /<base_path>/*
```

Then run `worktree-cleanup.sh --execute` weekly, and consider
shortening the stash retention via `WORKTREE_CLEANUP_STASH_HOURS=12`.
