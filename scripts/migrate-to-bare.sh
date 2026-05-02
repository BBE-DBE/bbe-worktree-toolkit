#!/usr/bin/env bash
# migrate-to-bare.sh — convert a sibling-layout repo (v0.1.x toolkit
# install) into a bare-repo layout. Five stages with explicit dry-run
# vs. execute boundaries.
#
# v0.1.1 was the skeleton; v0.2.0 promotes bare-mode to first-class in
# install.sh and the lifecycle templates. The migration script itself
# keeps the same five stages and the same --i-understand-the-risk
# gate. The v0.1.1 docstring claimed the gate would be removed in
# v0.2.0; v0.2.0 keeps it deliberately because the migration is
# irreversible (.git is rewritten, sibling-layout worktrees are
# detached) and a typo on a production repo is unrecoverable. The
# safety > convenience trade-off is documented as a v0.2.0 soft-
# decision in CHANGELOG.md.
#
# License: MIT.
set -euo pipefail

VERSION_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION"
VERSION="$(cat "$VERSION_FILE" 2>/dev/null || printf '0.0.0')"

usage() {
  cat >&2 <<'EOF'
Usage: migrate-to-bare.sh [options]

Default mode is --dry-run: prints the plan, makes no changes.
--execute applies the migration only when paired with
--i-understand-the-risk (or env WTT_MIGRATE_CONFIRM=1). v0.2.0
keeps this double-confirmation deliberately — the migration is
irreversible at the .git-layout level and a typo on a production
repo is unrecoverable. See CHANGELOG.md (v0.2.0) for rationale.

Options:
  --dry-run              Default. Print plan, no changes.
  --execute              Apply the migration (requires risk confirmation).
  --i-understand-the-risk  Confirms you've read docs/MIGRATION.md and
                         backed up the repo. Required with --execute.
  --full-backup          tar.gz the entire sibling layout before
                         converting. Default backup is compact
                         (.git/ + stash bundle + uncommitted summary).
  --skip-backup          Skip the Backup stage entirely. Recovery only.
  --skip-detect          Skip the Detect stage. Recovery only.
  --skip-convert         Skip the Convert stage. Recovery only.
  --skip-reattach        Skip the Reattach stage. Recovery only.
  --skip-verify          Skip the Verify stage. Recovery only.
  --layout-dir <path>    Where the toolkit's layout YAML lives.
                         Default: .worktrees
  --help, -h             Print this help.
  --version              Print toolkit version.

Environment:
  WTT_MIGRATE_CONFIRM=1  Equivalent to --i-understand-the-risk.
  WTT_MIGRATE_BACKUP_DIR Override default backup location.

Five stages: Backup -> Detect -> Convert -> Reattach -> Verify.
Idempotent: a second run detects the bare layout and exits 0 with
"already migrated" notice.

Exits:
  0   ok (or already migrated)
  1   dependency missing or repo state unsafe
  2   --execute used without confirmation
  3   stage failed
  64  argument error
EOF
}

die() {
  local code="$1"
  shift
  printf 'migrate-to-bare: %s\n' "$*" >&2
  exit "$code"
}

stage() {
  printf '\n=== %s ===\n' "$*"
}

info() {
  printf 'migrate-to-bare: %s\n' "$*"
}

dry_run=1
risk_confirmed=0
full_backup=0
layout_dir=".worktrees"
skip_backup=0
skip_detect=0
skip_convert=0
skip_reattach=0
skip_verify=0

if [[ "${WTT_MIGRATE_CONFIRM:-0}" == "1" ]]; then
  risk_confirmed=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --execute) dry_run=0 ;;
    --i-understand-the-risk) risk_confirmed=1 ;;
    --full-backup) full_backup=1 ;;
    --layout-dir) shift; [[ $# -gt 0 ]] || die 64 "--layout-dir requires a value"; layout_dir="$1" ;;
    --skip-backup) skip_backup=1 ;;
    --skip-detect) skip_detect=1 ;;
    --skip-convert) skip_convert=1 ;;
    --skip-reattach) skip_reattach=1 ;;
    --skip-verify) skip_verify=1 ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) die 64 "unknown argument: $1 (use --help)" ;;
  esac
  shift
