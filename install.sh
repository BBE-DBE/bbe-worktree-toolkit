#!/usr/bin/env bash
# install.sh — scaffold bbe-worktree-toolkit into a target git repo.
#
# Idempotent: a second run skips already-installed pieces and reports
# what it would have done.
#
# Usage:
#   install.sh                          # install into current repo
#   install.sh --layout-dir <path>      # default: .worktrees
#   install.sh --base-path <path>       # default mode-aware (see below)
#   install.sh --layout <mode>          # auto | sibling | bare. default: auto
#   install.sh --check                  # report installation status, no writes
#   install.sh --uninstall              # remove toolkit-installed files
#   install.sh --version                # print toolkit version
#
# Layout modes (v0.2.0+):
#   auto     Detect from target repo state: bare if <root>/.bare/ + .git
#            pointer file exist; sibling otherwise. Default.
#   sibling  Force the v0.1.x layout. base_path defaults to
#            ../<repo>-worktrees. Always works.
#   bare     Force bare-repo layout. Requires the target repo to
#            already be in bare layout (run scripts/migrate-to-bare.sh
#            first to convert a sibling repo). base_path defaults to
#            "." so worktrees become siblings of .bare/.
#
# Prerequisites: bash >= 4, git >= 2.5, sed, awk, optional yq + jq.
#
# License: MIT. See LICENSE in the toolkit repo.
set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_VERSION="$(cat "$TOOLKIT_DIR/VERSION" 2>/dev/null || printf '0.0.0')"

# Markers used to detect prior installation in target files.
DOCTRINE_BEGIN_MARKER='# >>> bbe-worktree-toolkit T-030 BEGIN — DOCTRINE rule <<<'
DOCTRINE_END_MARKER='# >>> bbe-worktree-toolkit T-030 END — DOCTRINE rule <<<'
RATIONALE_BEGIN_MARKER='<!-- >>> bbe-worktree-toolkit T-030 BEGIN — RATIONALE anchor <<< -->'
RATIONALE_END_MARKER='<!-- >>> bbe-worktree-toolkit T-030 END — RATIONALE anchor <<< -->'

# Defaults
layout_dir=".worktrees"
base_path=""
mode="install"
layout_mode="auto"
base_path_was_explicit=0

usage() {
  sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

die() {
  local code="$1"
  shift
  printf 'install: %s\n' "$*" >&2
  exit "$code"
}

info() {
  printf 'install: %s\n' "$*"
}

# ---- arg parsing ------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --layout-dir)
      shift
      [[ $# -gt 0 ]] || die 64 "--layout-dir requires a value"
      layout_dir="$1"
      ;;
    --base-path)
      shift
      [[ $# -gt 0 ]] || die 64 "--base-path requires a value"
      base_path="$1"
      base_path_was_explicit=1
      ;;
    --layout)
      shift
      [[ $# -gt 0 ]] || die 64 "--layout requires a value (auto|sibling|bare)"
      case "$1" in
        auto|sibling|bare) layout_mode="$1" ;;
        *) die 64 "--layout must be one of: auto | sibling | bare (got '$1')" ;;
      esac
      ;;
    --check)
      mode="check"
      ;;
    --uninstall)
      mode="uninstall"
      ;;
    --version)
      printf '%s\n' "$TOOLKIT_VERSION"
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die 64 "unknown argument: $1 (use --help)"
      ;;
  esac
  shift
done

# ---- target repo discovery --------------------------------------------------

command -v git >/dev/null 2>&1 || die 1 "git is required"

target_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$target_root" ]] || die 65 "not in a git repository (run install.sh from inside the target repo)"

repo_name="$(basename "$target_root")"

# ---- layout-mode resolution -------------------------------------------------
#
# A target repo is in "bare layout" iff <root>/.bare exists and is a
# git bare repository AND <root>/.git is a pointer file containing
# "gitdir: ./.bare". Otherwise it's "sibling layout".
#
# auto: pick from the target's state.
# sibling: always sibling, even if .bare/ exists (operator override).
# bare: refuse if target isn't already bare; point at migrate-to-bare.sh.

