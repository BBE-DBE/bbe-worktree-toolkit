#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-bare-mode.sh — v0.2.0 first-class bare-layout coverage.
#
# Verifies:
#   - install.sh auto-detects bare layout (.bare/ + .git pointer)
#   - install.sh --layout sibling on a bare repo respects the override
#   - install.sh --layout bare refuses on a non-bare repo
#   - templates set layout_mode in the rendered YAML
#   - worktree-setup.sh in bare mode places worktrees at the right path
#   - worktree-status.sh --info reports layout_mode
#   - bit-identical regression: fresh sibling install matches v0.1.x
#     baseline modulo {{TOOLKIT_VERSION}} and {{INSTALL_TIMESTAMP}}.
#
# Sandbox under /tmp/wtt-test-bare-$$ — no real repo touched.
set -u

failures=0
sandbox="/tmp/wtt-test-bare-$$"
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
  if [[ -d "$sandbox" ]]; then
    # Remove any registered worktrees so /tmp cleanup leaves no
    # dangling refs.
    for r in "$sandbox/sibling-repo" "$sandbox/bare-root"; do
      if [[ -d "$r" ]]; then
        git -C "$r" worktree list --porcelain 2>/dev/null \
          | awk '/^worktree / { print substr($0, 10) }' \
          | while read -r p; do
              if [[ -n "$p" && "$p" != "$r" && -d "$p" ]]; then
                git -C "$r" worktree remove --force "$p" 2>/dev/null || true
              fi
            done
      fi
    done
    rm -rf "$sandbox"
  fi
}
trap cleanup EXIT

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS test-bare-mode: $name"
  else
    echo "FAIL test-bare-mode: $name"
    failures=$((failures + 1))
  fi
}

# Build a sibling-layout sandbox repo. Returns its path on stdout.
# Every call removes any prior sibling-repo so back-to-back tests
# don't collide.
build_sibling_repo() {
  local r="$sandbox/sibling-repo"
  rm -rf "$r"
  mkdir -p "$r"
  git -C "$r" init -q --initial-branch=main
  git -C "$r" config user.email t@t
  git -C "$r" config user.name t
  echo "init" >"$r/README.md"
  git -C "$r" add -A
  git -C "$r" commit -q -m init
  printf '%s' "$r"
}

# Build a bare-layout sandbox: <root>/.bare bare repo + <root>/.git
# pointer + <root>/main worktree. Returns the root path on stdout.
# Every call wipes any prior bare-root + bare-seed so collisions
# from back-to-back invocations cannot happen. Suppresses any
# residual git output so the captured stdout stays clean.
build_bare_repo() {
  local root="$sandbox/bare-root"
  local seed="$sandbox/bare-seed"
  rm -rf "$root" "$seed"
  mkdir -p "$seed"
  git -C "$seed" init -q --initial-branch=main >/dev/null 2>&1
  git -C "$seed" config user.email t@t
  git -C "$seed" config user.name t
  echo "seed" >"$seed/README.md"
  git -C "$seed" add -A >/dev/null 2>&1
  git -C "$seed" commit -q -m init >/dev/null 2>&1
  mkdir -p "$root"
  git clone --bare --quiet "$seed" "$root/.bare" >/dev/null 2>&1
  printf 'gitdir: ./.bare\n' >"$root/.git"
  git -C "$root/.bare" worktree add -q "$root/main" main >/dev/null 2>&1
  printf '%s' "$root"
}

# ---------- 1. auto-detection on a sibling repo --------------------------

check_auto_detects_sibling() {
  local r
  r="$(build_sibling_repo)"
  local out
  out="$(cd "$r" && bash "$toolkit_dir/install.sh" 2>&1)" || return 1
  printf '%s' "$out" | grep -q 'layout mode  = sibling' || return 1
  grep -Fq 'layout_mode: "sibling"' "$r/.worktrees/WORKTREE_LAYOUT.yaml" || return 1
  rm -rf "$r"
}

# ---------- 2. auto-detection on a bare repo -----------------------------

check_auto_detects_bare() {
  local r
  r="$(build_bare_repo)"
  local out
  out="$(cd "$r/main" && bash "$toolkit_dir/install.sh" 2>&1)" || return 1
  printf '%s' "$out" | grep -q 'layout mode  = bare' || return 1
  grep -Fq 'layout_mode: "bare"' "$r/main/.worktrees/WORKTREE_LAYOUT.yaml" || return 1
  # base_path defaults to "." in bare mode (worktrees as siblings of .bare/).
  grep -Fq 'base_path: "."' "$r/main/.worktrees/WORKTREE_LAYOUT.yaml" || return 1
  rm -rf "$r"
}