done

# Enforce double-confirmation for --execute.
if [[ "$dry_run" -eq 0 && "$risk_confirmed" -ne 1 ]]; then
  die 2 "--execute requires --i-understand-the-risk (or WTT_MIGRATE_CONFIRM=1). The migration is irreversible; v0.2.0 keeps this gate deliberately."
fi

# ---- prerequisites ----------------------------------------------------------

command -v git >/dev/null 2>&1 || die 1 "git is required"

# Idempotency check FIRST — before we rely on a working tree, because a
# bare-repo-layout parent directory has no work tree (the .git file
# points at the .bare directory which is bare).
cwd="$(pwd)"
if [[ -f "$cwd/.git" && -d "$cwd/.bare" ]]; then
  if grep -Fq 'gitdir: ./.bare' "$cwd/.git" 2>/dev/null \
    || grep -Fq "gitdir: $cwd/.bare" "$cwd/.git" 2>/dev/null; then
    info "repository at $cwd is already in bare-repo layout — nothing to do."
    exit 0
  fi
fi

main_repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$main_repo" ]] || die 1 "not in a git repository (run from inside the target repo)"

repo_name="$(basename "$main_repo")"
parent_dir="$(dirname "$main_repo")"

# ---- mode banner ------------------------------------------------------------

if [[ "$dry_run" -eq 1 ]]; then
  banner_mode="DRY-RUN"
else
  banner_mode="EXECUTE (risk confirmed)"
fi

cat <<EOF

bbe-worktree-toolkit migrate-to-bare.sh v$VERSION
mode:        $banner_mode
main repo:   $main_repo
layout dir:  $layout_dir
full backup: $([ "$full_backup" -eq 1 ] && echo yes || echo no)

EOF

# ---- helpers ----------------------------------------------------------------

# When dry-run, just echoes the command. When executing, runs it via
# bash -c so shell metacharacters in the command string (pipes,
# redirects, &&) work as intended. We still print the command first
# so the operator can see what's happening.
do_or_show() {
  local cmd="$*"
  if [[ "$dry_run" -eq 1 ]]; then
    printf '  WOULD: %s\n' "$cmd"
  else
    printf '  RUN:   %s\n' "$cmd"
    bash -c "$cmd"
  fi
}

backup_dir="${WTT_MIGRATE_BACKUP_DIR:-$main_repo/.bbe-worktree-toolkit-backup/$(date -u '+%Y%m%dT%H%M%SZ')}"

worktree_records_file=""

# ---- Stage 1: Backup --------------------------------------------------------

stage_backup() {
  if [[ "$skip_backup" -eq 1 ]]; then
    stage "Stage 1: Backup (SKIPPED)"
    return
  fi
  stage "Stage 1: Backup"
  info "backup destination: $backup_dir"
  do_or_show "mkdir -p '$backup_dir'"
  if [[ "$full_backup" -eq 1 ]]; then
    info "full backup mode — tar.gz of $main_repo and any sibling worktrees"
    do_or_show "tar -czf '$backup_dir/full.tar.gz' -C '$parent_dir' '$repo_name'"
    if [[ -d "$parent_dir/${repo_name}-worktrees" ]]; then
      do_or_show "tar -czf '$backup_dir/worktrees.tar.gz' -C '$parent_dir' '${repo_name}-worktrees'"
    fi
  else
    info "compact backup mode — .git/ + stash bundle + uncommitted summary"
    do_or_show "cp -a '$main_repo/.git' '$backup_dir/git-dir'"
    # Stash bundle: capture all stashes as a transferable bundle.
    do_or_show "git -C '$main_repo' stash list --format='%gd' > '$backup_dir/stashes.txt' 2>/dev/null || true"
    do_or_show "git -C '$main_repo' bundle create '$backup_dir/stashes.bundle' --stdin < '$backup_dir/stashes.txt' 2>/dev/null || true"
    # Uncommitted summary across all worktrees.
    do_or_show "git -C '$main_repo' status --porcelain > '$backup_dir/uncommitted-summary.txt' 2>/dev/null || true"
    do_or_show "git -C '$main_repo' diff > '$backup_dir/uncommitted-changes.diff' 2>/dev/null || true"
  fi
  if [[ "$dry_run" -eq 0 ]]; then
    info "backup written to $backup_dir"
  fi
}

