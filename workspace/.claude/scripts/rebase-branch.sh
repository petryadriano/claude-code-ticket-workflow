#!/usr/bin/env bash
# rebase-branch.sh — rebase a feature branch onto its remote target
#
# Usage: rebase-branch.sh --repo <repo> --branch <branch> [--target <target-branch>] [--path <abs-path>]
#
# --path overrides the default BASE/REPO path resolution (use for submodule repos)
#
# Output:
#   UPTODATE|repo|branch                   (nothing to rebase)
#   OK|repo|branch|N                       (rebased N commits)
#   CONFLICT|repo|branch|file1 file2 ...   (stopped mid-rebase — user must resolve)
#   ERROR|repo|message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib-protected.sh"
source "$SCRIPT_DIR/lib-branches.sh"
REPO=""
BRANCH=""
TARGET=""
PATH_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   REPO="$2";          shift ;;
    --branch) BRANCH="$2";        shift ;;
    --target) TARGET="$2";        shift ;;
    --path)   PATH_OVERRIDE="$2"; shift ;;
  esac
  shift
done

[ -z "$REPO" ]   && { echo "ERROR||missing --repo";   exit 1; }
[ -z "$BRANCH" ] && { echo "ERROR||missing --branch"; exit 1; }

# Resolve repo path: explicit override > known submodule table > BASE/REPO
if [ -n "$PATH_OVERRIDE" ]; then
  path="$PATH_OVERRIDE"
else
  case "$REPO" in
    shared) path="$BASE/api/shared" ;;
    *)      path="$BASE/$REPO" ;;
  esac
fi

# Resolve target branch if not provided — same resolution as create-branch/prepare-mr/sync-repos
# (lib-branches.sh), so a rebase always targets the base the branch was cut from.
if [ -z "$TARGET" ]; then
  TARGET=$(resolve_base "$REPO" "$path")
fi

[ -z "$TARGET" ] && { echo "ERROR|$REPO|cannot resolve target branch"; exit 1; }

# Fetch latest from origin
fetch_err=$(git -C "$path" fetch origin 2>&1)
[ $? -ne 0 ] && { echo "ERROR|$REPO|fetch failed: $(echo "$fetch_err" | head -1)"; exit 1; }

# Check if branch exists locally
git -C "$path" rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
  || { echo "ERROR|$REPO|branch '$BRANCH' not found locally"; exit 1; }

# Check if target exists on remote
git -C "$path" rev-parse --verify "origin/$TARGET" >/dev/null 2>&1 \
  || { echo "ERROR|$REPO|remote target 'origin/$TARGET' not found"; exit 1; }

# Snapshot protected files before checkout — restored unconditionally at exit
protected_tmp=$(mktemp -d)
save_protected "$path" "$protected_tmp"

# Checkout feature branch
git -C "$path" checkout "$BRANCH" -q 2>/dev/null \
  || { restore_protected "$path" "$protected_tmp"; echo "ERROR|$REPO|checkout $BRANCH failed"; exit 1; }

# How many commits behind?
behind=$(git -C "$path" rev-list --count HEAD..origin/"$TARGET" 2>/dev/null)

if [ "$behind" = "0" ]; then
  restore_protected "$path" "$protected_tmp"
  echo "UPTODATE|$REPO|$BRANCH"
  exit 0
fi

# Attempt rebase
rebase_out=$(git -C "$path" rebase origin/"$TARGET" 2>&1)
rebase_exit=$?

restore_protected "$path" "$protected_tmp"

if [ $rebase_exit -eq 0 ]; then
  ahead=$(git -C "$path" rev-list --count origin/"$TARGET"..HEAD 2>/dev/null)
  echo "OK|$REPO|$BRANCH|$ahead"
  exit 0
fi

# Rebase stopped — collect conflicted files
conflicted=$(git -C "$path" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
echo "CONFLICT|$REPO|$BRANCH|$conflicted"
exit 2
