#!/usr/bin/env bash
# worktree-setup.sh — manage per-track git worktrees so parallel
# agents don't share a working directory. Convention is read from
# the layout YAML (default {{LAYOUT_DIR}}/WORKTREE_LAYOUT.yaml).
#
# Installed by bbe-worktree-toolkit (https://github.com/BBE-DBE/bbe-worktree-toolkit).
# License: MIT.
set -euo pipefail

LAYOUT_FILE="${WORKTREE_LAYOUT_FILE:-{{LAYOUT_DIR}}/WORKTREE_LAYOUT.yaml}"

usage() {
  cat >&2 <<'EOF'
Usage:
  worktree-setup.sh create <track> <task-id> <branch-name>
  worktree-setup.sh list
  worktree-setup.sh remove <track> <task-id> [--force]

Subcommands
  create  Add a new worktree at base_path/<track>-<task-id>, checked out
          on <branch-name>. Seeds central_state_dir on first run if
          declared.
  list    Show every active worktree (cross-checks `git worktree list`).
  remove  Delete a worktree. Refuses if dirty (exit 2) or if branch is
          not merged to origin/main (exit 3) unless --force is given.

Exits
  0   ok
  2   worktree already exists / dirty
  3   branch not merged and --force not given
  64  argument error
  65  layout file missing or malformed
EOF
}

die() {
  local code="$1"
  shift
  printf 'worktree-setup: %s\n' "$*" >&2
  exit "$code"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die 1 "missing required command: $1"
}

iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

require_layout() {
  [[ -f "$LAYOUT_FILE" ]] || die 65 "layout file not found: $LAYOUT_FILE (single-tree mode is the default; multi-tree mode requires this file)"
  yq . "$LAYOUT_FILE" >/dev/null 2>&1 || die 65 "malformed yaml: $LAYOUT_FILE"
}

repo_root() {
  git rev-parse --show-toplevel
}

resolve_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s' "$p"
  else
    printf '%s/%s' "$(repo_root)" "$p"
  fi
}

layout_get() {
  local key="$1"
  yq -r ".$key // \"\"" "$LAYOUT_FILE"
}

worktree_path_for() {
  local track="$1"
  local task_id="$2"
  local base pattern rel
  base="$(layout_get base_path)"
  pattern="$(layout_get pattern)"
  [[ -n "$base" ]] || die 65 "layout: base_path missing"
  [[ -n "$pattern" ]] || die 65 "layout: pattern missing"
  rel="${pattern//\{track\}/$track}"
  rel="${rel//\{task_id\}/$task_id}"
  printf '%s/%s' "$(resolve_path "$base")" "$rel"
}

# Seed the central state directory + file from a source path if the
# central_state_dir is configured and the central file does not yet
# exist. Idempotent.
seed_central_state() {
  local src="$1"
  local rel_dir rel_file dir target
  rel_dir="$(layout_get central_state_dir)"
  rel_file="$(layout_get central_state_file)"
  if [[ -z "$rel_dir" || "$rel_dir" == "null" ]]; then
    return 0
  fi
  if [[ -z "$rel_file" || "$rel_file" == "null" ]]; then
    rel_file="STATE.json"
  fi
  dir="$(resolve_path "$rel_dir")"
  target="$dir/$rel_file"
  if [[ -f "$target" ]]; then
    return 0
  fi
  mkdir -p "$dir"
  if [[ -f "$src" ]]; then
    cp "$src" "$target"
    printf 'worktree-setup: seeded central state %s from %s\n' "$target" "$src" >&2
  else
    printf 'worktree-setup: warning: source %s missing; central state not seeded\n' "$src" >&2
  fi
}

