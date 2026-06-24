#!/usr/bin/env bash
# push-branch.sh — push a branch to origin with tracking
#
# Usage: push-branch.sh --repo <repo> --branch <branch>
#
# Output:
#   OK|repo|branch|repo_url
#   ERROR|repo|message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO=""
BRANCH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   REPO="$2";   shift ;;
    --branch) BRANCH="$2"; shift ;;
  esac
  shift
done

[ -z "$REPO" ]   && { echo "ERROR||missing --repo";   exit 1; }
[ -z "$BRANCH" ] && { echo "ERROR||missing --branch"; exit 1; }

path="$BASE/$REPO"

push_err=$(git -C "$path" push -u origin "$BRANCH" 2>&1)
if [ $? -ne 0 ]; then
  echo "ERROR|$REPO|push failed: $(echo "$push_err" | head -1)"
  exit 1
fi

repo_url=$(git -C "$path" remote get-url origin 2>/dev/null | sed 's|\.git$||')
echo "OK|$REPO|$BRANCH|$repo_url"
