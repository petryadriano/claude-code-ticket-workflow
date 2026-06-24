#!/usr/bin/env bash
# update-standards.sh — check (and optionally fast-forward) the shared standards-repo clone.
#
# The workspace's skills/scripts are junctioned to one standards-repo clone; pulling that
# clone updates every workspace at once. Run this at the START of a top-level skill
# (complete-ticket / review Step 0) — never mid-lifecycle.
#
# Usage: update-standards.sh [--pull]
#   (no flag) report only;  --pull  fast-forward if behind and clean.
#
# Reads the clone path from <workspace>/.claude/standards-root (written by /setup).
#
# Output (pipe-delimited, one line):
#   NOMARKER|<note>            no standards-root marker — not linked to a standards clone
#   UPTODATE|<branch>          already current
#   BEHIND|<n>|<branch>        n commits behind upstream — a pull is recommended
#   DIRTY|<branch>             clone has uncommitted changes (e.g. pending improve-skills edits)
#   PULLED|<branch>|<commit>   (with --pull) fast-forwarded
#   PULLFAIL|<msg>             (with --pull) could not fast-forward

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$SCRIPT_DIR/../.." && pwd)"
MARKER="$WS/.claude/standards-root"

[ -f "$MARKER" ] || { echo "NOMARKER|no standards-root marker in $WS/.claude"; exit 0; }
STD="$(tr -d '\r\n' < "$MARKER")"
[ -n "$STD" ] && [ -d "$STD/.git" ] || { echo "NOMARKER|standards-root '$STD' is not a git repo"; exit 0; }

branch="$(git -C "$STD" rev-parse --abbrev-ref HEAD 2>/dev/null)"

# Uncommitted changes in the clone? Never auto-pull over them.
if [ -n "$(git -C "$STD" status --porcelain 2>/dev/null)" ]; then
  echo "DIRTY|$branch"
  exit 0
fi

git -C "$STD" fetch -q origin 2>/dev/null
if ! git -C "$STD" rev-parse --symbolic-full-name "@{u}" >/dev/null 2>&1; then
  echo "UPTODATE|$branch (no upstream)"
  exit 0
fi
behind="$(git -C "$STD" rev-list --count "HEAD..@{u}" 2>/dev/null)"
[ -z "$behind" ] && behind=0

if [ "${1:-}" = "--pull" ]; then
  if [ "$behind" -gt 0 ]; then
    if git -C "$STD" merge --ff-only "@{u}" -q 2>/dev/null; then
      echo "PULLED|$branch|$(git -C "$STD" log -1 --oneline 2>/dev/null)"
    else
      echo "PULLFAIL|$branch is not fast-forwardable — resolve manually in $STD"
    fi
  else
    echo "UPTODATE|$branch"
  fi
  exit 0
fi

if [ "$behind" -gt 0 ]; then
  echo "BEHIND|$behind|$branch"
else
  echo "UPTODATE|$branch"
fi
