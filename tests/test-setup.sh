#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-setup.sh — exercises the worktree-setup.sh lifecycle (create /
# list / remove) inside an isolated sandbox.
set -u

failures=0
sandbox="/tmp/wtt-test-setup-$$"
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
    echo "PASS test-setup: $name"
  else
    echo "FAIL test-setup: $name"
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
  # Bare-clone so origin/main exists for ancestry checks
  git -C "$sandbox/repo" clone --bare --quiet . "$sandbox/bare.git"
  git -C "$sandbox/repo" remote remove origin 2>/dev/null || true
  git -C "$sandbox/repo" remote add origin "$sandbox/bare.git"
  git -C "$sandbox/repo" fetch --quiet origin
}

setup_sh() {
  bash "$sandbox/repo/.worktrees/scripts/worktree-setup.sh" "$@"
}

# ----------------------------------------------------------------------------

check_create_list_remove() {
  fresh_sandbox
  local out
  out="$(cd "$sandbox/repo" && setup_sh create track_a T-001 feature/x 2>/dev/null)" || return 1
  [[ "$out" == "$sandbox/wt/track_a-T-001" ]] || return 1
  [[ -d "$sandbox/wt/track_a-T-001" ]] || return 1
  # list shows the row
  local listing
  listing="$(cd "$sandbox/repo" && setup_sh list)"
  grep -q 'feature/x' <<<"$listing" || return 1
  # remove with --force (branch not yet merged)
  (cd "$sandbox/repo" && setup_sh remove track_a T-001 --force >/dev/null 2>&1) || return 1
  [[ ! -d "$sandbox/wt/track_a-T-001" ]]
}

check_double_create_fails() {
  fresh_sandbox
  (cd "$sandbox/repo" && setup_sh create track_a T-DUP feature/dup >/dev/null 2>&1) || return 1
  local status
  set +e
  (cd "$sandbox/repo" && setup_sh create track_a T-DUP feature/dup >/dev/null 2>&1)
  status=$?
  set -e
  [[ "$status" -eq 2 ]]
}

check_dirty_remove_blocked() {
  fresh_sandbox
  (cd "$sandbox/repo" && setup_sh create track_a T-DIRTY feature/dirty >/dev/null 2>&1) || return 1
  echo "uncommitted" >"$sandbox/wt/track_a-T-DIRTY/dirty.txt"
  local status
  set +e
  (cd "$sandbox/repo" && setup_sh remove track_a T-DIRTY >/dev/null 2>&1)
  status=$?
  set -e
  [[ "$status" -eq 2 ]] || return 1
  (cd "$sandbox/repo" && setup_sh remove track_a T-DIRTY --force >/dev/null 2>&1)
}

check_invalid_track_rejected() {
  fresh_sandbox
  local status
  set +e
  (cd "$sandbox/repo" && setup_sh create track_x T-NO feature/no >/dev/null 2>&1)
  status=$?
  set -e
  [[ "$status" -eq 64 ]]
}

check_unmerged_remove_blocked_without_force() {
  fresh_sandbox
  (cd "$sandbox/repo" && setup_sh create track_a T-UNMRG feature/unmerged >/dev/null 2>&1) || return 1
  # Add a commit so the branch isn't an ancestor of origin/main
  echo "extra" >"$sandbox/wt/track_a-T-UNMRG/extra.txt"
  git -C "$sandbox/wt/track_a-T-UNMRG" add extra.txt
  git -C "$sandbox/wt/track_a-T-UNMRG" commit --quiet -m "extra"
  local status
  set +e
  (cd "$sandbox/repo" && setup_sh remove track_a T-UNMRG >/dev/null 2>&1)
  status=$?
  set -e
  [[ "$status" -eq 3 ]] || return 1
  (cd "$sandbox/repo" && setup_sh remove track_a T-UNMRG --force >/dev/null 2>&1)
}

# ----------------------------------------------------------------------------

check "create + list + remove --force"             check_create_list_remove
check "duplicate create exits 2"                   check_double_create_fails
check "remove blocked on dirty (exit 2), --force overrides" check_dirty_remove_blocked
check "invalid track name exits 64"                check_invalid_track_rejected
check "unmerged remove exits 3, --force overrides" check_unmerged_remove_blocked_without_force

exit "$failures"