detect_layout_mode() {
  local root="$1"
  # Direct check: <root>/.bare/ + <root>/.git pointer file. Catches
  # the case where install.sh is run from the bare-layout root.
  if [[ -d "$root/.bare" && -f "$root/.git" ]]; then
    if git -C "$root/.bare" rev-parse --is-bare-repository 2>/dev/null | grep -Fxq true; then
      printf 'bare\n'
      return 0
    fi
  fi
  # Indirect check: install.sh is most often run from a worktree
  # (e.g. <root>/main/) rather than the bare-layout root itself.
  # `git rev-parse --git-common-dir` returns the shared git dir
  # across worktrees — for a bare-layout repo that's <root>/.bare.
  local common
  common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -n "$common" ]]; then
    # Resolve to absolute path so basename/dirname behave predictably.
    if [[ "$common" != /* ]]; then
      common="$(cd "$root" && cd "$(dirname "$common")" 2>/dev/null && pwd)/$(basename "$common")"
    fi
    if [[ "$(basename "$common")" == ".bare" ]]; then
      if git -C "$common" rev-parse --is-bare-repository 2>/dev/null | grep -Fxq true; then
        printf 'bare\n'
        return 0
      fi
    fi
  fi
  printf 'sibling\n'
}

# bare_layout_root — for bare layout, returns the parent dir of .bare
# (the directory that hosts main/, track_*-T-NNN/, .bare/, .git
# pointer). Returns empty for sibling layout.
bare_layout_root() {
  local from="$1"
  local common
  common="$(git -C "$from" rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$common" ]] || return 0
  if [[ "$common" != /* ]]; then
    common="$(cd "$from" && cd "$(dirname "$common")" 2>/dev/null && pwd)/$(basename "$common")"
  fi
  if [[ "$(basename "$common")" == ".bare" ]]; then
    dirname "$common"
  fi
}

if [[ "$layout_mode" == "auto" ]]; then
  resolved_layout_mode="$(detect_layout_mode "$target_root")"
else
  resolved_layout_mode="$layout_mode"
  if [[ "$resolved_layout_mode" == "bare" ]]; then
    detected="$(detect_layout_mode "$target_root")"
    if [[ "$detected" != "bare" ]]; then
      die 1 "--layout bare requires the target to already be in bare layout. Run scripts/migrate-to-bare.sh inside the target repo first, then re-run install.sh --layout bare."
    fi
  fi
fi

# In bare mode, the lifecycle scripts need a base_path that resolves
# to the bare-layout root (parent of .bare/), not show-toplevel
# (which is the current worktree, e.g. main/). When install.sh runs
# from inside main/, base_path "." would point into main/ — wrong.
# Use ".." instead so layout_root() in the lifecycle scripts (which
# returns the bare-layout root) resolves the correct destination.
#
# When install.sh runs from the bare-layout root itself (rare; the
# bare-layout root has no working tree), show-toplevel and bare-root
# coincide, so "." would also work — but we always emit ".." for
# bare so the YAML stays portable across worktrees.
if [[ "$base_path_was_explicit" -eq 0 ]]; then
  case "$resolved_layout_mode" in
    sibling) base_path="../${repo_name}-worktrees" ;;
    bare)
      # Use "." so the YAML reads naturally from the bare-layout
      # root's perspective; the lifecycle scripts' layout_root()
      # already maps to the bare-root regardless of which worktree
      # invokes them, so resolve_path("./<rel>") = bare_root + "<rel>".
      base_path="."
      ;;
  esac
fi

# ---- helpers ----------------------------------------------------------------

# write_if_absent_or_changed <dest> <content_command>
#   Writes the output of <content_command> to <dest> if the file does
#   not exist or its content differs. Idempotent.
write_if_absent_or_changed() {
  local dest="$1"
  local content="$2"
  if [[ -f "$dest" ]]; then
    local existing
    existing="$(cat "$dest")"
    if [[ "$existing" == "$content" ]]; then
      info "  $dest already up to date"
      return 0
    fi
    info "  $dest differs — overwriting (toolkit-managed file)"
  else
    info "  $dest creating"
  fi
  printf '%s' "$content" >"$dest"
}

# substitute_template <template_path>
#   Substitutes {{TOKENS}} from the env. Returns content on stdout.
substitute_template() {
  local tmpl="$1"
  # central_state_dir convention:
  #   sibling: <base_path>-state (e.g. ../<repo>-worktrees-state)
  #   bare: <root>/state (lives next to .bare/, peer to worktrees)
  local central_state_dir
  if [[ "$resolved_layout_mode" == "bare" ]]; then
    central_state_dir="$base_path/state"
  else
    central_state_dir="$base_path-state"
  fi
  sed \
    -e "s|{{TOOLKIT_VERSION}}|$TOOLKIT_VERSION|g" \
    -e "s|{{REPO_NAME}}|$repo_name|g" \
    -e "s|{{BASE_PATH}}|$base_path|g" \
    -e "s|{{LAYOUT_DIR}}|$layout_dir|g" \
    -e "s|{{LAYOUT_MODE}}|$resolved_layout_mode|g" \
    -e "s|{{CENTRAL_STATE_DIR}}|$central_state_dir|g" \
    -e "s|{{INSTALL_TIMESTAMP}}|$(date -u '+%Y-%m-%dT%H:%M:%SZ')|g" \
    "$tmpl"
}

# ---- file inventory we manage ----------------------------------------------

scripts_dest_dir="$target_root/$layout_dir/scripts"
layout_dest="$target_root/$layout_dir/WORKTREE_LAYOUT.yaml"

managed_files=(
  "$scripts_dest_dir/worktree-setup.sh"
  "$scripts_dest_dir/worktree-cleanup.sh"
  "$scripts_dest_dir/worktree-status.sh"
  "$layout_dest"
)

# ---- check mode -------------------------------------------------------------

cmd_check() {
  printf 'bbe-worktree-toolkit installation status for %s\n' "$target_root"
  printf '  toolkit version : %s\n' "$TOOLKIT_VERSION"
  printf '  layout dir      : %s\n' "$layout_dir"
  printf '  layout mode     : %s (resolved from --layout=%s)\n' "$resolved_layout_mode" "$layout_mode"
  printf '  base path       : %s\n' "$base_path"
  printf '\n'
  for f in "${managed_files[@]}"; do
    if [[ -f "$f" ]]; then
      printf '  [installed] %s\n' "$f"
    else
      printf '  [absent]    %s\n' "$f"
    fi
  done
  printf '\nDoctrine integration:\n'
  local doctrine_file="$target_root/$layout_dir/DOCTRINE.yaml"
  local rationale_file="$target_root/$layout_dir/DOCTRINE_RATIONALE.md"
  for f in "$doctrine_file" "$rationale_file"; do
    if [[ ! -f "$f" ]]; then
      printf '  [absent]    %s (skipped if missing)\n' "$f"
      continue
    fi
    if grep -Fq "bbe-worktree-toolkit T-030" "$f"; then
      printf '  [merged]    %s\n' "$f"
    else
      printf '  [untouched] %s (will append on install)\n' "$f"
    fi
  done
}

# ---- install mode -----------------------------------------------------------

cmd_install() {
  info "installing into $target_root"
  info "  layout dir   = $layout_dir"
  info "  layout mode  = $resolved_layout_mode"
  info "  base path    = $base_path"
  info "  toolkit ver  = $TOOLKIT_VERSION"

  mkdir -p "$scripts_dest_dir"

  # Copy / refresh templates.
  for name in worktree-setup.sh worktree-cleanup.sh worktree-status.sh; do
    local src="$TOOLKIT_DIR/templates/$name"
    local dst="$scripts_dest_dir/$name"
    [[ -f "$src" ]] || die 1 "template missing: $src"
    local rendered
    rendered="$(substitute_template "$src")"
    write_if_absent_or_changed "$dst" "$rendered"
    chmod +x "$dst"
  done

  # Layout YAML — only render if absent. Re-running install must not
  # clobber a layout that the operator may have customised.
  if [[ ! -f "$layout_dest" ]]; then
    local layout_rendered
    layout_rendered="$(substitute_template "$TOOLKIT_DIR/templates/WORKTREE_LAYOUT.yaml.tmpl")"
    printf '%s' "$layout_rendered" >"$layout_dest"
    info "  $layout_dest creating"
  else
    info "  $layout_dest already exists — leaving operator customisations alone"
  fi

  # Doctrine integration. Skip cleanly if no DOCTRINE.yaml exists.
  integrate_doctrine
}

integrate_doctrine() {
  local doctrine_file="$target_root/$layout_dir/DOCTRINE.yaml"
  local rationale_file="$target_root/$layout_dir/DOCTRINE_RATIONALE.md"
  local snippet_file="$TOOLKIT_DIR/templates/doctrine-snippet.yaml"
  [[ -f "$snippet_file" ]] || die 1 "snippet missing: $snippet_file"

  if [[ -f "$doctrine_file" ]]; then
    if grep -Fq "$DOCTRINE_BEGIN_MARKER" "$doctrine_file"; then
      info "  $doctrine_file already has toolkit snippet — skip"
    else
      append_doctrine_rule "$snippet_file" "$doctrine_file"
      info "  $doctrine_file appended doctrine rule"
    fi
  else
    info "  $doctrine_file absent — skipping doctrine integration (no error)"
  fi

  if [[ -f "$rationale_file" ]]; then
    if grep -Fq "$RATIONALE_BEGIN_MARKER" "$rationale_file"; then
      info "  $rationale_file already has toolkit anchor — skip"
    else
      append_rationale "$snippet_file" "$rationale_file"
      info "  $rationale_file appended rationale anchor"
    fi
  else
    info "  $rationale_file absent — skipping rationale append (no error)"
  fi
}

# Extract the YAML block under `mandatory_rule: |` from the snippet,
# strip the leading two-space indent, and append it to the doctrine
# file under `mandatory_for_every_sprint:`. We do not try to merge
# YAML — the snippet ships with begin/end markers so future runs can
# detect prior installation.
append_doctrine_rule() {
  local snippet="$1"
  local doctrine="$2"
  local block
  block="$(extract_block "$snippet" "mandatory_rule")"
  {
    printf '\n'
    printf '%s\n' "$block"
  } >>"$doctrine"
}

append_rationale() {
  local snippet="$1"
  local rationale="$2"
  local block
  block="$(extract_block "$snippet" "rationale_md")"
  {
    printf '\n'
    printf '%s\n' "$block"
  } >>"$rationale"
}

# extract_block <snippet_path> <key>
#   Reads the block-scalar value of `<key>: |` from a YAML file using
#   awk, strips the leading two-space indent of the block contents.
#   Avoids depending on yq-merge semantics (which differ between
#   python-yq and go-yq).
extract_block() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    BEGIN { in_block = 0; min_indent = -1 }
    {
      # Detect "key: |" line
      if (!in_block) {
        if ($0 ~ "^" key ": *\\|[[:space:]]*$") {
          in_block = 1
          next
        }
      } else {
        # End of block when a non-indented or differently-keyed line appears.
        if ($0 !~ /^([[:space:]]+|$)/) {
          in_block = 0
          next
        }
        # Determine block indent from first non-empty line.
        if (min_indent < 0 && $0 !~ /^[[:space:]]*$/) {
          match($0, /^[[:space:]]+/)
          min_indent = RLENGTH
        }
        # Strip leading min_indent spaces.
        if (min_indent > 0 && length($0) >= min_indent && substr($0, 1, min_indent) == sprintf("%*s", min_indent, "")) {
          print substr($0, min_indent + 1)
        } else {
          print $0
        }
      }
    }
  ' "$file"
}

# ---- uninstall mode ---------------------------------------------------------

cmd_uninstall() {
  info "uninstalling from $target_root"
  for f in "${managed_files[@]}"; do
    if [[ -f "$f" ]]; then
      rm "$f"
      info "  removed $f"
    fi
  done
  if [[ -d "$scripts_dest_dir" ]]; then
    rmdir "$scripts_dest_dir" 2>/dev/null || info "  $scripts_dest_dir not empty — left in place"
  fi

  # Doctrine: remove the marked block in-place.
  local doctrine_file="$target_root/$layout_dir/DOCTRINE.yaml"
  local rationale_file="$target_root/$layout_dir/DOCTRINE_RATIONALE.md"
  remove_marked_block "$doctrine_file" "$DOCTRINE_BEGIN_MARKER" "$DOCTRINE_END_MARKER"
  remove_marked_block "$rationale_file" "$RATIONALE_BEGIN_MARKER" "$RATIONALE_END_MARKER"
}

remove_marked_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  [[ -f "$file" ]] || return 0
  if ! grep -Fq "$begin" "$file"; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v begin="$begin" -v end="$end" '
    {
      if (skip == 1) {
        if (index($0, end) > 0) skip = 0
        next
      }
      if (index($0, begin) > 0) {
        skip = 1
        next
      }
      print
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  info "  removed marked block from $file"
}

# ---- main -------------------------------------------------------------------

case "$mode" in
  install) cmd_install ;;
  check) cmd_check ;;
  uninstall) cmd_uninstall ;;
esac
