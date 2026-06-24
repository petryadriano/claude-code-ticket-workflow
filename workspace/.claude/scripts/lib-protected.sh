#!/usr/bin/env bash
# lib-protected.sh — shared helpers for preserving personal dev config files
# across git operations. Source this file; do not execute it directly.
#
# Usage in a script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib-protected.sh"
#   protected_tmp=$(mktemp -d)
#   save_protected "$repo_path" "$protected_tmp"
#   ... git operations ...
#   restore_protected "$repo_path" "$protected_tmp"

# Files matching this pattern are personal dev config — never committed, always preserved.
# Replace these globs with whatever local-only config your stack produces (IDE settings,
# local run profiles, lockfiles, certs, the .claude/ workspace dir, etc.).
NOISE_PATTERN="(launchSettings\.json|appsettings.*\.json|\.claude/|certs/|package-lock\.json|\.user)"

# Exclude noise files from the dirty check so they don't trigger a stash.
is_dirty() {
  git -C "$1" status --porcelain --ignore-submodules=all 2>/dev/null \
    | grep -Ev "$NOISE_PATTERN"
}

# Snapshot every modified/untracked file matching NOISE_PATTERN into $tmpdir.
# Uses NUL-delimited porcelain (-z) so paths with spaces and renames parse correctly
# (line-wise output quotes spaced paths and emits renames as "old -> new", both of
# which broke the previous sed-based parsing).
save_protected() {
  local repo_path="$1" tmpdir="$2"
  local entry status file orig dest
  while IFS= read -r -d '' entry; do
    [ -z "$entry" ] && continue
    status="${entry:0:2}"
    file="${entry:3}"
    # Renames/copies emit a second NUL-record (the original path) — consume and ignore it.
    case "$status" in
      *R*|*C*) IFS= read -r -d '' orig ;;
    esac
    printf '%s' "$file" | grep -qE "$NOISE_PATTERN" || continue
    [ -f "$repo_path/$file" ] || continue
    dest="$tmpdir/$file"
    mkdir -p "$(dirname "$dest")"
    cp "$repo_path/$file" "$dest" 2>/dev/null
  done < <(git -C "$repo_path" status --porcelain --ignore-submodules=all -z 2>/dev/null)
}

# Restore all files from $tmpdir back to the repo, then remove tmpdir.
# Protected files always win over whatever git checked out.
restore_protected() {
  local repo_path="$1" tmpdir="$2"
  [ -d "$tmpdir" ] || return
  find "$tmpdir" -type f 2>/dev/null | while IFS= read -r tmpfile; do
    local rel="${tmpfile#${tmpdir}/}"
    mkdir -p "$repo_path/$(dirname "$rel")"
    cp "$tmpfile" "$repo_path/$rel"
  done
  rm -rf "$tmpdir"
}