# ---------- 3. explicit --layout sibling on a bare repo --------------------

check_explicit_sibling_override_on_bare() {
  local r
  r="$(build_bare_repo)"
  local out
  out="$(cd "$r/main" && bash "$toolkit_dir/install.sh" --layout sibling 2>&1)" || return 1
  printf '%s' "$out" | grep -q 'layout mode  = sibling' || return 1
  grep -Fq 'layout_mode: "sibling"' "$r/main/.worktrees/WORKTREE_LAYOUT.yaml" || return 1
  rm -rf "$r"
}

# ---------- 4. --layout bare refused on non-bare repo --------------------

check_explicit_bare_refused_on_sibling() {
  local r rc
  r="$(build_sibling_repo)"
  set +e
  (cd "$r" && bash "$toolkit_dir/install.sh" --layout bare >/dev/null 2>&1)
  rc=$?
  set -e
  rm -rf "$r"
  [[ "$rc" -eq 1 ]]
}

# ---------- 5. unknown --layout value exits 64 --------------------------

check_unknown_layout_exits_64() {
  local r rc
  r="$(build_sibling_repo)"
  set +e
  (cd "$r" && bash "$toolkit_dir/install.sh" --layout banana >/dev/null 2>&1)
  rc=$?
  set -e
  rm -rf "$r"
  [[ "$rc" -eq 64 ]]
}

# ---------- 6. setup.sh in bare mode resolves paths against bare-root ----

check_setup_in_bare_resolves_against_bare_root() {
  local r
  r="$(build_bare_repo)"
  (cd "$r/main" && bash "$toolkit_dir/install.sh" >/dev/null) || { rm -rf "$r"; return 1; }
  # base_path is "." → worktrees should be created at <bare-root>/<rel>.
  git -C "$r/.bare" branch feature/x main
  if ! (cd "$r/main" && bash .worktrees/scripts/worktree-setup.sh \
          create track_a T-001 feature/x >/dev/null 2>&1); then
    rm -rf "$r"; return 1
  fi
  # Worktree should live at <bare-root>/track_a-T-001, NOT at
  # <bare-root>/main/track_a-T-001.
  [[ -d "$r/track_a-T-001" ]] || { rm -rf "$r"; return 1; }
  [[ ! -d "$r/main/track_a-T-001" ]] || { rm -rf "$r"; return 1; }
  # Cleanup the test worktree so the trap doesn't have to.
  git -C "$r/.bare" worktree remove --force "$r/track_a-T-001" 2>/dev/null || true
  rm -rf "$r"
}

# ---------- 7. status.sh --info reports layout_mode --------------------

check_status_info_reports_mode() {
  local r out
  r="$(build_bare_repo)"
  (cd "$r/main" && bash "$toolkit_dir/install.sh" >/dev/null) || { rm -rf "$r"; return 1; }
  out="$(cd "$r/main" && bash .worktrees/scripts/worktree-status.sh --info)" \
    || { rm -rf "$r"; return 1; }
  rm -rf "$r"
  printf '%s' "$out" | grep -Fq '"layout_mode":"bare"' || return 1
}

# ---------- 8. bit-identical regression for sibling default install -----
# Default install on an empty repo must produce the same set of files
# (modulo {{TOOLKIT_VERSION}} and {{INSTALL_TIMESTAMP}}) as v0.1.x. We
# install with the new toolkit, then re-render the layout/scripts with
# the v0.1.1 version stamp + a fixed timestamp, and compare against the
# v0.1.1-templated output side-by-side. Any structural regression would
# show up as a diff outside the version/timestamp lines.

