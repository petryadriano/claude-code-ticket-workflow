#!/usr/bin/env bash
# detect-wip.sh — scan repos for active feature/bugfix branches
#
# Usage: detect-wip.sh
#
# Output:
#   BRANCH|repo|branch|ticket         (repo currently on a feature/bugfix branch)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib-branches.sh"   # provides ALL_REPOS

# scan repos for active feature/bugfix branches
for repo in $ALL_REPOS; do
  branch=$(git -C "$BASE/$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if echo "$branch" | grep -qE '^(feature|bugfix)/PROJ-[0-9]+_'; then
    ticket=$(echo "$branch" | grep -oE 'PROJ-[0-9]+')
    echo "BRANCH|$repo|$branch|$ticket"
  fi
done
