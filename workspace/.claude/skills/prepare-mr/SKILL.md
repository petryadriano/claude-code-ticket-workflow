---
description: Validate a branch for MR readiness and show the MR creation URL. Never creates the MR — always shows the URL for the user to open.
arguments:
  - name: repo
    description: Repo name (e.g. "api"). Omit if obvious from context.
    required: false
allowed-tools:
  - Bash
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Validate the current branch for MR readiness and output the Git host's MR creation URL.

**Never create the MR.** Always show the URL for the user to open themselves.

## Required disciplines (Superpowers substrate)

This skill is the **domain** layer — its job is the MR-readiness machinery (the
`prepare-mr.sh` checks, the branch/commit-format gates, the user-creates-the-MR rule). The one
generic discipline it leans on is delegated:

- **REQUIRED: superpowers:verification-before-completion** — evidence before any "MR is ready / the
  diff is correct / checks pass" claim. The proof here is the **actual `prepare-mr.sh` output** — do
  not report a check as PASS, or call the branch ready, on anything but the script's `CHECK|PASS`
  lines you ran in this message.

---

## Run

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/prepare-mr.sh" --repo "<repo>" [--branch "<branch>"]
```

If `$repo` is not provided and not obvious from context, ask before running.
Omit `--branch` to auto-detect from the repo's current branch.

## Report

Parse output and render a checklist:

| # | Check | Result |
|---|---|---|
| 1 | Branch name format | PASS / FAIL |
| 2 | Commit message format | PASS / FAIL |
| 3 | Shared pointer not in commits | PASS / FAIL |
| 4 | Shared pointer not staged | PASS / FAIL |

For each `CHECK|FAIL` line, show what is wrong and how to fix it. Render PASS/FAIL **only** from the
script's own `CHECK|` lines — **REQUIRED: superpowers:verification-before-completion**; never infer a
PASS the output didn't print.

Then, regardless of pass/fail, always show the MR URL prominently:

> **Open MR:** `<URL from URL| line>`

The user clicks this URL to create the MR on the Git host with source and target branches pre-filled.