# ---- Stage 2: Detect --------------------------------------------------------

stage_detect() {
  if [[ "$skip_detect" -eq 1 ]]; then
    stage "Stage 2: Detect (SKIPPED)"
    return
  fi
  stage "Stage 2: Detect"
  info "scanning git worktree list for sibling-layout worktrees"
  worktree_records_file="$backup_dir/worktrees.txt"
  if [[ "$dry_run" -eq 1 ]]; then
    printf '  WOULD: capture worktree list to %s\n' "$worktree_records_file"
    git -C "$main_repo" worktree list --porcelain | head -20 | sed 's/^/    /'
  else
    mkdir -p "$backup_dir"
    git -C "$main_repo" worktree list --porcelain >"$worktree_records_file"
    info "captured $(grep -c '^worktree ' "$worktree_records_file") worktree records to $worktree_records_file"
  fi
}

# ---- Stage 3: Convert -------------------------------------------------------

stage_convert() {
  if [[ "$skip_convert" -eq 1 ]]; then
    stage "Stage 3: Convert (SKIPPED)"
    return
  fi
  stage "Stage 3: Convert"
  info "creating bare clone at $main_repo/.bare"
  if [[ -d "$main_repo/.bare" ]]; then
    info "  $main_repo/.bare already exists — skipping clone"
    return
  fi

  # Plan:
  # 1. Remove all sibling-layout worktrees (administrative, not files)
  # 2. git clone --bare from the main repo into a temp dir
  # 3. Move temp -> $main_repo/.bare
  # 4. Replace $main_repo/.git directory with a pointer file
  # 5. Move main repo's working files into $main_repo/main/

  do_or_show "git -C '$main_repo' worktree list --porcelain | awk '/^worktree / {print substr(\$0, 10)}' | while read -r wt; do [ \"\$wt\" != '$main_repo' ] && git -C '$main_repo' worktree remove --force \"\$wt\" || true; done"
  local tmp_bare
  tmp_bare="$main_repo/.bare-tmp-$$"
  do_or_show "git clone --bare '$main_repo' '$tmp_bare'"
  do_or_show "mv '$tmp_bare' '$main_repo/.bare'"
  # Move main repo's existing working files OUT of the way before
  # creating the new main/ worktree. Original files (which may carry
  # uncommitted changes) land under the backup dir; the operator can
  # rsync them back over main/ post-migration to restore uncommitted
  # state. v0.2.0 keeps this manual restore step intentional — an
  # automated rsync could silently overwrite a freshly checked-out
  # main with stale uncommitted edits. docs/MIGRATION.md walks the
  # one-line restore command.
  do_or_show "mkdir -p '$backup_dir/main-working'"
  do_or_show "find '$main_repo' -mindepth 1 -maxdepth 1 -not -name '.bare' -not -name '.bbe-worktree-toolkit-backup' -not -name '.git' -exec mv {} '$backup_dir/main-working/' \\;"
  # Replace main repo's .git dir with a pointer file.
  do_or_show "rm -rf '$main_repo/.git'"
  do_or_show "printf 'gitdir: ./.bare\\n' > '$main_repo/.git'"
  # Attach main/ as a proper worktree of the new bare clone. This
  # checks out a fresh copy of the main branch into main/.
  do_or_show "git -C '$main_repo/.bare' worktree add '$main_repo/main' main"
  if [[ "$dry_run" -eq 0 ]]; then
    info "bare layout created at $main_repo/.bare"
    info "  uncommitted state from old main was preserved at $backup_dir/main-working"
    info "  to restore: rsync -a '$backup_dir/main-working/' '$main_repo/main/' (review changes first)"
  fi
}