cmd_create() {
  [[ $# -eq 3 ]] || { usage; exit 64; }
  local track="$1"
  local task_id="$2"
  local branch="$3"

  case "$track" in
    track_a|track_b|track_c) ;;
    *) die 64 "unknown track '$track' (expected track_a, track_b, or track_c)" ;;
  esac
  [[ "$task_id" =~ ^[A-Z][A-Z0-9-]+$ ]] || die 64 "task_id must match ^[A-Z][A-Z0-9-]+$"
  [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || die 64 "branch fails sanity pattern"

  require_cmd git
  require_cmd yq
  require_layout

  local target
  target="$(worktree_path_for "$track" "$task_id")"
  if [[ -e "$target" ]]; then
    die 2 "worktree already exists at $target"
  fi

  local parent
  parent="$(dirname "$target")"
  mkdir -p "$parent"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$target" "$branch" >&2
  else
    git worktree add -b "$branch" "$target" >&2
  fi

  # Seed central state from this worktree's committed copy if any.
  local seed_src rel_file
  rel_file="$(layout_get central_state_file)"
  if [[ -z "$rel_file" || "$rel_file" == "null" ]]; then
    rel_file="STATE.json"
  fi
  seed_src="$target/$(layout_get central_state_dir)/$rel_file"
  seed_central_state "$seed_src"

  printf '%s\n' "$target"
  printf 'worktree-setup: created %s on %s for %s/%s at %s\n' \
    "$target" "$branch" "$track" "$task_id" "$(iso_now)" >&2
}

cmd_list() {
  require_cmd git
  require_cmd yq

  printf '%-9s  %-12s  %-44s  %s\n' "TRACK" "TASK" "BRANCH" "PATH"
  local base
  if [[ -f "$LAYOUT_FILE" ]]; then
    base="$(resolve_path "$(layout_get base_path)")"
  else
    base=""
  fi

  git worktree list --porcelain | awk -v base="$base" '
    function emit() {
      if (path == "") return
      track = "-"
      task = "-"
      if (base != "" && index(path, base "/") == 1) {
        rel = substr(path, length(base) + 2)
        n = index(rel, "-")
        if (n > 0) {
          if (substr(rel, 1, 8) == "track_a-") {
            track = "track_a"
            task = substr(rel, 9)
          } else if (substr(rel, 1, 8) == "track_b-") {
            track = "track_b"
            task = substr(rel, 9)
          } else if (substr(rel, 1, 8) == "track_c-") {
            track = "track_c"
            task = substr(rel, 9)
          } else {
            track = substr(rel, 1, n - 1)
            task = substr(rel, n + 1)
          }
        }
      }
      printf "%-9s  %-12s  %-44s  %s\n", track, task, branch, path
    }
    /^worktree / { emit(); path = substr($0, 10); branch = "-" }
    /^branch refs\/heads\// { branch = substr($0, 19) }
    /^bare/ { branch = "(bare)" }
    /^detached/ { branch = "(detached)" }
    END { emit() }
  '
}

cmd_remove() {
  local force=0
  local args=()
  for a in "$@"; do
    case "$a" in
      --force) force=1 ;;
      *) args+=("$a") ;;
    esac
  done
  set -- "${args[@]}"
  [[ $# -eq 2 ]] || { usage; exit 64; }
  local track="$1"
  local task_id="$2"

  require_cmd git
  require_cmd yq
  require_layout

  local target
  target="$(worktree_path_for "$track" "$task_id")"
  [[ -d "$target" ]] || die 64 "no worktree at $target"

  local dirty
  dirty="$(git -C "$target" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$dirty" -ne 0 && "$force" -ne 1 ]]; then
    die 2 "worktree dirty ($dirty files); use --force to override"
  fi

  local branch
  branch="$(git -C "$target" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -n "$branch" && "$branch" != "main" && "$force" -ne 1 ]]; then
    if ! git merge-base --is-ancestor "$branch" origin/main 2>/dev/null; then
      die 3 "branch '$branch' not merged to origin/main; use --force to override"
    fi
  fi

  if [[ "$force" -eq 1 ]]; then
    git worktree remove --force "$target" >&2
  else
    git worktree remove "$target" >&2
  fi
  printf 'worktree-setup: removed %s\n' "$target" >&2
}

main() {
  [[ $# -ge 1 ]] || { usage; exit 64; }
  local sub="$1"
  shift
  case "$sub" in
    create) cmd_create "$@" ;;
    list) [[ $# -eq 0 ]] || { usage; exit 64; }; cmd_list ;;
    remove) cmd_remove "$@" ;;
    -h|--help|help) usage ;;
    *) usage; exit 64 ;;
  esac
}

main "$@"