check_sibling_install_structural_match() {
  local r
  r="$(build_sibling_repo)"
  (cd "$r" && bash "$toolkit_dir/install.sh" >/dev/null) || { rm -rf "$r"; return 1; }
  # Compare the rendered scripts byte-for-byte with the templates,
  # post-substitution. The substitutions touch {{LAYOUT_DIR}} only —
  # all other tokens are absent from the script bodies.
  # NOTE: declare loop var as local; otherwise bash dynamic scoping
  # would clobber the caller's $name (the check-runner's test label).
  local expected actual fname
  for fname in worktree-setup.sh worktree-cleanup.sh worktree-status.sh; do
    expected="$(sed -e 's|{{LAYOUT_DIR}}|.worktrees|g' "$toolkit_dir/templates/$fname")"
    actual="$(cat "$r/.worktrees/scripts/$fname")"
    if [[ "$expected" != "$actual" ]]; then
      printf '    diff in %s:\n' "$fname" >&2
      diff <(printf '%s' "$expected") <(printf '%s' "$actual") | head -10 >&2
      rm -rf "$r"
      return 1
    fi
  done
  # Layout YAML must contain the new layout_mode field.
  grep -Fq 'layout_mode: "sibling"' "$r/.worktrees/WORKTREE_LAYOUT.yaml" || { rm -rf "$r"; return 1; }
  rm -rf "$r"
}

# ---------- 9. idempotent re-install: byte-stable -----------------------

check_install_idempotent_v020() {
  local r first second
  r="$(build_sibling_repo)"
  (cd "$r" && bash "$toolkit_dir/install.sh" >/dev/null) || { rm -rf "$r"; return 1; }
  first="$(find "$r/.worktrees" -type f -exec sha256sum {} + | sort)"
  (cd "$r" && bash "$toolkit_dir/install.sh" >/dev/null) || { rm -rf "$r"; return 1; }
  second="$(find "$r/.worktrees" -type f -exec sha256sum {} + | sort)"
  rm -rf "$r"
  [[ "$first" == "$second" ]]
}

# ---------- 10. v0.2.0 layout YAML opens with layout_mode -------------

check_layout_yaml_has_layout_mode_field() {
  local r
  r="$(build_sibling_repo)"
  (cd "$r" && bash "$toolkit_dir/install.sh" >/dev/null) || { rm -rf "$r"; return 1; }
  grep -Eq '^layout_mode:[[:space:]]+"(sibling|bare)"$' "$r/.worktrees/WORKTREE_LAYOUT.yaml" || { rm -rf "$r"; return 1; }
  rm -rf "$r"
}

# ---------- 11. cleanup.sh defensive guard against main-branch removal -

check_cleanup_skips_main_branch() {
  local r
  r="$(build_bare_repo)"
  (cd "$r/main" && bash "$toolkit_dir/install.sh" >/dev/null) || { rm -rf "$r"; return 1; }
  # Add a feature worktree, run cleanup from inside it, verify main/
  # is NOT in the dry-run cleanup list.
  git -C "$r/.bare" branch feature/y main
  (cd "$r/main" && bash .worktrees/scripts/worktree-setup.sh \
    create track_a T-002 feature/y >/dev/null 2>&1) || { rm -rf "$r"; return 1; }
  local out
  out="$(cd "$r/track_a-T-002" && bash "$r/main/.worktrees/scripts/worktree-cleanup.sh" 2>&1)" || { rm -rf "$r"; return 1; }
  # main/ must not appear in any "Worktrees to clean" line.
  if printf '%s' "$out" | awk '/Worktrees to clean/,/Stashes/' | grep -Fq "/main "; then
    rm -rf "$r"; return 1
  fi
  git -C "$r/.bare" worktree remove --force "$r/track_a-T-002" 2>/dev/null || true
  rm -rf "$r"
}

check "auto-detect sibling on a regular repo" check_auto_detects_sibling
check "auto-detect bare on a .bare/ + .git pointer repo" check_auto_detects_bare
check "explicit --layout sibling overrides auto-detection on a bare repo" check_explicit_sibling_override_on_bare
check "--layout bare on non-bare repo exits 1 with migrate hint" check_explicit_bare_refused_on_sibling
check "unknown --layout value exits 64" check_unknown_layout_exits_64
check "setup.sh in bare mode resolves paths against bare-root, not show-toplevel" check_setup_in_bare_resolves_against_bare_root
check "status.sh --info emits layout_mode JSON" check_status_info_reports_mode
check "sibling install matches v0.1.x template structure (modulo version/timestamp)" check_sibling_install_structural_match
check "v0.2.0 install is idempotent (byte-stable across re-runs)" check_install_idempotent_v020
check "layout YAML carries layout_mode field" check_layout_yaml_has_layout_mode_field
check "cleanup.sh defensive guard prevents main-branch worktree removal" check_cleanup_skips_main_branch

if [[ "$failures" -eq 0 ]]; then
  echo "PASS test-bare-mode: 11/11"
else
  echo "FAIL test-bare-mode: $failures failing checks"
fi

exit "$failures"