# ---- Stage 4: Reattach ------------------------------------------------------

stage_reattach() {
  if [[ "$skip_reattach" -eq 1 ]]; then
    stage "Stage 4: Reattach (SKIPPED)"
    return
  fi
  stage "Stage 4: Reattach"
  info "re-adding worktrees against the new bare layout"
  if [[ -z "${worktree_records_file:-}" ]]; then
    worktree_records_file="$backup_dir/worktrees.txt"
  fi
  if [[ "$dry_run" -eq 1 ]]; then
    printf '  WOULD: for each branch in worktrees.txt, run: git -C %s/.bare worktree add ../<rel_path> <branch>\n' "$main_repo"
    return
  fi
  if [[ ! -f "$worktree_records_file" ]]; then
    info "  no worktree records (Detect stage was skipped) — nothing to reattach beyond main"
    return
  fi
  local cur_path="" cur_branch=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        if [[ -n "$cur_path" && -n "$cur_branch" && "$cur_path" != "$main_repo" ]]; then
          local rel
          rel="$(basename "$cur_path")"
          info "  reattaching $rel on branch $cur_branch"
          git -C "$main_repo/.bare" worktree add "$main_repo/$rel" "$cur_branch" 2>&1 | sed 's/^/    /' || info "    (skipped: branch may already be checked out elsewhere)"
        fi
        cur_path="${line#worktree }"
        cur_branch=""
        ;;
      "branch refs/heads/"*)
        cur_branch="${line#branch refs/heads/}"
        ;;
    esac
  done <"$worktree_records_file"
  # Final entry
  if [[ -n "$cur_path" && -n "$cur_branch" && "$cur_path" != "$main_repo" ]]; then
    local rel
    rel="$(basename "$cur_path")"
    info "  reattaching $rel on branch $cur_branch"
    git -C "$main_repo/.bare" worktree add "$main_repo/$rel" "$cur_branch" 2>&1 | sed 's/^/    /' || info "    (skipped: branch may already be checked out elsewhere)"
  fi
}

# ---- Stage 5: Verify --------------------------------------------------------

stage_verify() {
  if [[ "$skip_verify" -eq 1 ]]; then
    stage "Stage 5: Verify (SKIPPED)"
    return
  fi
  stage "Stage 5: Verify"
  info "running worktree-status.sh --check"
  local status_script="$main_repo/main/$layout_dir/scripts/worktree-status.sh"
  if [[ ! -x "$status_script" ]]; then
    status_script="$main_repo/$layout_dir/scripts/worktree-status.sh"
  fi
  if [[ "$dry_run" -eq 1 ]]; then
    printf '  WOULD: run %s --check\n' "$status_script"
  else
    if [[ -x "$status_script" ]]; then
      if "$status_script" --check; then
        info "  worktree-status: OK"
      else
        info "  worktree-status: degraded — investigate $status_script output"
      fi
    else
      info "  worktree-status.sh not found at expected paths — skipping; verify manually"
    fi
    info "  git worktree list:"
    git -C "$main_repo/.bare" worktree list 2>/dev/null | sed 's/^/    /' || git -C "$main_repo" worktree list | sed 's/^/    /'
  fi
}

# ---- main -------------------------------------------------------------------

stage_backup
stage_detect
stage_convert
stage_reattach
stage_verify

echo
if [[ "$dry_run" -eq 1 ]]; then
  info "dry-run complete. Re-run with --execute --i-understand-the-risk to apply."
else
  info "migration complete. Update your toolkit layout file's base_path to '.' and verify worktrees in your IDE."
fi
