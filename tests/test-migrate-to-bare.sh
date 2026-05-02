#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-migrate-to-bare.sh — sandbox lifecycle tests for the
# sibling -> bare-repo migration script. Builds a sibling layout
# under /tmp/wtt-migrate-test-$$/ and exercises dry-run, full
# --execute, idempotency, and recovery via stage-skip flags.
set -u

failures=0
sandbox="/tmp/wtt-migrate-test-$$"
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
migrate_script="$toolkit_dir/scripts/migrate-to-bare.sh"

cleanup() {
  if [[ -d "$sandbox" ]]; then
    # Best-effort: drop any worktrees registered under sandbox so
    # /tmp removal doesn't leave dangling git refs.
    if [[ -d "$sandbox/repo/.git" || -d "$sandbox/repo/.bare" ]]; then
      git -C "$sandbox/repo" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree / { print substr($0, 10) }' \
        | while read -r p; do
            if [[ -n "$p" && "$p" != "$sandbox/repo" && -d "$p" ]]; then
              git -C "$sandbox/repo" worktree remove --force "$p" 2>/dev/null || true
            fi
          done
    fi
    rm -rf "$sandbox"
  fi
}
trap cleanup EXIT

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS test-migrate-to-bare: $name"
  else
    echo "FAIL test-migrate-to-bare: $name"
    failures=$((failures + 1))
  fi
}

# Build a sibling-layout repo under $sandbox/repo with the toolkit
# installed and at least one extra worktree registered.
build_sibling_layout() {
  cleanup
  mkdir -p "$sandbox/repo"
  git -C "$sandbox/repo" init --quiet --initial-branch=main
  git -C "$sandbox/repo" config user.email t@t
  git -C "$sandbox/repo" config user.name t
  echo "init" >"$sandbox/repo/README.md"
  git -C "$sandbox/repo" add README.md
  git -C "$sandbox/repo" commit --quiet -m "init"
  # Install the toolkit so worktree-status.sh exists for verify-stage tests.
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" \
    --layout-dir .worktrees \
    --base-path "$sandbox/wt" \
    >/dev/null) || return 1
  # Add one extra worktree so Detect/Reattach has something to do.
  git -C "$sandbox/repo" branch feature/x main
  bash "$sandbox/repo/.worktrees/scripts/worktree-setup.sh" \
    create track_a T-FEAT feature/x >/dev/null 2>&1 \
    || (cd "$sandbox/repo" && bash .worktrees/scripts/worktree-setup.sh create track_a T-FEAT feature/x >/dev/null 2>&1) \
    || return 1
}

# ----------------------------------------------------------------------------

check_dry_run_default() {
  build_sibling_layout || return 1
  local out
  out="$(cd "$sandbox/repo" && bash "$migrate_script" 2>&1)" || return 1
  grep -q 'mode:.*DRY-RUN' <<<"$out" || return 1
  grep -q 'Stage 1: Backup' <<<"$out" || return 1
  grep -q 'Stage 5: Verify' <<<"$out" || return 1
  grep -q 'WOULD:' <<<"$out" || return 1
  # No bare layout was created
  [[ ! -d "$sandbox/repo/.bare" ]] || return 1
  # No backup was created
  [[ ! -d "$sandbox/repo/.bbe-worktree-toolkit-backup" ]]
}

check_execute_without_confirmation_refused() {
  build_sibling_layout || return 1
  local status
  set +e
  (cd "$sandbox/repo" && bash "$migrate_script" --execute 2>/dev/null)
  status=$?
  set -e
  [[ "$status" -eq 2 ]]
}

check_execute_with_confirmation_creates_bare_layout() {
  build_sibling_layout || return 1
  (cd "$sandbox/repo" && bash "$migrate_script" --execute --i-understand-the-risk >/tmp/wtt-migrate-out.log 2>&1) || {
    cat /tmp/wtt-migrate-out.log >&2
    return 1
  }
  [[ -d "$sandbox/repo/.bare" ]] || return 1
  [[ -f "$sandbox/repo/.git" ]] || return 1
  grep -Fq 'gitdir: ./.bare' "$sandbox/repo/.git" || return 1
  # Backup directory was created with our compact artefacts
  [[ -d "$sandbox/repo/.bbe-worktree-toolkit-backup" ]] || return 1
  find "$sandbox/repo/.bbe-worktree-toolkit-backup" -name 'git-dir' -type d | head -1 | grep -q git-dir || return 1
  # main/ exists with the README
  [[ -f "$sandbox/repo/main/README.md" ]] || return 1
  # The feature/x branch reattached into a worktree under the bare layout
  git -C "$sandbox/repo/.bare" worktree list --porcelain 2>/dev/null | grep -q 'feature/x'
}

check_idempotent_after_migration() {
  build_sibling_layout || return 1
  (cd "$sandbox/repo" && bash "$migrate_script" --execute --i-understand-the-risk >/dev/null 2>&1) || return 1
  # Second run must detect the already-migrated layout and exit 0.
  local out
  out="$(cd "$sandbox/repo" && bash "$migrate_script" 2>&1)" || return 1
  grep -q 'already in bare-repo layout' <<<"$out"
}

check_skip_backup_flag() {
  build_sibling_layout || return 1
  local out
  out="$(cd "$sandbox/repo" && bash "$migrate_script" --skip-backup 2>&1)" || return 1
  grep -q 'Stage 1: Backup (SKIPPED)' <<<"$out" || return 1
  grep -q 'Stage 2: Detect' <<<"$out"
}

check_version_flag() {
  local v
  v="$(bash "$migrate_script" --version)"
  [[ "$v" == "0.1.1" ]]
}

# ----------------------------------------------------------------------------

check "default mode is dry-run, prints all 5 stages"      check_dry_run_default
check "--execute without confirmation exits 2"             check_execute_without_confirmation_refused
check "--execute --i-understand-the-risk creates .bare/"   check_execute_with_confirmation_creates_bare_layout
check "second run detects already-migrated and exits 0"    check_idempotent_after_migration
check "--skip-backup honors stage-skip flags"              check_skip_backup_flag
check "--version reports 0.1.1"                            check_version_flag

exit "$failures"
