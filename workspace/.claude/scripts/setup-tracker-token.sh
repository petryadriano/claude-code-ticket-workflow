#!/usr/bin/env bash
# setup-tracker-token.sh — one-time setup so the lifecycle can auto-download tracker attachments.
#
# Stores tracker API-token credentials to ~/.tracker-creds (chmod 600), then VALIDATES them
# against the tracker's "current user" endpoint. The token is never echoed back. Pair with
# fetch-attachment.sh, which reads the same file.
#
# The USER runs this themselves (so the secret stays in their shell, not in a tool call), typically
# via the session's `!` prefix. Provide email + token as env vars OR as args:
#
#   !  TRACKER_EMAIL=you@example.com TRACKER_API_TOKEN=xxxxx bash .claude/scripts/setup-tracker-token.sh
#   !  bash .claude/scripts/setup-tracker-token.sh you@example.com xxxxx tracker.example.com
#
# Create the token first in your tracker's account / security settings (API tokens).
#
# Output (one status line; token NEVER printed):
#   OK|<displayName>|<host>     stored at ~/.tracker-creds and validated (HTTP 200)
#   BADAUTH|<code>|<host>       stored, but validation failed (401 bad token / 403 / etc.) — fix & rerun
#   USAGE|<hint>               missing email or token
# Exit: 0 OK, 5 BADAUTH, 2 USAGE.

set -uo pipefail

EMAIL="${1:-${TRACKER_EMAIL:-}}"
TOKEN="${2:-${TRACKER_API_TOKEN:-}}"
HOST="${3:-${TRACKER_SITE:-tracker.example.com}}"
CREDS="$HOME/.tracker-creds"

if [ -z "$EMAIL" ] || [ -z "$TOKEN" ]; then
  echo "USAGE|provide email + token via args or TRACKER_EMAIL/TRACKER_API_TOKEN env. Create an API token in your tracker's account/security settings."
  exit 2
fi

umask 077
printf 'email=%s\ntoken=%s\nhost=%s\n' "$EMAIL" "$TOKEN" "$HOST" > "$CREDS"
chmod 600 "$CREDS" 2>/dev/null

# Validate without printing the token. The "current user" endpoint returns 200 + the account when creds are good.
name="$(curl -sS -u "$EMAIL:$TOKEN" -H "Accept: application/json" \
        "https://$HOST/rest/api/3/myself" 2>/dev/null \
        | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).displayName||"")}catch(e){}})' 2>/dev/null)"

if [ -n "$name" ]; then
  echo "OK|$name|$HOST"
  exit 0
fi

code="$(curl -sS -o /dev/null -w '%{http_code}' -u "$EMAIL:$TOKEN" \
        "https://$HOST/rest/api/3/myself" 2>/dev/null || true)"
echo "BADAUTH|${code:-000}|$HOST — creds saved to $CREDS but validation failed; recheck email/token and rerun"
exit 5
