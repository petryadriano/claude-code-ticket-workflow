#!/usr/bin/env bash
# append-journal.sh — append a dense, timestamped entry to a ticket's context journal.
#
# The journal is an append-only sidecar to the JSON state file. It holds the three
# things the JSON does NOT capture and that evaporate on context compaction:
# decisions (with WHY), dead-ends (tried + failed, so we don't retry), and open
# questions. Task state, plan, and file lists live in <ticket>.json — never duplicate
# them here.
#
# Usage:
#   append-journal.sh <ticket> <DECISION|DEADEND|QUESTION|RESOLVED|NOTE> "<one-line text>"
#
# Examples:
#   append-journal.sh PROJ-123 DECISION "Chose scoped lifetime for IFooService — matches every other service in the composition root"
#   append-journal.sh PROJ-123 DEADEND  "Tried adding nav prop on Foo; the ORM threw cyclic-ref on save. Reverted — use explicit join instead"
#   append-journal.sh PROJ-123 QUESTION "Unclear which transaction scope the finally-block persist runs in"
#   append-journal.sh PROJ-123 RESOLVED "Transaction scope → user said reuse the outer UoW"
#
# Output: prints the journal path on success. Warns on stderr (does not fail) when the
# entry count passes the soft cap — that is Claude's cue to prune RESOLVED/low-value lines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"

TICKET="${1:-}"
TYPE="${2:-}"
TEXT="${3:-}"

# Tolerant parse: accept the type glued to the text as one arg ("NOTE: text…") —
# a common caller slip; auto-split instead of burning a round-trip on the usage error.
if [ -z "$TEXT" ]; then
  case "$TYPE" in
    DECISION:*|DEADEND:*|QUESTION:*|RESOLVED:*|NOTE:*)
      TEXT="$(printf '%s' "${TYPE#*:}" | sed -e 's/^[[:space:]]*//')"
      TYPE="${TYPE%%:*}"
      ;;
  esac
fi

if [ -z "$TICKET" ] || [ -z "$TYPE" ] || [ -z "$TEXT" ]; then
  echo "usage: append-journal.sh <ticket> <DECISION|DEADEND|QUESTION|RESOLVED|NOTE> \"<text>\"" >&2
  exit 2
fi

case "$TYPE" in
  DECISION|DEADEND|QUESTION|RESOLVED|NOTE) ;;
  *)
    echo "error: type must be one of DECISION|DEADEND|QUESTION|RESOLVED|NOTE (got '$TYPE')" >&2
    exit 2
    ;;
esac

JOURNAL="$BASE/.claude/tickets/$TICKET.journal.md"
SOFT_CAP=120

mkdir -p "$BASE/.claude/tickets"

if [ ! -f "$JOURNAL" ]; then
  {
    printf '# %s journal\n' "$TICKET"
    printf '# Append-only context journal: decisions (+why), dead-ends, open questions.\n'
    printf '# Read on resume after compaction. Honor DEADENDs (do not retry). One dense line per entry.\n'
    printf '# Structured state (phase, plan, files) lives in %s.json - not here.\n\n' "$TICKET"
  } > "$JOURNAL"
fi

# Collapse any newlines in the text so each entry stays a single line.
CLEAN_TEXT="$(printf '%s' "$TEXT" | tr '\n' ' ' | tr -s ' ')"
STAMP="$(date -u +%Y-%m-%dT%H:%MZ)"

printf -- '- [%s] %s: %s\n' "$STAMP" "$TYPE" "$CLEAN_TEXT" >> "$JOURNAL"

ENTRY_COUNT="$(grep -c '^- \[' "$JOURNAL" 2>/dev/null || true)"
ENTRY_COUNT="${ENTRY_COUNT:-0}"
if [ "$ENTRY_COUNT" -gt "$SOFT_CAP" ]; then
  echo "warning: $TICKET journal has $ENTRY_COUNT entries (cap $SOFT_CAP) — prune RESOLVED/stale lines to keep recovery cheap." >&2
fi

echo "$JOURNAL"
