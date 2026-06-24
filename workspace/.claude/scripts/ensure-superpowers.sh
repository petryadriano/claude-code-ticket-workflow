#!/usr/bin/env bash
# ensure-superpowers.sh — make the Superpowers plugin present on this machine so the
# lifecycle's `REQUIRED: superpowers:*` substrate can load. Called by /setup Step 0b.
#
# WHY A SCRIPT: /setup only ever runs `bash <script>` (pre-approved via Bash(bash *)), and the
# `claude` CLI installs plugins NON-INTERACTIVELY — unlike the `/plugin` slash command, which
# Claude cannot invoke (slash commands don't give the model a turn). So this does, hands-off,
# what the user used to have to type by hand.
#
# WHAT IT DOES NOT DO: it does not *activate* the plugin in the running session. Plugins load at
# session start, so after this succeeds the user must still `/reload-plugins` or restart. And it
# does not *enable* the plugin — enablement is declared by the repo's committed settings.json
# (enabledPlugins); this script only puts the plugin ON DISK.
#
# Always installs at USER scope. We deliberately do NOT short-circuit on "already installed":
# `claude plugin list` reports installs across ALL projects, so a `local`-scope install belonging
# to a *different* checkout would make a naive check pass while leaving the current context with
# nothing loadable. A user-scope install applies everywhere and `claude plugin install` is
# idempotent, so installing unconditionally is both correct and cheap (the gate fires rarely).
#
# Progress (human) → stderr, ":: " prefixed (so /setup can stream it live).
# Result (machine) → stdout; the final line is exactly one of:
#   SUPERPOWERS|installed       — present on disk (user scope), ready to activate on reload/restart
#   SUPERPOWERS|nocli           — `claude` CLI not on PATH; caller should fall back to manual install
#   SUPERPOWERS|failed|<reason> — install was attempted but returned an error

PLUGIN="superpowers@claude-plugins-official"
MARKET="anthropics/claude-plugins-official"

if ! command -v claude >/dev/null 2>&1; then
  printf ':: `claude` CLI not found on PATH — cannot auto-install\n' >&2
  echo "SUPERPOWERS|nocli"
  exit 0
fi

printf ':: ensuring marketplace %s …\n' "$MARKET" >&2
claude plugin marketplace add "$MARKET" >&2 || true   # idempotent; non-fatal if already present

printf ':: installing %s (scope: user) …\n' "$PLUGIN" >&2
if claude plugin install "$PLUGIN" --scope user >&2; then
  printf ':: superpowers installed at user scope (activate with /reload-plugins or a restart)\n' >&2
  echo "SUPERPOWERS|installed"
else
  printf ':: install returned an error — falling back to manual\n' >&2
  echo "SUPERPOWERS|failed|claude plugin install returned nonzero"
fi
