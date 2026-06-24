---
description: Read MR review comments, implement required changes, and squash all changes into the original feature commit. Usage: /address-review PROJ-XXX
arguments:
  - name: ticket
    description: Tracker ticket ID (e.g. PROJ-123), full tracker URL, or MR URL (e.g. https://<git-host>/org/repo/-/merge_requests/42)
    required: true
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Agent
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Address reviewer feedback on an open MR. Reads discussion threads from the Git host, implements required changes, verifies the build, and **squashes all changes into the original feature commit** (force push — the MR history stays clean with one commit).

> **Coverage & gaps.** This reads MR metadata, **review notes/discussions**, and **conflicts** — any can fail (token absent, MR 404/403, notes-count mismatch, conflicts fetch failed). Attempt each; on failure tell the user EXACTLY what couldn't be read and the fix. If the fetched note count is below `user_notes_count`, warn and proceed with what was found — never address only a subset of the feedback silently.

## Required disciplines (Superpowers substrate)

This skill is the **domain** layer for a review round — fetching MR threads, mapping each to a
change, the squash/additive re-push, and the tracker-state handoff. The generic engineering discipline
is delegated to Superpowers skills; do not re-derive it here. Load and follow each at the point
marked below:

- **REQUIRED: superpowers:receiving-code-review** — how to *triage* reviewer feedback (Steps 4–6):
  verify each suggestion against this codebase before implementing, push back with technical reasoning
  on what's wrong or breaks existing behavior, ask when an item is unclear instead of guessing, and
  never give performative agreement. This is what makes Step 4's REQUIRED/SUGGESTION buckets and the
  Step 5 gate more than rubber-stamping — a "wrong" or unclear comment is challenged, not blindly
  applied.
- **REQUIRED: superpowers:systematic-debugging** — root cause before *any* fix: understand the
  reviewer's actual concern (Step 6) and find the real cause of a build/test break (Steps 7–8) before
  editing. Read the complete error output; never patch a symptom.
- **REQUIRED: superpowers:verification-before-completion** — evidence before any "addressed / builds /
  tests pass / ready to push" claim (Steps 6–13). Instances: cite the grep/read behind any "this
  is the only caller", "there's no existing helper", or "the pattern is X" claim, and render the view
  before any visual claim; report the build/test result only from output you ran in this message.

Domain-specific guardrails these do **not** cover, active throughout:
- **Security by default**: a reviewer-flagged security gap is HIGH — treat it as such (Step 9).
- **No scope creep**: only change what the review comments ask for (Step 6's scoped/minimal rules).
- **Trace every comment**: every REQUIRED change must be traceable to a comment thread (Step 6).

---

### Branch hygiene rules (apply to every git command in this skill)
- Always `git fetch origin <target_branch>` before any reset, rebase, or diff against the target.
- Always reference the remote as `origin/<branch>` — never use a local branch name as a base (it may be stale).
- Never stage a shared submodule / vendored-dependency pointer.

---

> **Context journal:** Once the ticket ID is known, read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` if it exists. It carries the decisions and dead-ends from the original implementation; honor every `DEADEND` so a reviewer-requested change does not re-introduce a failed approach. As you address review feedback, append entries via `bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> <TYPE> "<text>"`: log each non-trivial change you make to satisfy a comment as a `DECISION` (with the reviewer's reasoning), and any fix attempt that failed as a `DEADEND`. This survives compaction during a long review cycle.

## Step 1 — Identify branch, repos, and current working state

**If `$ticket` is an MR URL** (matches `<git-host>/.*/merge_requests/\d+`):

Extract the project path and MR IID, then call the Git host MCP `get_merge_request` to get `source_branch` and `target_branch`. Derive the ticket ID from the branch name (e.g. `feature/PROJ-123_...` → `PROJ-123`). Map the Git host project to a local repo name:

| Git host project | Local repo |
|---|---|
| `org/shared` | `shared` |
| `org/api` | `api` |
| `org/web` | `web` |
| `org/auth` | `auth` |
| others | strip the `org/` prefix, match by name |

Store the MR IID, project path, and `target_branch` — skip Step 2 (MR already known).

**If `$ticket` is a tracker ticket ID or tracker URL:**

Extract the ticket ID. Try to load `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`.

- If the file exists and `plan.branch` + `plan.repos` are set → use them.
- Otherwise run `bash "$WORKSPACE_ROOT/.claude/scripts/detect-wip.sh"` and filter for this ticket. If still not found, ask: _"Which repo(s) have the open MR? (e.g. api, web)"_

After this step you must have: `ticket`, `branch`, `repos`, `target_branch`.

### Branch switching

For each repo, check the current branch:
```bash
git -C "$WORKSPACE_ROOT/<repo>" branch --show-current
```

If the current branch is **not** `<branch>`:
1. Check for uncommitted changes: `git -C "$WORKSPACE_ROOT/<repo>" status --short`
2. If there are uncommitted changes, stash them:
   ```bash
   git -C "$WORKSPACE_ROOT/<repo>" stash push -m "<current_branch> WIP before switching to <ticket>"
   ```
3. Switch to the feature branch:
   ```bash
   git -C "$WORKSPACE_ROOT/<repo>" checkout <branch>
   ```
4. Note the original branch and whether a stash was created — you must restore this in Step 14.

### Staleness check (before building or committing)

After switching, check whether the branch is behind its target:
```bash
git -C "$WORKSPACE_ROOT/<repo>" fetch origin <target_branch> -q
git -C "$WORKSPACE_ROOT/<repo>" rev-list --count HEAD..origin/<target_branch>
```
If > 0, the branch is **stale**. A stale branch often fails to build against the current shared submodule with errors in files you never touched (missing members/types, changed method signatures) — that is a **staleness signal, not your bug**. The fix is to rebase onto the target. Do **not** patch those unrelated files, and **never** downgrade the shared submodule to the branch's recorded gitlink to force a build — keep the shared submodule on `develop`:
```bash
# non-destructive conflict check first
git -C "$WORKSPACE_ROOT/<repo>" merge-tree --write-tree --name-only origin/<target_branch> HEAD
# clean → rebase; conflicts → run /resolve-conflicts <ticket>
bash "$WORKSPACE_ROOT/.claude/scripts/rebase-branch.sh" --repo <repo> --branch <branch> --target <target_branch>
```
Rebasing is the proper flow — it is exactly what the Step 11 squash does via reset-to-target. For a single-commit feature branch, the Step 11 squash is simply `git commit --amend` after the rebase.

---


## Step 2 — Find the MR(s) on the Git host

For each repo, derive the Git host project path:
```bash
git -C "$WORKSPACE_ROOT/<repo>" remote get-url origin 2>/dev/null \
  | sed 's|https://<git-host>/||;s|\.git$||'
```

Then search for the open MR by source branch:
```
<Git host MCP search>
  query: "source_branch:<branch> state:opened"
  scope: merge_requests
```

If not found, ask the user for the MR URL and extract the `iid` from it.

---

## Step 3 — Fetch review discussions

**Connector first, token second.**

### 3a — Git host connector (primary)

```
<Git host MCP get_workitem_notes>
  project_path: <project_path>
  iid: <mr_iid>
```

For each note record: `author.username`, `body`, `type` (`DiffNote` = inline), `position.new_path` + `position.new_line`, `resolvable`, `resolved`.

If the tool is unavailable, fails, or the response lacks the fields above (`resolvable`/`position`) → fall through to 3b.

### 3b — Direct REST API (fallback — needs the PAT)

```bash
GIT_TOKEN="${GIT_TOKEN:-$(cat "$HOME/.claude/git-token" 2>/dev/null)}"
echo "${GIT_TOKEN:0:4}…"
```

If a token is found:
```bash
PROJECT_ENCODED=$(echo "<project_path>" | sed 's|/|%2F|g')
curl -sf "https://<git-host>/api/v4/projects/${PROJECT_ENCODED}/merge_requests/<mr_iid>/notes?per_page=100&sort=asc" \
  -H "PRIVATE-TOKEN: $GIT_TOKEN" \
  > /tmp/mr_notes.json
```

Parse the JSON for the same fields as 3a.

If curl returns 401 or token is absent → fall through to 3c.

### 3c — Keyword search (last resort)

```
<Git host MCP get_merge_request_diffs>
  id: <project_path>
  merge_request_iid: <mr_iid>
```

Extract identifiers from the diff and search for reviewer notes:
```
<Git host MCP search>  scope: notes  search: <term>  project_id: <project_path>
```

Aggregate, filter to `noteable_iid == <mr_iid>`, deduplicate by `id`.

### 3d — Coverage check

Compare found note count against `user_notes_count` from `get_merge_request`. Warn if lower; continue with what was found.

Fetch diffs only if inline comments reference specific lines and you need surrounding context.

---


## Step 4 — Categorize the feedback

Triage with **REQUIRED: superpowers:receiving-code-review** — evaluate each comment for technical
correctness *against this codebase* before bucketing it; a suggestion that is wrong, breaks existing
behavior, or is unclear gets challenged or queried, not auto-accepted. Three buckets: **REQUIRED**
(correctness/security/naming — must fix), **SUGGESTION** (optional — ask user), **RESOLVED/INFO** (skip).

Show triage table, ask about suggestions, wait for reply before proceeding.

If ZERO unresolved REQUIRED → stop: _"No unresolved change requests found on MR !<iid>."_

---

## Step 5 — Build action plan

### 🛑 GATE — DO NOT TOUCH ANY CODE until user confirms.

```
Action plan:

1. [REQUIRED] <repo>/<file>:<line>
   Reviewer: "<exact comment>"
   Change: <what specifically changes>

Commit strategy — choose one (no default; let the MR's review state guide you):
  (a) additive — add a new "PROJ-XXX <what the review changed>" commit on top; plain push, NO force-push.
      Preferred when the MR is open / under active review (preserves the reviewer's reading).
  (b) squash — fold the changes into the original feature commit; force-push (one clean commit).
      Preferred before first review, or when the team wants a single-commit MR.
  Original commit message: "<PROJ-XXX original commit message>"

Reply "additive" or "squash" (plus "go ahead") to implement.
```

**Wait for "go ahead" before writing any code.**

---


## Step 6 — Implement changes

Understand the reviewer's actual concern before editing — **REQUIRED: superpowers:systematic-debugging**
for any comment about a bug or broken behavior (root cause, not the symptom the comment names). If a
comment is still unclear at this point, stop and ask rather than guessing (**REQUIRED:
superpowers:receiving-code-review**).

Read each target file, then apply the change. Trace back to comment number after each edit:
```
  ✓ <file> — addressed comment #<N> (<2-word summary>)
```

Do not change files not in the plan. If a side-effect requires touching another file, stop and ask.

**Scoped fixes only.** Touch only what the review comment requires. Do **not** sweep-fix pre-existing issues in a file you're editing — in particular a `--fix` linter/style-linter run can reorder or rewrite **unrelated pre-existing** lines (e.g. ordering rules applied across a whole stylesheet); keep only the changes on the lines your fix touches and revert the rest, or the diff balloons with churn the reviewer didn't ask for.

**Minimal mechanism over structural improvement.** For each fix, prefer the smallest change that genuinely resolves the comment (often one guard/condition) over a restructure that *also* prevents the bug class — a review round is the wrong time to relocate ownership or rewire components. If a structural fix seems genuinely better, present both ("1-line guard" vs "restructure, +N/−M lines") and let the user choose; default to minimal.

---

## Step 7 — Build verify

Capture the **full** log (never pipe through `| tail` — that hides compiler errors behind cache-lock noise), then grep for real errors:
```bash
<build command for the repo> > "$WORKSPACE_ROOT/.claude/tickets/_build.log" 2>&1
grep -E ': error |error ' "$WORKSPACE_ROOT/.claude/tickets/_build.log" | head -20   # empty = clean
```
If you hit build-cache-lock errors (an IDE or leftover build nodes holding the caches): shut down the build server, then rebuild. If errors land in files you did **not** touch, the branch is stale — see the Staleness check in Step 1 and rebase rather than patching unrelated files.

For the UI repo, type-check:
```bash
<type-check command> 2>&1 | tail -20
```

If the change touched the UI/SPA, also run the linter — and the style linter if any stylesheet changed — on that SPA (the same checks implement-ticket runs; the type-checker does not cover them):
```bash
(cd "$WORKSPACE_ROOT/web/<spa>" && npm run lint)
(cd "$WORKSPACE_ROOT/web/<spa>" && npm run slint)   # only if a stylesheet changed
```
(Keep any `--fix` scoped — see Step 6.)

If the build or a check fails, **REQUIRED: superpowers:systematic-debugging** — read the complete log
and find the root cause before editing (and mind the staleness signal in Step 1: errors in files you
never touched mean rebase, not patch). Report "build clean" only from the grep result you ran in this
message — **REQUIRED: superpowers:verification-before-completion**. Fix all errors before proceeding.
Never skip this step.

---


## Step 8 — Run affected tests

```bash
<test command, filtered to the affected namespace/suite>
```

If tests that were previously passing now fail → fix before continuing.

---

## Step 9 — Self-review

Read every file modified in Step 6. Check:
- Security: auth still present, no new query interpolation
- Correctness: null guards, no fire-and-forget async, disposables managed
- Quality: no magic strings, no commented-out code, logging levels appropriate
- **Cross-artifact (HIGH if mismatched):** if the change altered a value-set (enum/magic-number list, status codes), grep sibling repos — especially the DB scripts — for the same set and confirm they match. A reviewer-driven change to a value-set is frequently mirrored in a one-time SQL `DELETE`/`UPDATE` that won't appear in this repo's diff; a stale mirror is a data-loss bug.

Report HIGH (auto-fix), MEDIUM (ask user), LOW (note only). Do not mark a checklist item clean without
the grep/read/render that proves it — **REQUIRED: superpowers:verification-before-completion** (e.g. the
cited grep behind "this is the only caller" / "there's no existing helper" / "the pattern is X").

---


## Step 10 — Commit & push

Branch on the commit strategy chosen in Step 5.

### ADDITIVE path ("additive") — new commit on top, plain push, no force

🛑 FULL STOP — do not stage or commit until approved. Show the files changed in Step 6 and the proposed new commit message `PROJ-XXX <summary of the review changes>`; wait for confirmation. Then, per repo:
```bash
git -C "$WORKSPACE_ROOT/<repo>" add <review-touched files>   # the Step 6 files only — never a shared submodule
git -C "$WORKSPACE_ROOT/<repo>" commit -m "PROJ-XXX <summary of the review changes>"   # single line, no body
bash "$WORKSPACE_ROOT/.claude/scripts/prepare-mr.sh" --repo <repo> --branch <branch>   # confirm CHECK|PASS
```
🛑 Push gate — wait for "push", then a **plain** push (reviewed commits stay intact, nothing is rewritten):
```bash
git -C "$WORKSPACE_ROOT/<repo>" push origin <branch>
```
Then skip to **Step 14**.

### SQUASH path ("squash") — fold into the original commit, force-push (Steps 10–13 below)

### 🛑 FULL STOP. DO NOT STAGE OR COMMIT UNTIL APPROVED.

Fetch the target branch so the identification commands use fresh remote refs:
```bash
git -C "$WORKSPACE_ROOT/<repo>" fetch origin <target_branch>
```

Identify:
1. The original feature commit message:
   ```bash
   git -C "$WORKSPACE_ROOT/<repo>" log --format="%s" "origin/<target_branch>..HEAD" | tail -1
   ```
2. All files that belong to this feature (committed + any still-unstaged edits from Step 6):
   ```bash
   git -C "$WORKSPACE_ROOT/<repo>" diff "origin/<target_branch>..HEAD" --name-only | grep -v "^shared$"
   # Plus any working-tree changes not yet committed:
   git -C "$WORKSPACE_ROOT/<repo>" status --short | awk '{print $2}'
   ```
   Merge both lists (deduplicated), excluding the shared submodule.

Show:
```
Ready to squash into original commit:

  Feature files (will be squashed):
    <repo>/<file1>
    <repo>/<file2>

  Commit: <original PROJ-XXX commit message>

  Note: this force-pushes origin/<branch>.

Confirm to proceed. Or suggest a different commit message.
```

Wait for explicit confirmation.

---

## Step 11 — Squash and commit (squash path)

For each repo in the change set:

```bash
# 1. Fetch was already done in Step 10 — skip if running immediately after.
#    If Step 10 was more than a few minutes ago, re-fetch:
git -C "$WORKSPACE_ROOT/<repo>" fetch origin <target_branch>

# 2. Find the original commit message (first PROJ-XXX commit unique to this branch)
#    --format="%s" avoids fragile hash-length assumptions
ORIG_MSG=$(git -C "$WORKSPACE_ROOT/<repo>" log --format="%s" "origin/<target_branch>..HEAD" \
  | tail -1)

# 3. Collect ALL feature files (committed diff vs origin/<target_branch>), excluding the shared submodule
FEATURE_FILES=$(git -C "$WORKSPACE_ROOT/<repo>" diff "origin/<target_branch>..HEAD" --name-only \
  | grep -v "^shared$")

# 4. Stage any working-tree edits from the review step that were not yet committed.
#    This is critical — reset --hard would otherwise discard them.
git -C "$WORKSPACE_ROOT/<repo>" add $FEATURE_FILES

# 5. If there are staged changes (review edits not yet committed), make a temp commit
#    so SAVED_HEAD captures everything.
if ! git -C "$WORKSPACE_ROOT/<repo>" diff --cached --quiet; then
  git -C "$WORKSPACE_ROOT/<repo>" commit -m "temp: review changes — will be squashed"
fi

# 6. Save HEAD — now contains all original + review changes
SAVED_HEAD=$(git -C "$WORKSPACE_ROOT/<repo>" rev-parse HEAD)

# 7. Re-collect feature files against fresh origin/<target_branch> (includes temp commit)
FEATURE_FILES=$(git -C "$WORKSPACE_ROOT/<repo>" diff "origin/<target_branch>..HEAD" --name-only \
  | grep -v "^shared$")

# 8. Hard reset to the freshly-fetched target branch
git -C "$WORKSPACE_ROOT/<repo>" reset --hard origin/<target_branch>

# 9. Restore all feature files from the saved HEAD
git -C "$WORKSPACE_ROOT/<repo>" checkout $SAVED_HEAD -- $FEATURE_FILES

# 10. Stage only feature files (never the shared submodule)
git -C "$WORKSPACE_ROOT/<repo>" add $FEATURE_FILES

# 11. Commit with the original message (single line, no body)
git -C "$WORKSPACE_ROOT/<repo>" commit -m "$ORIG_MSG"
```

Run `prepare-mr.sh` to verify format checks pass:
```bash
bash "$WORKSPACE_ROOT/.claude/scripts/prepare-mr.sh" --repo <repo> --branch <branch>
```

If any `CHECK|FAIL` → fix before pushing.

---


## Step 12 — Push gate

### 🛑 FULL STOP. Do not push without explicit approval.

```
Committed. Ready to force-push to origin/<branch>.

  This rewrites the branch history (squash into original commit).
  Use: git push --force-with-lease

Reply "push" to continue.
```

Wait for explicit "push".

---

## Step 13 — Push

```bash
git -C "$WORKSPACE_ROOT/<repo>" push --force-with-lease origin <branch>
```

On success: confirm.
On failure (rejected): show the error. If remote has newer commits, fetch and redo the squash from Step 11.

---


## Step 14 — Restore original branch and final output

**Restore original branch** (if you switched in Step 1):
```bash
git -C "$WORKSPACE_ROOT/<repo>" checkout <original_branch>
# If a stash was created in Step 1:
git -C "$WORKSPACE_ROOT/<repo>" stash pop
```

Verify the stash pop succeeds cleanly. If there is a conflict (the stashed file was also modified by the feature branch checkout), resolve by keeping the stash version for files that were only in the original-branch WIP, and keeping HEAD for all others.

**Update state file** (if it exists): read it, append to the `reviews` array, then save the whole document — preserve all other fields, do not change `phase`.

> **Persist via the helper — never the Write/Edit tool.** Write the full JSON to a temp file with
> the Write tool at `$WORKSPACE_ROOT/<ticket>.state.json`, then run the plain command
> `bash "$WORKSPACE_ROOT/.claude/scripts/save-state.sh" <ticket> "$WORKSPACE_ROOT/<ticket>.state.json"` — the
> helper validates the JSON, writes `.claude/tickets/<ticket>.json`, stamps timestamps, and deletes
> the temp. Do NOT use a heredoc / `<` redirect / `&&` chain (they make the command compound and
> prompt) and do NOT Write/Edit `.claude/tickets/*.json` directly (its dot-dir path prompts on Windows).

**Final output:**
```
✓ PROJ-XXX review addressed.

Commit: <squash → "squashed into '<original message>'"  |  additive → "new commit 'PROJ-XXX <summary>'">

Comments addressed:
  #1 [<author>] — <what changed>
  #2 [<author>] — <what changed>

Next steps:
  1. Open the MR on the Git host and mark addressed threads as resolved.
  2. Re-request review from the reviewer(s).

MR link(s):
  <repo> → <web_url>
```
