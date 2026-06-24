---
description: Rebase a feature/bugfix branch onto its target after a long code review — resolves MR conflicts repo by repo with guided conflict resolution. Usage: /resolve-conflicts PROJ-XXX
arguments:
  - name: ticket
    description: Tracker ticket ID (e.g. PROJ-123), or an MR URL. Omit to auto-detect from current branch.
    required: false
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - the Git host's MCP get-merge-request tool
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Rebase one or more feature branches onto their upstream target to clear MR conflicts.

## Required disciplines (Superpowers substrate)

This skill is the **rebase / conflict-resolution** procedure — the branch-per-repo model, the
`rebase-branch.sh` machinery, the shared-submodule handling, the stash/pop logic, the conflict-block
mechanics, and `--force-with-lease` all stay here. The generic engineering discipline is delegated to
Superpowers skills; load and follow each at the point marked below:

- **REQUIRED: superpowers:systematic-debugging** — root-cause **before** acting whenever something fails or surprises you: a build break after a rebase (Step 4 — is the `error` branch-owned or pre-existing on `origin/<target>`?), a true semantic conflict (Step 3a — understand *both* sides before choosing), and a silently dropped commit (Step 4a — find *why* it dropped before accepting it). Read the complete output first; never patch a symptom or accept a surprise without understanding it.
- **REQUIRED: superpowers:verification-before-completion** — evidence before any "rebased / clean / builds / pushed" claim: confirm no conflict markers and no dropped lines remain after a resolution (Step 3a), confirm the build is green in branch-owned files before the push gate (Steps 4–5), and confirm each force-push actually landed before reporting it (Steps 6–7).

> **Coverage & gaps.** This reads MR metadata (source/target branches) from the Git host. If the fetch fails (404 / 403 / token), state the exact failure and the fix (confirm the MR exists + you have access, set the token); if an MR URL can't be resolved, ask the user for the ticket id + branch rather than guessing the target branch.

Scripts: `$WORKSPACE_ROOT/.claude/scripts/`

**Submodule note:** the shared submodule is not a top-level repo — it lives at `$WORKSPACE_ROOT/api/Shared/`. The `rebase-branch.sh` script handles this automatically when `--repo Shared` is passed (no `--path` needed). If a different nested path is ever needed, pass `--path <abs-path>`.

---

> **Context journal:** Once the ticket ID is known, read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` if it exists — conflict resolution is where prior decisions matter most, since a careless resolution can silently undo one. Honor every `DEADEND` and `DECISION`. When a conflict resolution involves a real choice (which side to keep, how to reconcile divergent changes), append it: `bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> DECISION "<file>: kept <X> over <Y> because <why>"`.

## Step 1 — Identify branch and repos

**If the argument is an MR URL** (matches the Git host's `.../merge_requests/\d+` path):

Extract the project path and MR IID, then call the Git host's MCP get-merge-request tool to get `source_branch` and `target_branch`. Derive the ticket ID from the branch name (e.g. `feature/PROJ-123_...` → `PROJ-123`). Map the Git host project to a local repo name:

| Git host project | Local repo |
|---|---|
| `org/web/shared` | `Shared` |
| `org/web/api` | `api` |
| `org/web/web` | `web` |
| `org/web/auth` | `auth` |
| others | strip `org/web/` prefix, match by name |

**If `$ticket` is a plain tracker ID:**

1. Normalise to `PROJ-XXX` uppercase.
2. Try to load `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. If it exists and `plan.branch` + `plan.repos` are set → use them.
3. Otherwise: `bash "$WORKSPACE_ROOT/.claude/scripts/detect-wip.sh"` — filter `BRANCH|repo|branch|ticket` lines to those matching the ticket. If none found, ask the user which repo(s) to rebase.

**If `$ticket` was omitted:**

Run `detect-wip.sh` and infer the ticket from currently checked-out branches. If multiple ticket IDs are found → ask which one.

After this step you must have:
- `ticket` — e.g. `PROJ-123`
- `branch` — e.g. `feature/PROJ-123_Implement_X`
- `target` — e.g. `develop`
- `repos` — list of repo names, e.g. `["api", "database"]`
- `paths` — resolved absolute path per repo (e.g. `Shared` → `$WORKSPACE_ROOT/api/Shared`, all others → `$WORKSPACE_ROOT/<repo>`)

---


## Step 2 — Pre-rebase safety snapshot

**Shared submodule (api repo only):** Before anything else, ensure the shared submodule is on `develop` HEAD — this is the correct local dev state and prevents stale-submodule compile errors:

