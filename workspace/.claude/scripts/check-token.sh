#!/usr/bin/env bash
# check-token.sh — verify the Git host token used for cloning + the MR skills.
#
# Reads ~/.claude/git-token locally and makes one cheap API call.
# Prints EXACTLY one status word to stdout (and nothing else):
#   OK       — token present and accepted by the Git host
#   MISSING  — file absent or empty
#   INVALID  — token present but rejected (expired / wrong scope / revoked)
#
# The token value is never printed, so it is safe to run as a tool call.

TOKEN_FILE="${HOME}/.claude/git-token"

if [ ! -s "$TOKEN_FILE" ]; then
  echo "MISSING"
  exit 0
fi

TOKEN=$(tr -d '\r\n' < "$TOKEN_FILE")
if [ -z "$TOKEN" ]; then
  echo "MISSING"
  exit 0
fi

if curl -sf -H "PRIVATE-TOKEN: $TOKEN" "https://git.example.com/api/v4/user" >/dev/null 2>&1; then
  echo "OK"
else
  echo "INVALID"
fi
