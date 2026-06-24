#!/usr/bin/env bash
# ensure-e2e.sh — provision the e2e verification harness into THIS workspace on first use.
#
# The harness scaffold (Playwright config + core fixtures + domain modules + build-env /
# extract-evidence) is maintained ONCE in the standards repo at workspace/e2e/. /setup deliberately
# does NOT install it (keeps setup fast). This copies the scaffold into $WORKSPACE_ROOT/e2e and installs
# deps the first time a ticket needs an AUTO spec. Idempotent: a no-op once set up.
#
# It does NOT build .env — that needs valid cloud credentials + an environment user + the developer's
# creds, so it is the human-finish step; the script prints exactly how.
#
# Result (stdout, final line is exactly one of):
#   E2E|ready             — harness present, deps installed, .env present → specs can run
#   E2E|needsenv|<hint>   — harness + deps present, but .env not built yet (run build-env.mjs)
#   E2E|installed         — scaffold just copied + deps installed AND .env already present
#   E2E|noscaffold|<why>  — standards scaffold not found (workspace not /setup-provisioned?)
#   E2E|failed|<why>      — copy or npm install failed
# Progress → stderr (":: " prefixed) so /implement-ticket can stream it live like /sync-repos.

set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
E2E="$WORKSPACE_ROOT/e2e"
progress() { printf ':: %s\n' "$1" >&2; }

# Locate the standards scaffold via the standards-root marker (written by /setup); fall back to
# walking up from the (junctioned) scripts dir.
MARKER="$WORKSPACE_ROOT/.claude/standards-root"
if [ ! -f "$MARKER" ]; then
  # The standards clone is only locatable via this marker (the .claude junction target is not
  # recoverable from pwd). No marker → not /setup-provisioned → can't find the scaffold.
  echo "E2E|noscaffold|no standards-root marker at $MARKER (workspace not provisioned by /setup?)"
  exit 0
fi
STD="$(tr -d '\r\n' < "$MARKER")"
SCAFFOLD="$STD/workspace/e2e"

# 1 — copy the scaffold if this workspace has no harness yet
if [ ! -d "$E2E" ]; then
  if [ ! -d "$SCAFFOLD" ]; then
    echo "E2E|noscaffold|no scaffold at $SCAFFOLD (is this workspace provisioned by /setup?)"
    exit 0
  fi
  progress "provisioning e2e harness from $SCAFFOLD …"
  cp -R "$SCAFFOLD" "$E2E" || { echo "E2E|failed|copy from $SCAFFOLD failed"; exit 1; }
fi

# 1b — keep SHARED scaffold files in sync even when $E2E already exists, so scaffold improvements (new
# fixtures, config/helper fixes) reach EXISTING workspaces on the next ticket. Workspace-LOCAL files are
# never touched: tests/, .env, node_modules, package-lock.json. (package.json is left alone too — a
# dependency change is rare and would need a deliberate npm ci, not a silent overwrite.)
if [ -d "$SCAFFOLD" ]; then
  progress "syncing shared e2e scaffold files (fixtures/config/helpers) …"
  mkdir -p "$E2E/fixtures"
  cp -f "$SCAFFOLD"/fixtures/*.ts "$E2E/fixtures/" 2>/dev/null || true
  for f in playwright.config.ts build-env.mjs extract-evidence.mjs README.md .env.example .gitignore; do
    [ -f "$SCAFFOLD/$f" ] && cp -f "$SCAFFOLD/$f" "$E2E/$f"
  done
fi

# 2 — install deps if missing (one-time; the slow part)
installed=false
if [ ! -d "$E2E/node_modules" ]; then
  if [ -f "$E2E/package-lock.json" ]; then
    progress "installing e2e dependencies (one-time: npm ci) …"
    ( cd "$E2E" && npm ci ) >&2 || { echo "E2E|failed|npm ci failed"; exit 1; }
  else
    progress "installing e2e dependencies (one-time: npm install) …"
    ( cd "$E2E" && npm install ) >&2 || { echo "E2E|failed|npm install failed"; exit 1; }
  fi
  installed=true
fi

# 2b — Playwright browser for UI specs (best-effort). API/DB specs don't need it; UI specs do.
# Idempotent (Playwright skips if already present). A failure here is non-fatal — UI specs would
# then fail with Playwright's own "run playwright install" message; API/DB specs are unaffected.
if $installed; then
  progress "installing Playwright chromium (one-time, for UI specs) …"
  ( cd "$E2E" && npx --yes playwright install chromium ) >&2 || progress "WARN: 'playwright install chromium' failed — UI specs need it; API/DB specs are unaffected."
fi

# 3 — .env is the human-finish step (needs valid cloud credentials + an environment user + creds)
if [ ! -f "$E2E/.env" ]; then
  progress "e2e harness ready, but .env is not built yet — build it ONCE for this workspace (reused for every ticket):"
  progress "  cd \"$E2E\"  &&  node build-env.mjs <environment> <user> [--with=<domain>]   # prompts your password (stored gitignored)"
  progress "  (<environment> = the ticket's test_scope target environment; uses your existing cloud credentials — refresh them only if it errors)"
  echo "E2E|needsenv|run build-env.mjs in $E2E"
  exit 0
fi

$installed && echo "E2E|installed" || echo "E2E|ready"
