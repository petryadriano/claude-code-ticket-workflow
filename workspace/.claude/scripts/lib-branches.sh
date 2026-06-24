#!/usr/bin/env bash
# lib-branches.sh — single source of truth for the repo inventory and
# base/default-branch resolution. Source this file; do not execute it directly.
#
# Usage in a script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib-branches.sh"
#
# Previously this table was copy-pasted into create-branch.sh, prepare-mr.sh,
# sync-repos.sh, and rebase-branch.sh — and had already drifted (rebase-branch
# resolved versioned repos from origin/HEAD instead of the highest develop_X.YY,
# and was missing some repos). Edit branch mappings HERE only.

# Every top-level repo in the workspace (must match the table in the root CLAUDE.md).
# Replace with your own repo set.
ALL_REPOS="api web auth"

# resolve_base <repo> <path> — echo the repo's base/default branch.
#   Fixed-branch repos come from the table; versioned repos use the highest
#   develop_X.XX on origin; fallback reads remote HEAD WITHOUT mutating local
#   config (never `git remote set-head`).
resolve_base() {
  local repo="$1" path="$2"
  # Match on the basename so submodule paths resolve too (e.g. api/shared → shared).
  # Without this, api/shared fell through to the versioned-repo logic and picked the
  # highest develop_X.YY inside the shared repo (an ancient develop_2.2).
  case "${repo##*/}" in
    api)     echo "develop"; return ;;
    web)     echo "develop"; return ;;
    auth)    echo "develop"; return ;;
    shared)  echo "develop"; return ;;
  esac
  # Versioned repo: find highest develop_X.XX on remote — works regardless of current branch
  local latest
  latest=$(git -C "$path" branch -r 2>/dev/null \
    | sed 's|.*origin/||' \
    | grep -E '^develop_[0-9]+\.[0-9]+$' \
    | sed 's/^develop_//' \
    | sort -t. -k1,1n -k2,2n \
    | tail -1 \
    | sed 's/^/develop_/')
  [ -n "$latest" ] && echo "$latest" && return
  # fallback: read remote HEAD without modifying local config
  git -C "$path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'
}
