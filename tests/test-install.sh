#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-install.sh — installs the toolkit into an isolated sandbox repo,
# verifies all expected files are dropped, and checks idempotency.
# Includes a sub-test that exercises the doctrine-snippet integration.
set -u

failures=0
sandbox="/tmp/wtt-test-install-$$"
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
  rm -rf "$sandbox"
}
trap cleanup EXIT

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS test-install: $name"
  else
    echo "FAIL test-install: $name"
    failures=$((failures + 1))
  fi
}

fresh_sandbox() {
  rm -rf "$sandbox"
  mkdir -p "$sandbox/repo"
  cp -r "$toolkit_dir/tests/fixtures/empty-repo/." "$sandbox/repo/"
  git -C "$sandbox/repo" init --quiet --initial-branch=main
  git -C "$sandbox/repo" config user.email t@t
  git -C "$sandbox/repo" config user.name t
  git -C "$sandbox/repo" add -A
  git -C "$sandbox/repo" commit --quiet -m "fixture init"
}

# ----------------------------------------------------------------------------

check_install_creates_files() {
  fresh_sandbox
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  [[ -f "$sandbox/repo/.worktrees/WORKTREE_LAYOUT.yaml" ]] || return 1
  [[ -x "$sandbox/repo/.worktrees/scripts/worktree-setup.sh" ]] || return 1
  [[ -x "$sandbox/repo/.worktrees/scripts/worktree-cleanup.sh" ]] || return 1
  [[ -x "$sandbox/repo/.worktrees/scripts/worktree-status.sh" ]] || return 1
}

check_install_substitutes_tokens() {
  fresh_sandbox
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  # No raw {{TOKEN}} should remain anywhere in the installed files.
  if grep -rE '\{\{[A-Z_]+\}\}' "$sandbox/repo/.worktrees" >/dev/null 2>&1; then
    return 1
  fi
  # Layout file mentions the substituted toolkit version.
  grep -q '_toolkit_version: "0.1.0"' "$sandbox/repo/.worktrees/WORKTREE_LAYOUT.yaml"
}

check_install_is_idempotent() {
  fresh_sandbox
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  # Capture file hashes after first install
  local first_hash
  first_hash="$(find "$sandbox/repo/.worktrees" -type f -exec sha256sum {} + | sort)"
  # Run install again
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  local second_hash
  second_hash="$(find "$sandbox/repo/.worktrees" -type f -exec sha256sum {} + | sort)"
  [[ "$first_hash" == "$second_hash" ]]
}

check_install_check_mode() {
  fresh_sandbox
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  local out
  out="$(cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" --check 2>&1)" || return 1
  grep -q '\[installed\]' <<<"$out" || return 1
  grep -q 'WORKTREE_LAYOUT.yaml' <<<"$out"
}

check_install_uninstall_round_trip() {
  fresh_sandbox
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  [[ -f "$sandbox/repo/.worktrees/WORKTREE_LAYOUT.yaml" ]] || return 1
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" --uninstall >/dev/null) || return 1
  [[ ! -f "$sandbox/repo/.worktrees/WORKTREE_LAYOUT.yaml" ]] || return 1
  [[ ! -f "$sandbox/repo/.worktrees/scripts/worktree-setup.sh" ]] || return 1
}

check_install_custom_layout_dir() {
  fresh_sandbox
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" --layout-dir .bbe-coord >/dev/null) || return 1
  [[ -f "$sandbox/repo/.bbe-coord/WORKTREE_LAYOUT.yaml" ]] || return 1
  [[ -x "$sandbox/repo/.bbe-coord/scripts/worktree-setup.sh" ]]
}

# ----- Doctrine integration sub-test ----------------------------------------

check_doctrine_integration() {
  fresh_sandbox
  # Set up a minimal DOCTRINE.yaml plus DOCTRINE_RATIONALE.md in the
  # default layout dir BEFORE running install.
  mkdir -p "$sandbox/repo/.worktrees"
  cat >"$sandbox/repo/.worktrees/DOCTRINE.yaml" <<'YAML'
version: "1.0.0"
mandatory_for_every_sprint:
  example_existing_rule:
    rule: "exists"
    enforcement: doctrine_review_block
YAML
  cat >"$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md" <<'MD'
# DOCTRINE_RATIONALE

## example_existing_rule
A pre-existing rule.
MD

  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1

  # Snippet appended to DOCTRINE.yaml
  grep -Fq 'worktree_isolation_required:' "$sandbox/repo/.worktrees/DOCTRINE.yaml" || return 1
  grep -Fq 'bbe-worktree-toolkit T-030 BEGIN' "$sandbox/repo/.worktrees/DOCTRINE.yaml" || return 1
  grep -Fq 'bbe-worktree-toolkit T-030 END' "$sandbox/repo/.worktrees/DOCTRINE.yaml" || return 1

  # Anchor appended to DOCTRINE_RATIONALE.md
  grep -Fq '## worktree_isolation' "$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md" || return 1
  grep -Fq 'bbe-worktree-toolkit T-030 BEGIN' "$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md" || return 1

  # Pre-existing content untouched
  grep -Fq 'example_existing_rule:' "$sandbox/repo/.worktrees/DOCTRINE.yaml" || return 1
  grep -Fq '## example_existing_rule' "$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md"
}

