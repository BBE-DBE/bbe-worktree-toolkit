#!/usr/bin/env bash
# worktree-status.sh — read-only summary of every active git worktree
# in the current repository. Standalone replacement for the worktree-
# status block previously embedded in bbe-coord's agent-relay.sh.
#
# Installed by bbe-worktree-toolkit (https://github.com/BBE-DBE/bbe-worktree-toolkit).
# License: MIT.
#
# Usage:
#   worktree-status.sh            (table view)
#   worktree-status.sh --json     (machine-readable)
#   worktree-status.sh --check    (exit 0 iff multi-worktree mode active)
set -euo pipefail

LAYOUT_FILE="${WORKTREE_LAYOUT_FILE:-{{LAYOUT_DIR}}/WORKTREE_LAYOUT.yaml}"

usage() {
  cat >&2 <<'EOF'
Usage: worktree-status.sh [--json | --check | --info]
  default  Print a human-readable table of active worktrees.
  --json   Emit a JSON array, one object per worktree.
  --check  Exit 0 iff a layout file is present and ≥ 1 non-main worktree
           is registered. Exit 1 otherwise. Useful for CI gating.
  --info   Emit a JSON object with layout-level metadata
           (layout_mode, layout_file, main_root). v0.2.0+.
EOF
}

mode="table"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) mode="json" ;;
    --check) mode="check" ;;
    --info) mode="info" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || {
  printf 'worktree-status: missing required command: git\n' >&2
  exit 1
}

main_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$main_root" ]] || {
  printf 'worktree-status: not in a git repository\n' >&2
  exit 1
}

# Returns 0 if multi-worktree mode is opt-in (layout file exists).
has_layout() {
  [[ -f "$LAYOUT_FILE" ]]
}

# layout_mode_value — read .layout_mode from YAML (v0.2.0+), default
# to sibling for v0.1.x layouts that pre-date the field. Uses awk so
# we don't require yq for the read-only summary.
layout_mode_value() {
  if ! has_layout; then printf 'sibling'; return; fi
  local m
  m="$(awk -F': *' '/^layout_mode:/ { gsub(/^"|"$/, "", $2); print $2; exit }' "$LAYOUT_FILE" 2>/dev/null)"
  if [[ -z "$m" ]]; then printf 'sibling'; else printf '%s' "$m"; fi
}

# Emit one record per worktree as TSV: branch<TAB>path<TAB>head_sha<TAB>kind
records_tsv() {
  git worktree list --porcelain | awk '
    function emit() {
      if (path == "") return
      printf "%s\t%s\t%s\t%s\n", branch, path, head, kind
      path=""; branch="-"; head="-"; kind="worktree"
    }
    /^worktree / { emit(); path=substr($0, 10); branch="-"; head="-"; kind="worktree" }
    /^HEAD / { head=substr($0, 6) }
    /^branch refs\/heads\// { branch=substr($0, 19) }
    /^detached/ { branch="(detached)" }
    /^bare/ { branch="(bare)"; kind="bare" }
    END { emit() }
  '
}

case "$mode" in
  table)
    records="$(records_tsv)"
    if [[ -z "$records" ]]; then
      printf 'No worktrees registered.\n'
      exit 0
    fi
    printf '%-44s  %-12s  %s\n' "BRANCH" "HEAD" "PATH"
    while IFS=$'\t' read -r branch path head _kind; do
      [[ "$path" == "$main_root" ]] && marker=" *" || marker=""
      printf '%-44s  %-12s  %s%s\n' "$branch" "${head:0:10}" "$path" "$marker"
    done <<<"$records"
    if has_layout; then
      printf '\nLayout: %s\n' "$LAYOUT_FILE"
      printf 'Mode:   %s\n' "$(layout_mode_value)"
    else
      printf '\nLayout: (none — single-tree mode)\n'
    fi
    ;;
  json)
    # JSON output stays a top-level array for backwards compat with
    # v0.1.x consumers (docs/ADVANCED.md examples use `jq '.[] | ...'`).
    # New layout-level metadata is exposed via `--info` instead.
    records="$(records_tsv)"
    {
      printf '['
      first=1
      while IFS=$'\t' read -r branch path head kind; do
        [[ -z "$path" ]] && continue
        [[ "$first" -eq 1 ]] || printf ','
        first=0
        is_main="false"
        [[ "$path" == "$main_root" ]] && is_main="true"
        printf '{"branch":"%s","path":"%s","head":"%s","kind":"%s","is_main_checkout":%s}' \
          "$branch" "$path" "$head" "$kind" "$is_main"
      done <<<"$records"
      printf ']\n'
    }
    ;;
  info)
    # v0.2.0+ layout-level metadata. Stable JSON object.
    layout_path=""
    has_layout && layout_path="$LAYOUT_FILE"
    printf '{"layout_mode":"%s","layout_file":"%s","main_root":"%s"}\n' \
      "$(layout_mode_value)" "$layout_path" "$main_root"
    ;;
  check)
    has_layout || exit 1
    n=$(records_tsv | awk -v main="$main_root" '$2 != main { count++ } END { print count+0 }')
    [[ "$n" -ge 1 ]]
    ;;
esac
