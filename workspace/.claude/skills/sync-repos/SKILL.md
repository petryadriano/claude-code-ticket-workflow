---
description: Sync repos to their default branch and pull latest code. Use when the user wants to start a new ticket, get latest code, or sync repos. Supports targeting specific repos — e.g. /sync-repos api web syncs only those two.
arguments:
  - name: repos
    description: Space-separated repo names to sync (e.g. "api web"). Omit to sync all repos.
    required: false
allowed-tools:
  - Bash
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Sync repos to their default branch and pull latest code. Dirty changes are auto-stashed and restored after — no questions asked.

Script: `$WORKSPACE_ROOT/.claude/scripts/sync-repos.sh`

## Required disciplines (Superpowers substrate)

This skill is the **multi-repo sync** procedure — the git/branch/stash machinery below is product-specific
and stays here. The generic engineering discipline is delegated to Superpowers skills; load and follow each
at the point marked below:

- **REQUIRED: superpowers:systematic-debugging** — when a sync, fetch, or pull **fails** (ERROR/CONFLICT lines): read the complete error and find the root cause (auth/credentials, network, moved shared submodule pointer, true merge conflict) before proposing a fix. An environmental failure needs the precondition fixed, not a blind retry.
- **REQUIRED: superpowers:verification-before-completion** — never report "all synced" without the script's own per-repo output as evidence, and never `git stash drop` without first proving the stash is redundant (the proof rule below is the instance of this discipline).

## Run

```bash
# Specific repos (when $repos was provided):
bash "$WORKSPACE_ROOT/.claude/scripts/sync-repos.sh" --repos "<$repos>"
# All repos (when $repos omitted) — pass NO --repos flag; the script's own ALL_REPOS
# list is the single source of truth for the full repo set:
bash "$WORKSPACE_ROOT/.claude/scripts/sync-repos.sh"
```

## Report

Parse pipe-delimited output and render:

**Sync results table** — repo rows, submodule rows as `↳ Name` immediately below their parent:

| Repo | Status | Branch | Latest commit |

**Summary:** `X OK | X warnings | X skipped | X errors` (repo rows only)

### Conflict handling (CONFLICT lines)

If any `CONFLICT|repo|message` lines appear in the output, **do not report success silently** (**REQUIRED: superpowers:verification-before-completion** — a conflict is evidence the sync did *not* cleanly complete). Instead:

1. Show which repos have conflicts and what happened.
2. Explain the state: the stash entry is still intact, but conflicting files are in the working tree with conflict markers.
3. Ask the user how to proceed for each conflicted repo:
   - **Resolve and continue (agent)** — the usual right answer mid-lifecycle, when the conflict is between this ticket's working-tree changes and new upstream commits: merge **both** sides (keep upstream's fixes AND your changes — new upstream tests may call APIs your change reshaped; convert them, don't revert your shape), `git add` the resolved files, then verify: if the build now fails in files you never touched, root-cause it before patching (**REQUIRED: superpowers:systematic-debugging**) — run `git submodule update --init Shared` first (a moved shared submodule pointer surfaces exactly that way), rebuild, and rerun the affected tests. Only then consider the stash drop (proof rule below).
   - **Keep conflicts** — leave as-is so they can resolve manually (`git status` to see files, `git add` + `git stash drop` once done)
   - **Discard my changes** — run `git checkout -- .` then `git stash drop` to throw away the stashed changes

> **Before any `git stash drop` — prove the stash is redundant, and say so** (the instance of
> **REQUIRED: superpowers:verification-before-completion**). A drop permanently
> deletes the stash, and the safety hook will ask the user to confirm it. So before proposing one:
> confirm every change in `git stash show -p stash@{0}` is already present in the working tree
> (conflicts resolved, files modified/staged) and the build/tests pass — then state that evidence in
> the **same message** as the drop, so the user sees the justification right where the confirmation
> prompt appears. If anything in the stash is NOT in the tree, do not drop — surface the gap instead.

Wait for the user's answer before finishing.

### Error / unreachable repo handling (ERROR lines)

> **Coverage & gaps.** Cloning/pulling can fail on **auth/credentials, network, or a missing repo** — not just merge conflicts. For any `ERROR|repo|message` (or a repo that simply didn't sync), do **not** report success: root-cause the failure first (**REQUIRED: superpowers:systematic-debugging** — read the exact error; auth/credentials vs network vs missing repo each have different fixes), then name each affected repo and the exact reason, give the concrete fix (fix git/credentials and retry; check the remote/network), and **list which repos are therefore stale or absent** so downstream skills never assume a repo synced when it didn't. "All synced" is a completion claim — only make it once the per-repo output shows every targeted repo OK (**REQUIRED: superpowers:verification-before-completion**).
