#!/usr/bin/env bash
# shellcheck disable=SC2317
# test-npm-wrapper.sh — verifies the bin/bbe-worktree.js wrapper:
#   - help, version, and unknown-command exit codes
#   - init forwards to install.sh and produces the same files
#   - check / uninstall subcommands work end-to-end
#   - npm pack produces a tarball that includes install.sh + templates/
#     and excludes tests/, docs/, .git/
#   - the bin file is executable as a script (#!/usr/bin/env node)
#
# All sandboxes live under /tmp/wtt-test-npm-$$.
set -u

failures=0
toolkit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="/tmp/wtt-test-npm-$$"
bin="$toolkit_dir/bin/bbe-worktree.js"

cleanup() { rm -rf "$sandbox"; }
trap cleanup EXIT
mkdir -p "$sandbox"

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS test-npm-wrapper: $name"
  else
    echo "FAIL test-npm-wrapper: $name"
    failures=$((failures + 1))
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "SKIP test-npm-wrapper: $1 not on PATH" >&2
    exit 0
  }
}

require_cmd node
require_cmd npm

# ---- helpers --------------------------------------------------------------

fresh_repo() {
  local repo="$1"
  rm -rf "$repo"
  mkdir -p "$repo"
  cp -r "$toolkit_dir/tests/fixtures/empty-repo/." "$repo/"
  git -C "$repo" init --quiet --initial-branch=main
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
  git -C "$repo" add -A
  git -C "$repo" commit --quiet -m "fixture init"
}

# ---- tests ----------------------------------------------------------------

check_bin_is_executable_node_shebang() {
  [[ -x "$bin" ]] || return 1
  head -n1 "$bin" | grep -Fq '#!/usr/bin/env node'
}

check_help_exits_zero_and_shows_init() {
  local out
  out="$(node "$bin" help 2>&1)" || return 1
  grep -q 'init' <<<"$out" || return 1
  grep -q 'check' <<<"$out" || return 1
  grep -q 'uninstall' <<<"$out"
}

check_help_via_no_args() {
  node "$bin" >/dev/null 2>&1
}

check_help_via_dash_h() {
  node "$bin" -h >/dev/null 2>&1
}

check_version_prints_both() {
  local out
  out="$(node "$bin" version 2>&1)" || return 1
  grep -q 'npm package:' <<<"$out" || return 1
  grep -q 'toolkit:' <<<"$out" || return 1
  # Toolkit line must match the VERSION file exactly.
  local v
  v="$(cat "$toolkit_dir/VERSION")"
  grep -Fq "$v" <<<"$out"
}

check_unknown_command_exits_64() {
  local code=0
  node "$bin" banana >/dev/null 2>&1 || code=$?
  [[ "$code" == "64" ]]
}

check_init_forwards_to_install_sh() {
  local repo="$sandbox/init-default"
  fresh_repo "$repo"
  (cd "$repo" && node "$bin" init >/dev/null) || return 1
  [[ -f "$repo/.worktrees/WORKTREE_LAYOUT.yaml" ]] || return 1
  [[ -x "$repo/.worktrees/scripts/worktree-setup.sh" ]] || return 1
  [[ -x "$repo/.worktrees/scripts/worktree-cleanup.sh" ]] || return 1
  [[ -x "$repo/.worktrees/scripts/worktree-status.sh" ]]
}

check_init_passes_through_layout_dir_flag() {
  local repo="$sandbox/init-custom-layout"
  fresh_repo "$repo"
  (cd "$repo" && node "$bin" init --layout-dir .bbe-coord >/dev/null) || return 1
  [[ -f "$repo/.bbe-coord/WORKTREE_LAYOUT.yaml" ]] || return 1
  [[ ! -d "$repo/.worktrees" ]]
}

check_init_idempotent() {
  local repo="$sandbox/init-idem"
  fresh_repo "$repo"
  (cd "$repo" && node "$bin" init >/dev/null) || return 1
  local first
  first="$(find "$repo/.worktrees" -type f -exec sha256sum {} + | sort)"
  (cd "$repo" && node "$bin" init >/dev/null) || return 1
  local second
  second="$(find "$repo/.worktrees" -type f -exec sha256sum {} + | sort)"
  [[ "$first" == "$second" ]]
}

check_check_subcommand_runs() {
  local repo="$sandbox/check-sub"
  fresh_repo "$repo"
  (cd "$repo" && node "$bin" init >/dev/null) || return 1
  local out
  out="$(cd "$repo" && node "$bin" check 2>&1)" || return 1
  grep -q '\[installed\]' <<<"$out"
}

check_uninstall_subcommand_removes_files() {
  local repo="$sandbox/uninstall-sub"
  fresh_repo "$repo"
  (cd "$repo" && node "$bin" init >/dev/null) || return 1
  [[ -f "$repo/.worktrees/WORKTREE_LAYOUT.yaml" ]] || return 1
  (cd "$repo" && node "$bin" uninstall >/dev/null) || return 1
  [[ ! -f "$repo/.worktrees/WORKTREE_LAYOUT.yaml" ]]
}

