#!/usr/bin/env bash
# provision-workspaces.sh — create + wire one or more workspaces, then clone/sync every repo.
#
# Consolidates what /setup used to do as a dozen separate inline commands into ONE script,
# so the skill only ever runs `bash <this>` (a single pre-approved command family) and the
# user is not prompted to approve each step.
#
# Usage:
#   provision-workspaces.sh --std <STD_ROOT> --root <ROOT> --names "ws1 ws2 ws3" [--skip-sync]
#
# OS-agnostic: links with a directory junction on Windows (Git Bash, no admin needed) and a
# symlink on macOS/Linux — the result is identical. It is idempotent and NEVER touches a
# workspace that already has content (your other sessions are safe).
#
# Human-readable PROGRESS goes to STDERR, each line prefixed ":: " (this is what /setup streams
# live to the terminal so the slow clone is no longer silent — /setup runs this as a foreground
# Bash command, one per workspace, so the full output scrolls just like /sync-repos).
# Machine-readable RESULT lines go to STDOUT:
#   WS|<name>|created|<ws-path>
#   WS|<name>|skipped|already exists
#   …followed by sync-repos.sh result lines for that workspace (CLONE|, OK|, SUB|, WARN|, ERROR|, CONFLICT|)
# The final stdout line is always:  SETUP_DONE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STD="" ; ROOT="" ; NAMES="" ; SKIP_SYNC=false
while [ $# -gt 0 ]; do
  case "$1" in
    --std)       STD="$2"   ; shift ;;
    --root)      ROOT="$2"  ; shift ;;
    --names)     NAMES="$2" ; shift ;;
    --skip-sync) SKIP_SYNC=true ;;
  esac
  shift
done

if [ -z "$STD" ] || [ -z "$ROOT" ] || [ -z "$NAMES" ]; then
  echo "ERROR|args|--std, --root and --names are all required"
  echo "SETUP_DONE"
  exit 2
fi

STD="${STD%/}"          # strip a trailing slash
ROOT="${ROOT%/}"

is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT) return 0 ;;
    *) return 1 ;;
  esac
}

# Convert any path form (/c/foo, C:/foo, C:\foo) to a real Windows path for the mklink call.
# cygpath ships with Git Bash; the sed fallback covers the rare case it is absent.
winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1" | sed -E 's#^/([a-zA-Z])/#\1:/#' | sed 's|/|\\|g'
  fi
}

# link_dir <target> <linkpath> <label> — junction on Windows, symlink elsewhere. Leaves an existing link/dir as-is.
# Windows: use PowerShell's `New-Item -ItemType Junction` (no admin needed). We deliberately do NOT
# shell out to `cmd //c mklink` — under Git Bash/MSYS the `/J` switch is rewritten as a Unix path and
# `//c` is fragile, so mklink silently fails. Verify the link resolved and emit WARN| if it did not,
# so a broken link surfaces in the live stream instead of being swallowed (the original bug).
link_dir() {
  local target="$1" link="$2" label="$3"
  if [ -e "$link" ]; then
    return 0
  fi
  if is_windows; then
    powershell.exe -NoProfile -NonInteractive -Command \
      "New-Item -ItemType Junction -Path '$(winpath "$link")' -Target '$(winpath "$target")' | Out-Null" >/dev/null 2>&1
  else
    ln -s "$target" "$link" 2>/dev/null
  fi
  if [ ! -e "$link" ]; then
    echo "WARN|${label:-link}|failed to create link: $link"
  fi
}

# import_path <std> <ws> — path for the @import in the workspace CLAUDE.md.
# Relative (../<std-folder>/CLAUDE.md) when std and ws share a parent (the common case),
# else the absolute path to <std>/CLAUDE.md.
import_path() {
  local std="$1" ws="$2"
  local parent_ws parent_std std_base
  parent_ws="$(cd "$(dirname "$ws")" 2>/dev/null && pwd)"
  parent_std="$(cd "$(dirname "$std")" 2>/dev/null && pwd)"
  std_base="$(basename "$std")"
  if [ -n "$parent_ws" ] && [ "$parent_ws" = "$parent_std" ]; then
    printf '../%s/CLAUDE.md' "$std_base"
  else
    printf '%s/CLAUDE.md' "$std"
  fi
}

