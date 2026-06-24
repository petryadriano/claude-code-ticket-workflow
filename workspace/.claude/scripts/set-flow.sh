#!/usr/bin/env bash
# set-flow.sh — surgically patch ONLY the `flow` field of a ticket's state file.
#
# Why this exists: a flow checkpoint changes one field, but the full save path
# (Write the whole JSON + save-state.sh) makes the model regenerate the ENTIRE state
# document every time — slow and token-heavy on a large ticket. This patches `flow`
# in place via node (every other field untouched) and stamps `flow.updated_at` itself,
# so a checkpoint costs a one-line command instead of a full-document rewrite.
#
# It's a PLAIN `bash … args` command (no heredoc/redirect/`&&`), and it touches
# .claude/tickets/, so it is auto-approved and never prompts.
#
# Creates the state file if it does not exist yet (initialised to `{ticket, flow}`).
# This matters because understand-ticket sets its FIRST flow checkpoint BEFORE the full
# state file is written (the full state is saved only after the understanding gate) — so
# the early checkpoint must be able to create the stub. A later full `save-state` overwrites
# it with the complete document.
#
# Usage:
#   bash set-flow.sh <ticket> <active_skill> <step> <step_label>   # set/replace flow
#   bash set-flow.sh <ticket> --clear                              # set flow = null
#
# Use the full save path (Write temp + `save-state.sh <ticket> <file>`) only when real
# CONTENT changes (a phase transition, new ACs/plan/etc.) — not for flow ticks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"

TICKET="${1:-}"
if [ -z "$TICKET" ]; then
  echo "usage: set-flow.sh <ticket> <active_skill> <step> <step_label>   |   set-flow.sh <ticket> --clear" >&2
  exit 2
fi
case "$TICKET" in
  */*|*\\*|*..*) echo "error: invalid ticket id '$TICKET' (no '/', '\\', or '..')" >&2; exit 2 ;;
esac

TICKETS_DIR="$BASE/.claude/tickets"
TARGET="$TICKETS_DIR/$TICKET.json"
mkdir -p "$TICKETS_DIR"

if [ "${2:-}" = "--clear" ]; then
  node -e 'const f=require("fs"),p=process.argv[1],t=process.argv[2];const o=f.existsSync(p)?JSON.parse(f.readFileSync(p,"utf8")):{ticket:t};o.flow=null;f.writeFileSync(p,JSON.stringify(o,null,2));' "$TARGET" "$TICKET"
else
  SKILL="${2:-}"; STEP="${3:-}"; LABEL="${4:-}"
  if [ -z "$SKILL" ] || [ -z "$STEP" ] || [ -z "$LABEL" ]; then
    echo "usage: set-flow.sh <ticket> <active_skill> <step> <step_label>   |   set-flow.sh <ticket> --clear" >&2
    exit 2
  fi
  node -e 'const f=require("fs"),p=process.argv[1],t=process.argv[2];const o=f.existsSync(p)?JSON.parse(f.readFileSync(p,"utf8")):{ticket:t};o.flow={active_skill:process.argv[3],step:Number(process.argv[4]),step_label:process.argv[5],updated_at:new Date().toISOString()};f.writeFileSync(p,JSON.stringify(o,null,2));' "$TARGET" "$TICKET" "$SKILL" "$STEP" "$LABEL"
fi

echo "$TARGET"
