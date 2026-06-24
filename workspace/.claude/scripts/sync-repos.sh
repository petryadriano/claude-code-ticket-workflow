#!/usr/bin/env bash
# sync-repos.sh — workspace repo sync script
#
# Usage: sync-repos.sh [--repos "r1 r2"]
#
# Clones any missing repos first, then auto-stashes dirty repos, syncs to latest, pops stash after.
#
# Output lines (pipe-delimited):
#   CLONE|repo|message      (repo folder was missing and was freshly cloned)
#   OK|repo|branch|commit
#   SUB|repo|submodule|branch|commit
#   WARN|repo|message
#   ERROR|repo|message
#   CONFLICT|repo|message   (stash pop had conflicts — user must resolve)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib-branches.sh"   # provides ALL_REPOS + resolve_base
TARGET_REPOS="$ALL_REPOS"
# Base URL of your Git host's group/namespace where the repos live. Override as needed.
GIT_HOST_BASE="https://git.example.com/your-group"

while [ $# -gt 0 ]; do
  case "$1" in
    --repos) TARGET_REPOS="$2"; shift ;;
    --root)  BASE="$2";         shift ;;   # provision into an explicit workspace root (used by /setup)
  esac
  shift
done

# ── helpers ──────────────────────────────────────────────────────────────────
source "$(dirname "${BASH_SOURCE[0]}")/lib-protected.sh"

# resolve_base comes from lib-branches.sh (single source of truth)

# auto-stash if dirty, checkout branch, pull, pop stash
# emits OK|label|branch|commit, CONFLICT|label|..., ERROR|label|..., or nothing on skip
safe_sync() {
  local path="$1" branch="$2" label="$3"

  # Snapshot protected files before any git operation — restored unconditionally at exit
  local protected_tmp
  protected_tmp=$(mktemp -d)
  save_protected "$path" "$protected_tmp"

  local stashed=false
  if [ -n "$(is_dirty "$path")" ]; then
    git -C "$path" stash --include-untracked -q 2>/dev/null \
      && stashed=true \
      || { restore_protected "$path" "$protected_tmp"; echo "ERROR|$label|stash failed"; return 1; }
  fi

  git -C "$path" checkout "$branch" -q 2>/dev/null \
    || { $stashed && git -C "$path" stash pop -q 2>/dev/null; restore_protected "$path" "$protected_tmp"; echo "ERROR|$label|checkout $branch failed"; return 1; }

  local pull_err
  pull_err=$(git -C "$path" pull 2>&1)
  if [ $? -ne 0 ]; then
    $stashed && git -C "$path" stash pop -q 2>/dev/null
    restore_protected "$path" "$protected_tmp"
    echo "ERROR|$label|pull failed: $(echo "$pull_err" | head -1)"
    return 1
  fi

  if $stashed; then
    git -C "$path" stash pop 2>/dev/null
    if [ $? -ne 0 ]; then
      restore_protected "$path" "$protected_tmp"
      echo "CONFLICT|$label|stash pop had conflicts — your changes are preserved in the stash"
      return 1
    fi
  fi

  # Always restore protected files last — they win over whatever git checked out
  restore_protected "$path" "$protected_tmp"

  echo "OK|$label|$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)|$(git -C "$path" log -1 --oneline 2>/dev/null)"
}

sync_sub() {
  local parent="$1" name="$2" rel_path="$3" branch="$4" label="$5"
  local full="$parent/$rel_path"
  git -C "$full" rev-parse --git-dir >/dev/null 2>&1 || return
  # safe_sync emits  OK|<label>|<branch>|<commit>  (or ERROR|/CONFLICT|). Reformat to the
  # documented 5-field submodule line, injecting the submodule NAME that safe_sync doesn't know:
  #   SUB|<repo>|<submodule>|<branch>|<commit>
  safe_sync "$full" "$branch" "$label" | while IFS='|' read -r kind lbl rest; do
    case "$kind" in
      OK)                printf 'SUB|%s|%s|%s\n'  "$lbl" "$name" "$rest" ;;
      ERROR|CONFLICT)    printf 'WARN|%s|%s|%s\n' "$lbl" "$name" "$rest" ;;
      *)                 printf '%s|%s|%s\n'      "$kind" "$lbl" "$rest" ;;
    esac
  done
}

