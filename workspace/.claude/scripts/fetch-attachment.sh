#!/usr/bin/env bash
# fetch-attachment.sh — download a tracker attachment by id so the model can Read it.
#
# WHY THIS EXISTS: tracker attachment *binaries* are auth-gated. The tracker's MCP server may
# expose NO attachment-download tool, its `fetch` tool only takes issue/page identifiers, and
# its MCP resources are only UI widgets. An anonymous GET returns HTTP 403. The one working path is
# the documented tracker REST Basic-auth flow: `email:api_token` on the attachment content
# endpoint, which 302-redirects to a short-lived signed media URL (`-L` follows it to the bytes).
#
# After this downloads the file, the caller reads it with the Read tool (which renders images),
# so the image is actually *seen* — no "please paste it" needed when a token is configured.
#
# CREDENTIALS (first found wins; never echoed):
#   1. env  TRACKER_EMAIL + TRACKER_API_TOKEN  (+ optional TRACKER_SITE)
#   2. file $HOME/.tracker-creds  with lines:  email=...  token=...  host=...(optional)
# Create a token in your tracker's account / security settings (API tokens).
# Keep the creds file OUT of any git repo ($HOME is safe); chmod 600 it.
#
# Usage:   fetch-attachment.sh <attachmentId> <outPath> [siteHost]
# Output:  one status line on stdout:
#   OK|<outPath>                 downloaded — caller should Read <outPath>
#   NOAUTH|<hint>                no credentials configured — caller falls back to asking the user
#   HTTP_<code>|<host>           server refused even with creds (e.g. 401 bad token, 403 no access)
# Exit:    0 on OK, 3 on NOAUTH, 4 on HTTP failure, 2 on bad args.

set -uo pipefail

ID="${1:-}"; OUT="${2:-}"; HOST_ARG="${3:-}"
[ -n "$ID" ] && [ -n "$OUT" ] || { echo "USAGE|fetch-attachment.sh <attachmentId> <outPath> [siteHost]"; exit 2; }

CREDS="$HOME/.tracker-creds"
EMAIL="${TRACKER_EMAIL:-}"; TOKEN="${TRACKER_API_TOKEN:-}"; HOST="${TRACKER_SITE:-}"
if { [ -z "$EMAIL" ] || [ -z "$TOKEN" ]; } && [ -f "$CREDS" ]; then
  [ -z "$EMAIL" ] && EMAIL="$(sed -n 's/^email=//p'  "$CREDS" | head -1 | tr -d '\r')"
  [ -z "$TOKEN" ] && TOKEN="$(sed -n 's/^token=//p'  "$CREDS" | head -1 | tr -d '\r')"
  [ -z "$HOST"  ] && HOST="$(sed -n  's/^host=//p'   "$CREDS" | head -1 | tr -d '\r')"
fi
[ -n "$HOST_ARG" ] && HOST="$HOST_ARG"
[ -n "$HOST" ] || HOST="tracker.example.com"

if [ -z "$EMAIL" ] || [ -z "$TOKEN" ]; then
  echo "NOAUTH|set TRACKER_EMAIL+TRACKER_API_TOKEN or create $CREDS (email=/token=). Create a token in your tracker's account/security settings."
  exit 3
fi

mkdir -p "$(dirname "$OUT")" 2>/dev/null

# Try the site host (documented Basic-auth path).
for url in \
  "https://$HOST/rest/api/3/attachment/content/$ID" ; do
  code="$(curl -sS -L --fail-with-body -u "$EMAIL:$TOKEN" -H "Accept: */*" \
          -w '%{http_code}' -o "$OUT" "$url" 2>/dev/null || true)"
  if [ "$code" = "200" ] && [ -s "$OUT" ]; then
    echo "OK|$OUT"
    exit 0
  fi
done

rm -f "$OUT" 2>/dev/null
echo "HTTP_${code:-000}|$HOST — Basic-auth download refused (check token scope / attachment access)"
exit 4
