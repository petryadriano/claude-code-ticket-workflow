---
description: Create a feature or bugfix branch with the correct naming convention. Use when starting work on a new tracker ticket.
arguments:
  - name: request
    description: Natural language description, e.g. "PROJ-123 implement resource set on write service" or "PROJ-123 bugfix approval ordering"
    required: true
allowed-tools:
  - Bash
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Create a correctly named branch for a tracker ticket and check it out.

## Required disciplines (Superpowers substrate)

This skill is the **branch-naming + creation** procedure — the naming rules, verb list, commit-message
derivation, and the `create-branch.sh` call are product-specific and stay here. This is mechanical git with
little generic discipline to delegate; only one applies:

- **REQUIRED: superpowers:verification-before-completion** — report "branch created" only from the script's
  own `OK|repo|branch|base` line, never from the fact that the command returned. On `ERROR|message`, report
  the failure, not success. (See the report step below.)

There is no failure diagnosis here (the script relays `ERROR|message` verbatim — the user fixes the cause)
and no heavy reference catalog to extract, so nothing else is delegated.

## Branch naming rules

**Feature:** `feature/PROJ-XXX_Verb_Short_Title`
- Verb must be one of: `Implement`, `Add`, `Update`, `Refactor`, `Remove`, `Migrate`, `Enable`, `Disable`, `Expose`, `Extract`, `Rename`, `Move`, `Replace` (authoritative list: `FEATURE_VERBS` in `prepare-mr.sh` — keep in sync)
- Choose the verb that best matches the work described

**Bugfix:** `bugfix/PROJ-XXX_Fix_Short_Title`
- Always prefix title with `Fix` — never duplicate it if the user already said "fix"

**Title formatting:**
- Each word capitalised, joined with underscores
- Keep it concise (5–7 words max)
- No trailing underscores or special characters

**Commit message** = branch suffix with underscores replaced by spaces:
- `feature/PROJ-123_Implement_Resource_Set` → `PROJ-123 Implement Resource Set`
- `bugfix/PROJ-123_Fix_Approval_Ordering` → `PROJ-123 Fix Approval Ordering`
- First letter after the ticket number must be uppercase
- Single line only — no body, no description

## Steps

1. Extract from `$request`: ticket number (`PROJ-XXX`), type (feature/bugfix), and title words.
2. Format the full branch name following the rules above.
3. If the repo is not obvious from context, ask which repo before proceeding.
4. Run the script:

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/create-branch.sh" --repo "<repo>" --branch "<branch-name>"
```

5. Report the result — keyed off the script's actual output line, never assumed (**REQUIRED: superpowers:verification-before-completion**):
   - On `OK|repo|branch|base`: show the branch name and the commit message to use for all commits on this branch
   - On `ERROR|message`: explain what went wrong