check_init_resolves_install_sh_from_arbitrary_cwd() {
  # Critical contract: npx is invoked from the user's repo, not the
  # package dir. The bin must locate install.sh via __dirname, not cwd.
  local repo="$sandbox/init-cwd-far-away"
  fresh_repo "$repo"
  # Use a relative path to bin that would only resolve from a cwd that
  # doesn't help, then run from inside the user's repo.
  (cd "$repo" && node "$bin" init >/dev/null) || return 1
  [[ -f "$repo/.worktrees/WORKTREE_LAYOUT.yaml" ]]
}

# ---- npm pack tarball --------------------------------------------------

check_npm_pack_produces_tarball_with_required_files() {
  local pack_dir="$sandbox/pack"
  mkdir -p "$pack_dir"
  local tarball
  tarball="$(cd "$toolkit_dir" && npm pack --pack-destination "$pack_dir" --silent 2>/dev/null)" || return 1
  tarball="$pack_dir/$tarball"
  [[ -f "$tarball" ]] || return 1
  local listing
  listing="$(tar tzf "$tarball")" || return 1
  # Required: install.sh, VERSION, templates/, bin/bbe-worktree.js,
  # package.json, LICENSE, README.md.
  grep -Fq 'package/install.sh' <<<"$listing" || { echo "missing install.sh" >&2; return 1; }
  grep -Fq 'package/VERSION' <<<"$listing" || { echo "missing VERSION" >&2; return 1; }
  grep -Fq 'package/bin/bbe-worktree.js' <<<"$listing" || { echo "missing bin/bbe-worktree.js" >&2; return 1; }
  grep -Fq 'package/package.json' <<<"$listing" || { echo "missing package.json" >&2; return 1; }
  grep -Fq 'package/LICENSE' <<<"$listing" || { echo "missing LICENSE" >&2; return 1; }
  grep -Fq 'package/README.md' <<<"$listing" || { echo "missing README.md" >&2; return 1; }
  grep -Fq 'package/templates/worktree-setup.sh' <<<"$listing" || { echo "missing templates/" >&2; return 1; }
  # Forbidden: tests/, docs/, .git/.
  if grep -Fq 'package/tests/' <<<"$listing"; then
    echo "tarball includes tests/" >&2; return 1
  fi
  if grep -Fq 'package/docs/' <<<"$listing"; then
    echo "tarball includes docs/" >&2; return 1
  fi
  if grep -Fq 'package/.git' <<<"$listing"; then
    echo "tarball includes .git" >&2; return 1
  fi
}

check_pack_install_path_resolves_after_extract() {
  # Sanity: extract the packed tarball, run the bin from the extracted
  # location, and confirm it locates install.sh in the same package dir
  # — not from any source-tree leakage.
  local pack_dir="$sandbox/pack-extract"
  mkdir -p "$pack_dir"
  local tarball
  tarball="$(cd "$toolkit_dir" && npm pack --pack-destination "$pack_dir" --silent 2>/dev/null)" || return 1
  tar xzf "$pack_dir/$tarball" -C "$pack_dir"
  # Extract creates a `package/` directory.
  local pkg="$pack_dir/package"
  [[ -x "$pkg/bin/bbe-worktree.js" ]] || return 1
  local repo="$sandbox/extracted-init"
  fresh_repo "$repo"
  (cd "$repo" && node "$pkg/bin/bbe-worktree.js" init >/dev/null) || return 1
  [[ -f "$repo/.worktrees/WORKTREE_LAYOUT.yaml" ]]
}

# ---- run ------------------------------------------------------------------

check "bin has node shebang and is executable"        check_bin_is_executable_node_shebang
check "help exits zero and lists subcommands"         check_help_exits_zero_and_shows_init
check "no-args prints help (exit 0)"                  check_help_via_no_args
check "-h prints help (exit 0)"                       check_help_via_dash_h
check "version prints both pkg + toolkit"             check_version_prints_both
check "unknown command exits 64"                      check_unknown_command_exits_64
check "init forwards to install.sh (default layout)"  check_init_forwards_to_install_sh
check "init passes through --layout-dir flag"         check_init_passes_through_layout_dir_flag
check "init is idempotent"                            check_init_idempotent
check "check subcommand reports installed"            check_check_subcommand_runs
check "uninstall subcommand removes files"            check_uninstall_subcommand_removes_files
check "init resolves install.sh via __dirname"        check_init_resolves_install_sh_from_arbitrary_cwd
check "npm pack tarball includes required files"      check_npm_pack_produces_tarball_with_required_files
check "extracted tarball can install into a repo"     check_pack_install_path_resolves_after_extract

if [[ "$failures" -gt 0 ]]; then
  echo "test-npm-wrapper: $failures failure(s)" >&2
  exit 1
fi
echo "test-npm-wrapper: all checks passed"
