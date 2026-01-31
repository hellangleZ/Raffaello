#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./raffaello-merge.sh [--project-dir DIR] list
  ./raffaello-merge.sh [--project-dir DIR] merge-pass
  ./raffaello-merge.sh [--project-dir DIR] merge <STORY-ID> [<STORY-ID> ...]

Notes:
  - Merges story branches (story-<STORY-ID>) into the current branch (recommended: master).
  - 'merge-pass' merges stories with passes=true in prd.json, in numeric order.
EOF
}


# Optional: target project directory (defaults to cwd)
if [[ "${1:-}" == "--project-dir" ]]; then
  PROJECT_DIR="$2"
  shift 2
fi

cd "$PROJECT_DIR"

cmd=${1:-}
shift || true

if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi

require_clean_index() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree is not clean. Commit/stash first." >&2
    git status --porcelain >&2
    exit 2
  fi
}

story_branch() {
  local story_id=$1
  echo "story-${story_id}"
}

merge_one() {
  local story_id=$1
  local br
  br=$(story_branch "$story_id")

  if ! git show-ref --verify --quiet "refs/heads/${br}"; then
    echo "SKIP: branch not found: ${br}" >&2
    return 0
  fi

  echo "==> Merging ${br}"
  git merge --no-ff "$br"
}

case "$cmd" in
  list)
    if command -v jq >/dev/null 2>&1 && [[ -f prd.json ]]; then
      echo "Stories with passes=true:" 
      jq -r '.userStories[] | select(.passes==true) | .id' prd.json | sort
    else
      echo "Branches:" 
      git branch --list 'story-STORY-*'
    fi
    ;;

  merge-pass)
    require_clean_index
    if ! command -v jq >/dev/null 2>&1; then
      echo "ERROR: jq not found; cannot read prd.json" >&2
      exit 3
    fi
    ids=$(jq -r '.userStories[] | select(.passes==true) | .id' prd.json | sort)
    if [[ -z "$ids" ]]; then
      echo "No passes=true stories found in prd.json" >&2
      exit 0
    fi
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      merge_one "$id"
    done <<<"$ids"
    ;;

  merge)
    require_clean_index
    if [[ $# -lt 1 ]]; then
      usage
      exit 1
    fi
    for id in "$@"; do
      merge_one "$id"
    done
    ;;

  *)
    usage
    exit 1
    ;;
esac