check_doctrine_integration_idempotent() {
  fresh_sandbox
  mkdir -p "$sandbox/repo/.worktrees"
  cat >"$sandbox/repo/.worktrees/DOCTRINE.yaml" <<'YAML'
version: "1.0.0"
mandatory_for_every_sprint:
  example_existing_rule:
    rule: "exists"
YAML
  cat >"$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md" <<'MD'
# DOCTRINE_RATIONALE

## example_existing_rule
exists.
MD
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  local doctrine_hash_1 rationale_hash_1
  doctrine_hash_1="$(sha256sum "$sandbox/repo/.worktrees/DOCTRINE.yaml")"
  rationale_hash_1="$(sha256sum "$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md")"
  # Second run must not append the snippet again
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  local doctrine_hash_2 rationale_hash_2
  doctrine_hash_2="$(sha256sum "$sandbox/repo/.worktrees/DOCTRINE.yaml")"
  rationale_hash_2="$(sha256sum "$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md")"
  [[ "$doctrine_hash_1" == "$doctrine_hash_2" ]] || return 1
  [[ "$rationale_hash_1" == "$rationale_hash_2" ]] || return 1
  # Exactly one BEGIN marker per file
  local n
  n=$(grep -Fc 'bbe-worktree-toolkit T-030 BEGIN' "$sandbox/repo/.worktrees/DOCTRINE.yaml")
  [[ "$n" == "1" ]] || return 1
  n=$(grep -Fc 'bbe-worktree-toolkit T-030 BEGIN' "$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md")
  [[ "$n" == "1" ]]
}

check_doctrine_skip_when_absent() {
  fresh_sandbox
  # No DOCTRINE.yaml — install must not fail and must not create one
  local out
  out="$(cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" 2>&1)" || return 1
  grep -q 'absent — skipping doctrine integration' <<<"$out" || return 1
  [[ ! -f "$sandbox/repo/.worktrees/DOCTRINE.yaml" ]]
}

check_doctrine_uninstall_strips_marked_block() {
  fresh_sandbox
  mkdir -p "$sandbox/repo/.worktrees"
  cat >"$sandbox/repo/.worktrees/DOCTRINE.yaml" <<'YAML'
version: "1.0.0"
mandatory_for_every_sprint:
  example_existing_rule:
    rule: "exists"
YAML
  cat >"$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md" <<'MD'
# RATIONALE

## example_existing_rule
exists.
MD
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" >/dev/null) || return 1
  (cd "$sandbox/repo" && bash "$toolkit_dir/install.sh" --uninstall >/dev/null) || return 1
  # Marked block removed; pre-existing content survives
  ! grep -Fq 'worktree_isolation_required:' "$sandbox/repo/.worktrees/DOCTRINE.yaml" || return 1
  grep -Fq 'example_existing_rule:' "$sandbox/repo/.worktrees/DOCTRINE.yaml" || return 1
  ! grep -Fq '## worktree_isolation' "$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md" || return 1
  grep -Fq '## example_existing_rule' "$sandbox/repo/.worktrees/DOCTRINE_RATIONALE.md"
}

# ----------------------------------------------------------------------------

check "install drops layout + 3 scripts"           check_install_creates_files
check "install substitutes all template tokens"    check_install_substitutes_tokens
check "install is idempotent"                       check_install_is_idempotent
check "install --check reports installed state"    check_install_check_mode
check "install + uninstall round-trip"              check_install_uninstall_round_trip
check "install honors --layout-dir"                 check_install_custom_layout_dir
check "doctrine integration appends snippet"       check_doctrine_integration
check "doctrine integration is idempotent"         check_doctrine_integration_idempotent
check "install skips doctrine when absent"         check_doctrine_skip_when_absent
check "uninstall strips only marked block"         check_doctrine_uninstall_strips_marked_block

exit "$failures"
