#!/usr/bin/env bash
# create-branch.sh — create a feature/bugfix branch from the correct base
#
# Usage: create-branch.sh --repo <repo> --branch <full-branch-name> [--from <base-branch>]
#
# --from overrides the auto-resolved base. Use for stacked MRs where the base
# is another feature branch, not develop.
#
# Output:
#   OK|repo|branch|base_branch
#   ERROR|message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib-protected.sh"
source "$SCRIPT_DIR/lib-branches.sh"
REPO=""
BRANCH=""
FROM=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   REPO="$2";   shift ;;
    --branch) BRANCH="$2"; shift ;;
    --from)   FROM="$2";   shift ;;
  esac
  shift
done

[ -z "$REPO" ]   && { echo "ERROR|missing --repo";   exit 1; }
[ -z "$BRANCH" ] && { echo "ERROR|missing --branch"; exit 1; }

path="$BASE/$REPO"

# resolve_base comes from lib-branches.sh (single source of truth)

if [ -n "$FROM" ]; then
  base="$FROM"
else
  base=$(resolve_base "$REPO" "$path")
  [ -z "$base" ] && { echo "ERROR|cannot resolve base branch for $REPO"; exit 1; }
fi

# Snapshot protected files before any git operation — restored unconditionally at exit
protected_tmp=$(mktemp -d)
save_protected "$path" "$protected_tmp"

# ensure base is up to date
git -C "$path" fetch origin -q 2>/dev/null

stashed=false
if [ -n "$(is_dirty "$path")" ]; then
  git -C "$path" stash --include-untracked -q 2>/dev/null \
    && stashed=true \
    || { restore_protected "$path" "$protected_tmp"; echo "ERROR|stash failed"; exit 1; }
fi

git -C "$path" checkout "$base" -q 2>/dev/null \
  || { $stashed && git -C "$path" stash pop -q 2>/dev/null; restore_protected "$path" "$protected_tmp"; echo "ERROR|checkout $base failed"; exit 1; }

pull_err=$(git -C "$path" pull 2>&1)
if [ $? -ne 0 ]; then
  $stashed && git -C "$path" stash pop -q 2>/dev/null
  restore_protected "$path" "$protected_tmp"
  echo "ERROR|pull $base failed: $(echo "$pull_err" | head -1)"; exit 1
fi
$stashed && git -C "$path" stash pop -q 2>/dev/null

# check branch doesn't already exist
git -C "$path" branch --list "$BRANCH" | grep -q . \
  && { restore_protected "$path" "$protected_tmp"; echo "ERROR|branch $BRANCH already exists locally"; exit 1; }
git -C "$path" branch -r 2>/dev/null | grep -q "origin/$BRANCH" \
  && { restore_protected "$path" "$protected_tmp"; echo "ERROR|branch $BRANCH already exists on remote"; exit 1; }

git -C "$path" checkout -b "$BRANCH" -q 2>/dev/null \
  || { restore_protected "$path" "$protected_tmp"; echo "ERROR|failed to create branch $BRANCH"; exit 1; }

restore_protected "$path" "$protected_tmp"
echo "OK|$REPO|$BRANCH|$base"