```bash
git -C "$WORKSPACE_ROOT/api/Shared" checkout develop -q
git -C "$WORKSPACE_ROOT/api/Shared" pull origin develop -q
```

Before touching any repo, check for an interrupted rebase and capture a baseline. Run per repo:

```bash
# 1. Fail fast if a rebase is already in progress
if [ -d "$WORKSPACE_ROOT/<path>/.git/rebase-merge" ] || [ -d "$WORKSPACE_ROOT/<path>/.git/rebase-apply" ]; then
  echo "REBASE_IN_PROGRESS"
fi

# 2. Fetch so origin/<target> is up to date before the snapshot
git -C "<path>" fetch origin <target>

# 3. Snapshot the branch commit list (stable titles survive a clean rebase)
git -C "<path>" log --oneline origin/<target>..HEAD 2>/dev/null || \
  git -C "<path>" log --oneline HEAD~20..HEAD
```

If `REBASE_IN_PROGRESS`:
```
⚠ <repo> already has a rebase in progress.

  To continue the previous rebase: tell me "continue"
  To abort it and start fresh:     tell me "abort"
```
Wait for the user before touching that repo.

Store the commit list as the **pre-rebase baseline** — you will compare against it in Step 4a.

---

## Step 3 — Pre-rebase stash + Rebase (one repo at a time)

**Before** running the script, stash any unstaged changes so the rebase cannot be blocked by personal dev configs (launch configs, app settings files, CLAUDE.md, etc.):

```bash
git -C "<path>" stash push -m "pre-rebase stash <ticket>" 2>&1
```

Save the stash ref so you can pop it at the end (Step 7). If there is nothing to stash, git will print "No local changes to save" — that is fine, record that no pop is needed.

Then run the script — it fetches and rebases in a single pass:

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/rebase-branch.sh" \
  --repo <repo> \
  --branch <branch> \
  --target <target>
```

**After** a successful rebase (or UPTODATE), pop the stash immediately:

```bash
git -C "<path>" stash pop 2>&1
```

If the stash pop produces conflicts, stop and tell the user — do not silently discard the stash.

Print status as each repo finishes:

```
  Shared  → rebased onto develop (1 commit ahead) ✓
  api     → up to date
```

- `UPTODATE` → note and move on (still pop the stash if one was saved).
- `ERROR` → pop the stash, stop, explain, ask the user to fix before continuing.
- `CONFLICT` → **do NOT pop the stash yet** — go to Step 3a. Pop after `rebase --continue` exits 0.

**Special case — `CONFLICT` with empty file list:** If the script returns `CONFLICT` but `git diff --name-only --diff-filter=U` shows no conflicted files and no rebase is in progress (no `.git/rebase-merge` or `.git/rebase-apply` directory), the rebase was blocked by unstaged changes **before** it could start. In that case: pop any existing stash, stash again, then re-run the script.

---


## Step 3a — Conflict resolution

**Try auto-resolution first.** Read the conflicted file. For every conflict block in the file (there may be more than one):

```
<<<<<<< HEAD
<ours>
=======
<theirs>
>>>>>>> <sha> (<commit message>)
```

**Auto-resolve if and only if the conflict is purely additive** — each side added new content without modifying any line the other side also touched (e.g. new enum members, new config keys, new const declarations). In that case:
- Keep ALL lines from `<ours>`
- Keep ALL lines from `<theirs>`
- Remove the conflict markers

Repeat for every block in the file before staging.

**Mandatory verification after auto-resolving a file** (**REQUIRED: superpowers:verification-before-completion** — re-read the resolved file as evidence; do not assume the edit is clean):
1. Every unique line from every `<ours>` block is present in the output.
2. Every unique line from every `<theirs>` block is present in the output.
3. No conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) remain anywhere in the file.

If any check fails, fix the file and re-verify before staging.

Stage and continue:
```bash
git -C "<path>" add <file>
git -C "<path>" rebase --continue
```

**NEVER use `git rebase --skip`** — it silently discards an entire commit and all its code. If git suggests `--skip`, escalate to the user instead.

**Escalate to the user** if any conflict block has the same lines modified differently on both sides (true semantic conflict), or if you are not confident the resolution preserves all intended behaviour. A semantic conflict is a two-sided change you must *understand*, not guess at — root-cause what each side intended before proposing a merge (**REQUIRED: superpowers:systematic-debugging**); never pick a side to make the markers go away:

```
⚠ Rebase stopped in <repo> — conflict in <file>:

  Ours (HEAD):
    <lines from <<<<<<< … ======= block>

  Theirs (<commit message>):
    <lines from ======= … >>>>>>> block>

