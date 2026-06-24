#!/usr/bin/env bash
# prepare-mr.sh — validate a branch for MR readiness and output the creation URL
#
# Usage: prepare-mr.sh --repo <repo> [--branch <branch>]
#
# Output:
#   CHECK|PASS|description
#   CHECK|FAIL|description
#   URL|mr_creation_url

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib-branches.sh"
REPO=""
BRANCH=""
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   REPO="$2";   shift ;;
    --branch) BRANCH="$2"; shift ;;
    --target) TARGET="$2"; shift ;;
  esac
  shift
done

[ -z "$REPO" ] && { echo "CHECK|FAIL|missing --repo"; exit 1; }

path="$BASE/$REPO"

[ -z "$BRANCH" ] && BRANCH=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ] && { echo "CHECK|FAIL|could not detect current branch"; exit 1; }

# resolve_base comes from lib-branches.sh (single source of truth)

base="${TARGET:-$(resolve_base "$REPO" "$path")}"
[ -z "$base" ] && { echo "CHECK|FAIL|cannot resolve base branch for $REPO"; exit 1; }

# Range checks must use the REMOTE base ref. The local base branch is often stale, which makes
# "$base"..HEAD either find nothing (false "no commits") or count the target's own commits as
# branch commits (false commit-format failures). Fetch the base, then prefer origin/<base>.
git -C "$path" fetch origin "$base" -q 2>/dev/null
if git -C "$path" rev-parse --verify --quiet "origin/$base" >/dev/null; then
  BASE_REF="origin/$base"
else
  BASE_REF="$base"
fi

# ── 1. Branch name format ────────────────────────────────────────────────────
FEATURE_VERBS="Implement|Add|Update|Refactor|Remove|Migrate|Enable|Disable|Expose|Extract|Rename|Move|Replace"
if echo "$BRANCH" | grep -qE "^feature/PROJ-[0-9]+_(${FEATURE_VERBS})[_A-Za-z0-9]*$"; then
  echo "CHECK|PASS|branch name format valid (feature)"
elif echo "$BRANCH" | grep -qE '^bugfix/PROJ-[0-9]+_Fix[_A-Za-z0-9]*$'; then
  echo "CHECK|PASS|branch name format valid (bugfix)"
elif echo "$BRANCH" | grep -qE '^PROJ-[0-9]+-[A-Za-z0-9-]+$'; then
  echo "CHECK|PASS|branch name format valid (submodule repo: PROJ-XXXXX-desc)"
else
  echo "CHECK|FAIL|branch name invalid — expected: feature/PROJ-XXX_Verb_Title or bugfix/PROJ-XXX_Fix_Title (verbs: ${FEATURE_VERBS})"
fi

# ── 2. Commits: format and no body ──────────────────────────────────────────
commits=$(git -C "$path" log "$BASE_REF"..HEAD --format="%H" 2>/dev/null)
if [ -z "$commits" ]; then
  echo "CHECK|FAIL|no commits found on branch (base: $BASE_REF)"
else
  commit_ok=true
  while IFS= read -r sha; do
    subject=$(git -C "$path" log -1 --format="%s" "$sha")
    body=$(git -C "$path" log -1 --format="%b" "$sha" | grep -v '^[[:space:]]*$' | grep -v 'Co-Authored-By')
    echo "$subject" | grep -qE '^PROJ-[0-9]+ [A-Z].+' \
      || { echo "CHECK|FAIL|commit $(echo "$sha" | cut -c1-8): subject must be 'PROJ-XXX Capital...' — got: $subject"; commit_ok=false; }
    [ -n "$body" ] \
      && { echo "CHECK|FAIL|commit $(echo "$sha" | cut -c1-8): has a body (single line only) — body: $(echo "$body" | head -1)"; commit_ok=false; }
  done <<< "$commits"
  $commit_ok && echo "CHECK|PASS|all commit messages are correctly formatted"
fi

# ── 3. Shared submodule pointer must never be committed ─────────────────────
# A shared submodule / vendored dependency pointer must never ride along in a feature MR.
shared_in_commits=$(git -C "$path" log "$BASE_REF"..HEAD --oneline -- shared 2>/dev/null)
shared_staged=$(git -C "$path" diff --cached --name-only 2>/dev/null | grep -E "^shared$")

[ -n "$shared_in_commits" ] \
  && echo "CHECK|FAIL|shared submodule pointer found in commits — do not include this in the MR" \
  || echo "CHECK|PASS|no shared submodule pointer in commits"

[ -n "$shared_staged" ] \
  && echo "CHECK|FAIL|shared submodule pointer is staged — unstage it before creating MR" \
  || echo "CHECK|PASS|shared submodule pointer not staged"

# ── 4. MR URL ────────────────────────────────────────────────────────────────
# Derive the Git host + project path from the repo's own origin remote, so this works
# against whatever Git host you use rather than a hard-coded one.
remote_url=$(git -C "$path" remote get-url origin 2>/dev/null)
host=$(echo "$remote_url" | sed -E 's|^https?://||;s|^git@||;s|:.*$||;s|/.*$||')
repo_path=$(echo "$remote_url" | sed -E 's|^https?://[^/]+/||;s|^git@[^:]+:||;s|\.git$||')
encoded_branch=$(echo "$BRANCH" | sed 's|/|%2F|g')
encoded_base=$(echo "$base" | sed 's|/|%2F|g')
echo "URL|https://${host}/${repo_path}/-/merge_requests/new?merge_request%5Bsource_branch%5D=${encoded_branch}&merge_request%5Btarget_branch%5D=${encoded_base}"
