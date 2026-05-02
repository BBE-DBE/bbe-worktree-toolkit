#!/usr/bin/env bash
# worktree-cleanup.sh — find and (optionally) delete stale worktrees
# and stale stashes. Default mode is --dry-run.
#
# Installed by bbe-worktree-toolkit (https://github.com/BBE-DBE/bbe-worktree-toolkit).
# License: MIT.
set -euo pipefail

LOG_FILE="${WORKTREE_CLEANUP_LOG:-{{LAYOUT_DIR}}/tmp/worktree-cleanup.log}"
STASH_AGE_MAX_HOURS="${WORKTREE_CLEANUP_STASH_HOURS:-24}"

usage() {
  cat >&2 <<'EOF'
Usage: worktree-cleanup.sh [--dry-run | --execute]

Default is --dry-run. With --execute, removes worktrees whose branches
are merged to origin/main or no longer exist, and drops stashes older
than $WORKTREE_CLEANUP_STASH_HOURS (default 24).

Exits 0 on success, 64 on argument error.
EOF
}

die() {
  local code="$1"
  shift
  printf 'worktree-cleanup: %s\n' "$*" >&2
  exit "$code"
}

iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log() {
  if [[ "$execute" -eq 1 ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '%s %s\n' "$(iso_now)" "$*" >>"$LOG_FILE"
  fi
}

execute=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) execute=0 ;;
    --execute) execute=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || die 1 "missing required command: git"

git fetch origin main --quiet 2>/dev/null || true

mode_label() {
  if [[ "$execute" -eq 1 ]]; then printf 'EXECUTE'; else printf 'DRY-RUN'; fi
}

printf '=== worktree-cleanup [%s] @ %s ===\n' "$(mode_label)" "$(iso_now)"

stale_worktrees=()
current_path=""
current_branch=""

scan_one() {
  local path="$1"
  local branch="$2"
  if [[ -z "$path" ]]; then return; fi
  # Skip the current worktree (where this script is running from).
  if [[ "$path" == "$(git rev-parse --show-toplevel)" ]]; then
    return
  fi
  # Defensive guard for bare layout: never flag a peer worktree on
  # the default branch (main / master) as removable, even if the
  # branch passes the merged-to-origin/main check. In sibling layout
  # the main repo is always the current worktree (skipped above), so
  # this guard is a no-op there. In bare layout it prevents cleanup-
  # from-feature-worktree from removing the main/ peer.
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    return
  fi
  local reason=""
  if [[ -z "$branch" || "$branch" == "(detached)" || "$branch" == "(bare)" ]]; then
    return
  fi
  if ! git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1; then
    reason="branch '$branch' no longer exists"
  elif git merge-base --is-ancestor "$branch" origin/main 2>/dev/null; then
    reason="branch '$branch' merged to origin/main"
  fi
  if [[ -n "$reason" ]]; then
    stale_worktrees+=("$path|$branch|$reason")
  fi
}

while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      scan_one "$current_path" "$current_branch"
      current_path="${line#worktree }"
      current_branch=""
      ;;
    "branch refs/heads/"*)
      current_branch="${line#branch refs/heads/}"
      ;;
    "detached")
      current_branch="(detached)"
      ;;
    "bare")
      current_branch="(bare)"
      ;;
  esac
done < <(git worktree list --porcelain)
scan_one "$current_path" "$current_branch"

if [[ ${#stale_worktrees[@]} -eq 0 ]]; then
  printf '\nWorktrees: nothing to clean.\n'
else
  printf '\nWorktrees to clean (%d):\n' "${#stale_worktrees[@]}"
  for entry in "${stale_worktrees[@]}"; do
    IFS='|' read -r path branch reason <<<"$entry"
    printf '  %s  (%s) — %s\n' "$path" "$branch" "$reason"
    if [[ "$execute" -eq 1 ]]; then
      if git worktree remove "$path" 2>/dev/null; then
        log "removed worktree $path branch=$branch reason=\"$reason\""
        printf '    -> removed\n'
      else
        log "FAILED removed worktree $path branch=$branch"
        printf '    -> FAILED (run worktree-setup remove --force)\n'
      fi
    fi
  done
fi

now_epoch="$(date -u '+%s')"
threshold_seconds=$((STASH_AGE_MAX_HOURS * 3600))
stale_stashes=()

while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  ts="$(git log -1 --format=%ct "$ref" 2>/dev/null || true)"
  if [[ -z "$ts" ]]; then continue; fi
  age=$((now_epoch - ts))
  if [[ "$age" -gt "$threshold_seconds" ]]; then
    msg="$(git log -1 --format=%s "$ref")"
    stale_stashes+=("$ref|$age|$msg")
  fi
done < <(git stash list --format='%gd' 2>/dev/null || true)

if [[ ${#stale_stashes[@]} -eq 0 ]]; then
  printf '\nStashes: none older than %s hours.\n' "$STASH_AGE_MAX_HOURS"
else
  printf '\nStashes to drop (%d, older than %sh):\n' "${#stale_stashes[@]}" "$STASH_AGE_MAX_HOURS"
  for entry in "${stale_stashes[@]}"; do
    IFS='|' read -r ref age msg <<<"$entry"
    hours=$((age / 3600))
    printf '  %s  (%dh)  %s\n' "$ref" "$hours" "$msg"
  done
  if [[ "$execute" -eq 1 ]]; then
    indices=()
    for entry in "${stale_stashes[@]}"; do
      IFS='|' read -r ref _ _ <<<"$entry"
      idx="${ref#stash@\{}"
      idx="${idx%\}}"
      indices+=("$idx")
    done
    mapfile -t sorted < <(printf '%s\n' "${indices[@]}" | sort -rn)
    for idx in "${sorted[@]}"; do
      ref="stash@{$idx}"
      if git stash drop "$ref" >/dev/null 2>&1; then
        log "dropped $ref"
        printf '  -> dropped %s\n' "$ref"
      else
        log "FAILED drop $ref"
        printf '  -> FAILED %s\n' "$ref"
      fi
    done
  fi
fi

printf '\n=== %s ===\n' "$(mode_label)"