# Progress goes to STDERR with a ":: " prefix so it streams live to the terminal (both /setup and
# /sync-repos run this as a foreground Bash command) without polluting the pipe-delimited result
# lines that callers parse from STDOUT.
progress() { printf ':: %s\n' "$1" >&2; }

# ── Phase 0: clone any missing repos ─────────────────────────────────────────
missing=""
for repo in $TARGET_REPOS; do
  git -C "$BASE/$repo" rev-parse --git-dir >/dev/null 2>&1 || missing="$missing $repo"
done
miss_total=$(echo $missing | wc -w)
[ "$miss_total" -gt 0 ] && progress "cloning $miss_total missing repo(s) — this is the slow part …"
miss_i=0
for repo in $missing; do
  miss_i=$((miss_i + 1))
  progress "[$miss_i/$miss_total] cloning $repo (with submodules) …"
  clone_err=$(git clone --recurse-submodules -q "$GIT_HOST_BASE/$repo.git" "$BASE/$repo" 2>&1)
  if [ $? -eq 0 ]; then
    echo "CLONE|$repo|cloned from $GIT_HOST_BASE/$repo.git"
    progress "    $repo cloned"
  else
    # Surface the real git error (auth / permission / not-found) instead of swallowing it.
    echo "ERROR|$repo|clone failed: $(printf '%s' "$clone_err" | head -1) — check access to $GIT_HOST_BASE/$repo.git"
    progress "    $repo FAILED to clone"
  fi
done

# ── Phase A: parallel fetch (repos + known submodule paths) ──────────────────
progress "fetching latest for all repos …"
for repo in $TARGET_REPOS; do
  git -C "$BASE/$repo" fetch origin -q 2>/dev/null &
done
# also prefetch nested submodule remotes that are already initialized
for repo in $TARGET_REPOS; do
  [ -f "$BASE/$repo/.gitmodules" ] && git -C "$BASE/$repo" submodule foreach --quiet \
    'git fetch origin -q 2>/dev/null' 2>/dev/null &
done
wait

# ── Phase B: sequential sync ─────────────────────────────────────────────────
for repo in $TARGET_REPOS; do
  path="$BASE/$repo"
  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || continue   # skip missing repos (a failed clone was already reported in Phase 0)

  progress "syncing $repo …"
  default_branch=$(resolve_base "$repo" "$path")
  [ -z "$default_branch" ] && { echo "ERROR|$repo|cannot resolve default branch"; continue; }

  safe_sync "$path" "$default_branch" "$repo" || continue

  # submodules
  if [ -f "$path/.gitmodules" ]; then
    progress "  updating $repo submodules …"
    sub_err=$(git -C "$path" submodule update --init 2>&1) \
      || echo "WARN|$repo|submodule init failed: $(printf '%s' "$sub_err" | head -1)"
    # A shared submodule / vendored dependency tracked at the repo root.
    sync_sub "$path" "shared" "shared" "develop" "$repo"
    # EXAMPLE — replace with your app's own nested-submodule layout. The "web" repo here
    # demonstrates a repo whose UI submodule itself carries further nested submodules.
    if [ "$repo" = "web" ]; then
      sync_sub "$path" "ui"  "ui"  "develop" "$repo"
      sub_err=$(git -C "$path/ui" submodule update --init 2>&1) \
        || echo "WARN|$repo/ui|submodule init failed: $(printf '%s' "$sub_err" | head -1)"
      sync_sub "$path/ui" "ui-core"   "ui-core"   "main"    "$repo/ui"
      sync_sub "$path/ui" "ui-common" "ui-common" "develop" "$repo/ui"
    fi
  fi
done