How to resolve:
1. Open the file and fix the conflict markers.
   Preserve BOTH sides' changes unless one side is genuinely wrong.
2. Stage: git -C "$WORKSPACE_ROOT/<repo-path>" add <file>
3. Reply "resolved" when staged, or "abort" to cancel.
```

- On "resolved": verify the file (no markers, no dropped lines), then run `rebase --continue`. If new conflicts appear, repeat Step 3a. If exit 0, pop the stash (if one was saved) and continue to Step 4a.
- On "abort": run `git -C "<path>" rebase --abort`, then **immediately pop the stash** (if one was saved) so no pending changes are lost. Report: _"Rebase aborted — your branch is back to its pre-rebase state and your working-tree changes have been restored."_

---

## Step 4a — Dropped-commit check (run after every successful rebase)

`origin/<target>` is already fresh — `rebase-branch.sh` fetches as part of its rebase pass. No extra fetch needed here.

```bash
git -C "<path>" log --oneline origin/<target>..HEAD
```

Compare against the pre-rebase baseline from Step 2:

- **Fewer commits?** Git silently drops commits whose changes were already fully present in the target (common with dependency branches that were merged before this one). Before accepting it, find *why* each commit dropped — confirm its changes really are already in the target, not lost (**REQUIRED: superpowers:systematic-debugging** — a dropped commit is an unexpected behaviour to root-cause, not to wave through). Then list every dropped commit by title and **require the user to confirm each drop was intentional** before continuing. Never assume a drop is safe.
- **Same count or more?** Continue — no code was dropped at the commit level.

> A rebase never increases commit count; if the count went up something unusual happened — stop and investigate.

---


## Step 4 — Build verify

**Submodule sync first (api repo only):** Before building, sync the shared submodule to its `develop` branch HEAD — this is the always-correct local dev state and avoids stale-submodule compile errors:

```bash
git -C "$WORKSPACE_ROOT/api/Shared" checkout develop -q 2>/dev/null
git -C "$WORKSPACE_ROOT/api/Shared" pull origin develop -q 2>/dev/null
```

Then build each repo that has a buildable solution/project (`database` and `Shared` have none — skip them automatically). Use a clean (non-incremental) build to bypass the build tool's incremental cache, which can produce false file-lock errors on Windows:

```bash
proj=$(find "$WORKSPACE_ROOT/<repo>" -maxdepth 1 -name "<solution-glob>" 2>/dev/null | head -1)
if [ -n "$proj" ]; then
  <build command> "$proj" --clean -q 2>&1 | grep -E "error|Build succeeded|Build FAILED|Error\(s\)"
fi
```

**Distinguishing real errors from pre-existing ones** (the instance of **REQUIRED: superpowers:systematic-debugging** — read the complete `error` output and find the root cause before reacting): If the build fails with an `error` in files **not touched by this branch**, check whether the same error exists on `origin/<target>` by looking at git log for those files. If the error predates this branch, it is pre-existing — note it for the user and proceed. Only block on errors in files the branch introduced or modified.

If any build fails with errors in branch-owned files → show the error, do NOT proceed to push, ask the user to fix. A green build in branch-owned files is the evidence the push gate (Step 5) depends on — **REQUIRED: superpowers:verification-before-completion**; do not advance on an unrun or red build.

---

## Step 5 — Push gate

### 🛑 FULL STOP — Do not push without explicit approval.

```
Rebase complete. Summary:

  Shared  → rebased onto develop (1 commit ahead) ✓ no dropped commits
  api     → up to date

Ready to force-push with --force-with-lease. Reply "push" to continue.
```

Wait for explicit "push" from the user. Do not push for any other reply, including "looks good" or implicit approval.

---


## Step 6 — Force push

For each repo that was rebased (not UPTODATE), use its resolved path from Step 1:

```bash
git -C "<resolved-path>" push --force-with-lease origin <branch>
```

Report each result **only after confirming the push actually landed** — read the push output (it reports the updated remote ref) rather than assuming success from a returned command (**REQUIRED: superpowers:verification-before-completion**). On failure, show the error and stop — do not continue to the next repo.

---

## Step 7 — Final output

```
✓ PROJ-XXX rebased and pushed.

  Shared  → force-pushed to origin/<branch>
  api     → already up to date (no push needed)

MR conflict warnings on the Git host should clear within a few seconds.
If still shown after 30 s, do a hard refresh on the MR page.
```

Do not change the state file `phase`. The branch was rebased but the ticket is still `shipped` — the next `/complete-ticket` run will recheck the MR and route correctly via the MR health check.