total=$(echo $NAMES | wc -w)
idx=0
for name in $NAMES; do
  idx=$((idx + 1))
  WS="$ROOT/$name"
  printf ':: ===== Workspace %s (%d/%d) =====\n' "$name" "$idx" "$total" >&2

  # 2a — never clobber live work
  if [ -d "$WS" ] && [ -n "$(ls -A "$WS" 2>/dev/null)" ]; then
    printf '::   already has content — skipped, left untouched\n' >&2
    echo "WS|$name|skipped|already exists"
    continue
  fi

  mkdir -p "$WS/.claude"
  echo "WS|$name|created|$WS"

  # 2b — link the shared skills + scripts into the workspace
  printf '::   linking shared skills + scripts …\n' >&2
  link_dir "$STD/workspace/.claude/skills"  "$WS/.claude/skills"  "skills"
  link_dir "$STD/workspace/.claude/scripts" "$WS/.claude/scripts" "scripts"

  # 2c — workspace CLAUDE.md (imports the canonical doc)
  printf '::   writing CLAUDE.md …\n' >&2
  IMPORT="$(import_path "$STD" "$WS")"
  cat > "$WS/CLAUDE.md" <<EOF
<!-- Workspace instructions. The canonical doc is maintained once in the
     standards repo and imported below, so it never drifts. -->

@${IMPORT}

<!-- Workspace-specific notes (NOT shared) go below this line. -->
EOF

  # 2d — settings (never overwrite a developer's personal grants)
  if [ ! -e "$WS/.claude/settings.json" ]; then
    printf '::   copying settings.json from the template …\n' >&2
    cp "$STD/workspace/.claude/settings.template.json" "$WS/.claude/settings.json"
  fi

  # 2d.1 — put the standards clone in the workspace's READ SCOPE.
  # skills/ and scripts/ above are junctions (Windows) / symlinks (POSIX) whose REAL target is
  # the standards clone, which lives OUTSIDE this workspace. Claude Code resolves the link to its
  # real path and applies its directory-scope gate, so a `Read(**)` allow rule (scoped to the
  # workspace) is NOT enough — every skill support-file read (source-acquisition.md, etc.) and the
  # imported root CLAUDE.md would prompt mid-flow. additionalDirectories brings the clone in scope.
  # Additive + idempotent: runs even when settings.json already exists, so re-running /setup repairs
  # workspaces provisioned before this fix, and it never removes a developer's own entries.
  STD_SCOPE="$(cygpath -m "$STD" 2>/dev/null || printf '%s' "$STD")"
  if command -v node >/dev/null 2>&1; then
    if node -e 'const fs=require("fs");const [f,d]=process.argv.slice(1);const j=JSON.parse(fs.readFileSync(f,"utf8"));j.permissions=j.permissions||{};const a=(j.permissions.additionalDirectories=j.permissions.additionalDirectories||[]);if(!a.includes(d)){a.push(d);fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n");}' "$WS/.claude/settings.json" "$STD_SCOPE"; then
      printf '::   ensured standards clone is in read scope (additionalDirectories)\n' >&2
    else
      echo "WARN|scope|could not patch additionalDirectories in $WS/.claude/settings.json — skill reads may prompt"
    fi
  else
    echo "WARN|scope|node not found — additionalDirectories not set; skill support-file reads will prompt"
  fi

  # 2e — record the standards-repo link so other skills can find the shared clone
  printf '%s' "$STD" > "$WS/.claude/standards-root"

  # 2f — clone + sync all repos
  if $SKIP_SYNC; then
    printf '::   --skip-sync set; not cloning (provisioning only)\n' >&2
  else
    printf '::   cloning + syncing all repos (this is the slow part) …\n' >&2
    bash "$SCRIPT_DIR/sync-repos.sh" --root "$WS"
  fi
  printf '::   %s ready\n' "$name" >&2
done

echo "SETUP_DONE"
