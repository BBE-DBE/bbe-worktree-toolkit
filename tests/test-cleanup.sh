#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-cleanup.sh — exercises worktree-cleanup.sh dry-run / execute
# behaviour in an isolated sandbox.
set -u

failures=0
sandbox="/tmp/wtt-test-cleanup-$$"
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
  if [[ -d "$sandbox/repo/.git" ]]; then
    git -C "$sandbox/repo" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree / { print substr($0, 10) }' \
      | while read -r p; do
          if [[ -n "$p" && "$p" != "$sandbox/repo" && -d "$p" ]]; then
            git -C "$sandbox/repo" worktree remove --force "$p" 2>/dev/null || true
          fi
        done
  fi
  rm -rf "$sandbox"
}
trap cleanup EXIT

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS test-cleanup: $name"
  else
    echo "FAIL test-cleanup: $name"
    failures=$((failures + 1))
  fi
}

fresh_sandbox() {
  cleanup
  mkdir -p "$sandbox/repo"
  git -C "$sandbox/repo" init --quiet --initial-branch=main
  git -C "$sandbox/repo" config user.email t@t
  git -C "$sandbox/repo" config user.name t
  cp -r "$toolkit_dir/tests/fixtures/empty-repo/." "$sandbox/repo/"
  git -C "$sandbox/repo" add -A
  git -C "$sandbox/repo" commit --quiet -m "fixture init"
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" \
    --layout-dir .worktrees \
    --base-path "$sandbox/wt" \
    >/dev/null) || return 1
  git -C "$sandbox/repo" clone --bare --quiet . "$sandbox/bare.git"
  git -C "$sandbox/repo" remote remove origin 2>/dev/null || true
  git -C "$sandbox/repo" remote add origin "$sandbox/bare.git"
  git -C "$sandbox/repo" fetch --quiet origin
}

setup_sh() {
  bash "$sandbox/repo/.worktrees/scripts/worktree-setup.sh" "$@"
}

cleanup_sh() {
  bash "$sandbox/repo/.worktrees/scripts/worktree-cleanup.sh" "$@"
}

# ----------------------------------------------------------------------------

check_dry_run_lists_merged() {
  fresh_sandbox
  # Create a branch pointing at the same commit as main = "merged"
  git -C "$sandbox/repo" branch feature/already-merged main
  (cd "$sandbox/repo" && setup_sh create track_a T-MERGED feature/already-merged >/dev/null 2>&1) || return 1
  local out
  out="$(cd "$sandbox/repo" && cleanup_sh --dry-run 2>&1)" || return 1
  grep -q 'DRY-RUN' <<<"$out" || return 1
  grep -q 'feature/already-merged' <<<"$out" || return 1
  # Worktree must still be there
  [[ -d "$sandbox/wt/track_a-T-MERGED" ]]
}

check_execute_removes_merged() {
  fresh_sandbox
  git -C "$sandbox/repo" branch feature/m main
  (cd "$sandbox/repo" && setup_sh create track_a T-EX feature/m >/dev/null 2>&1) || return 1
  (cd "$sandbox/repo" && cleanup_sh --execute >/dev/null 2>&1) || return 1
  [[ ! -d "$sandbox/wt/track_a-T-EX" ]]
}

check_dry_run_no_changes() {
  fresh_sandbox
  git -C "$sandbox/repo" branch feature/m2 main
  (cd "$sandbox/repo" && setup_sh create track_a T-NC feature/m2 >/dev/null 2>&1) || return 1
  local before after
  before="$(git -C "$sandbox/repo" worktree list --porcelain | sha256sum)"
  (cd "$sandbox/repo" && cleanup_sh --dry-run >/dev/null 2>&1) || return 1
  after="$(git -C "$sandbox/repo" worktree list --porcelain | sha256sum)"
  [[ "$before" == "$after" ]]
}

check_unmerged_branches_skipped() {
  fresh_sandbox
  (cd "$sandbox/repo" && setup_sh create track_a T-UM feature/unmerged-2 >/dev/null 2>&1) || return 1
  echo "extra" >"$sandbox/wt/track_a-T-UM/extra.txt"
  git -C "$sandbox/wt/track_a-T-UM" add extra.txt
  git -C "$sandbox/wt/track_a-T-UM" commit --quiet -m "extra"
  local out
  out="$(cd "$sandbox/repo" && cleanup_sh --execute 2>&1)" || return 1
  # cleanup must NOT mention the unmerged branch
  ! grep -q 'feature/unmerged-2' <<<"$out" || return 1
  [[ -d "$sandbox/wt/track_a-T-UM" ]]
}

check_invalid_arg() {
  fresh_sandbox
  local status
  set +e
  (cd "$sandbox/repo" && cleanup_sh --bogus >/dev/null 2>&1)
  status=$?
  set -e
  [[ "$status" -eq 64 ]]
}

# ----------------------------------------------------------------------------

check "--dry-run lists merged worktree without acting"     check_dry_run_lists_merged
check "--execute removes merged worktree"                   check_execute_removes_merged
check "--dry-run leaves git worktree list unchanged"        check_dry_run_no_changes
check "unmerged branches are not touched"                    check_unmerged_branches_skipped
check "invalid argument exits 64"                            check_invalid_arg

exit "$failures"
