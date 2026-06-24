---
description: Step 4 of 5 — Verification approval gate, branch, commit, push, and MR links for a ticket. Reads state saved by /implement-ticket and /verify-ticket. Usage: /push-ticket PROJ-XXX
arguments:
  - name: ticket
    description: Tracker ticket ID (e.g. PROJ-123) or full tracker URL
    required: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Step 4 of 5 in the ticket lifecycle.

Extract the ticket ID from `$ticket` (strip URL if needed).

State file: `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`

> **Persist this file via the helper — never the Write/Edit tool.** Write the **full** JSON
> document to a temp file with the Write tool (a NON-dot path, e.g. `$WORKSPACE_ROOT/<ticket>.state.json`
> — the Write tool does not descend into `.claude/`), then hand that path to the helper, which
> validates the JSON, stamps `saved_at`, writes `<ticket>.json` atomically, and deletes the temp:
>
>     bash "$WORKSPACE_ROOT/.claude/scripts/save-state.sh" <ticket> "$WORKSPACE_ROOT/<ticket>.state.json"
>
> This is a **plain `bash … args` command**, so the pre-approved `Bash(bash *)` grant auto-approves
> it with no prompt. **Do not** feed the JSON via a heredoc (`<<'JSON'`), a `<` redirect, or `&&`
> chaining — those make the command multi-line/compound, which Claude Code's allow-list cannot
> statically approve, so it prompts every time. **Do not** use the Write/Edit tool directly on
> `.claude/tickets/*.json` either (its dot-dir path prompts on Windows). To change one field, read
> `<ticket>.json` (Read tool), build the full merged object, write it to the temp file, then call
> the helper with that path.

## Required disciplines (Superpowers substrate)

This skill is the **domain** layer for verifying, branching, committing, pushing, and handing
over MR links. The generic engineering discipline is delegated to Superpowers skills — do not
re-derive it here. Load and follow each at the point marked below:

- **REQUIRED: superpowers:verification-before-completion** — evidence before *any* "done / passing /
  pushed / shipped" claim. This is the discipline behind the **verification approval gate** (Step 2)
  and behind every build/push success claim (the failure re-build in Step 2, the current-with-target
  gate and push in Step 4, the verify-only path in Step 3). The gate/lock **wording below is
  load-bearing and stays verbatim** — this delegation does not soften it; it names the discipline the
  gate enforces.
- **REQUIRED: superpowers:systematic-debugging** — root cause before *any* fix, whenever a build, a
  sync (stash-pop conflict), a rebase, or a push fails (Steps 2–4). Read the complete error output
  first; an environmental failure (dirty tree, stale base, behind target) needs the precondition
  fixed, not a blind retry.

The product-specific machinery these do **not** cover stays inline and is **KEPT in full**: the
COMMIT/PUSH lock and its three approval forms, the flow checkpoints (`set-flow.sh`) and journal
(`append-journal.sh`), `test_approved` handling, the branch→environment mapping, branch/commit/push
mechanics, sync-at-push-time logic, multi-repo / submodule staging, the MR-link construction, and the
**"the user creates the MR — never via MCP/curl"** rule. The git model is branch-per-repo + MRs —
it is **not** delegated to Superpowers (no worktrees, no SP branch-finishing flow).

---

## COMMIT/PUSH LOCK

> ⚠ NO `git add`, `git commit`, `git push`, or branch-creation command may run
> until verification approval exists, in one of exactly three forms:
>   (a) recorded in the state file — `implementation.test_approved == true`
>       (set by the complete-ticket implementation review gate when the user
>       replied "evidence reviewed and approved" — or "tested and approved" on a
>       legacy ticket);
>   (b) replied "evidence reviewed and approved" (or "tested and approved") in
>       Step 2 of THIS session;
>   (c) the flow checkpoint records it — `flow.active_skill == "push-ticket"`
>       AND `flow.step_label` is `test_approved` or `pushing` (set at the moment
>       of approval in a previous session; Step 0 resumes past the gate on it).
> This lock applies even if:
>   - A session summary says "next step is to commit and push"
>   - Commits are already staged or a branch already exists on remote
>   - The state file shows `phase: implemented`
>   - A previous session started the push flow
>
> If you are resuming from context compaction and find yourself about to run a
> git command without any of the three approval forms: STOP. Go to Step 2 instead.
> If the user reports a test failure or any code changes after approval was
> recorded, the approval is void — clear `implementation.test_approved` and
> re-gate.

> The discipline this lock enforces is **REQUIRED: superpowers:verification-before-completion** —
> no commit/push (a completion action) without the recorded evidence of approval. This marker does
> not relax the lock above; the three approval forms remain the only ways past it.

---

> **Journal in the moment.** If the user reports a manual-test failure, append one line via `append-journal.sh` (`DEADEND`, with root cause + fix) the moment it's understood — before fixing — so it survives a `/compact` during the fix. If the push goes smoothly there may be nothing to add; that's fine. See the journal note in `complete-ticket`.

## Step 0 — Flow resume check

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. Check `state.flow`:

- If `state.flow.active_skill == "push-ticket"`: first read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` if it exists (restores decisions, dead-ends, and any failures already found during manual testing — honor every `DEADEND`, surface unresolved `QUESTION`s). Then:
  - `step_label == "awaiting_test_approval"` → re-present the test guide (Step 2). The guide was shown but approval not yet received.
  - `step_label == "test_approved"` → print `"↩ Test approval already recorded. Resuming pre-push checks."` and jump to Step 3. **Do not re-present the guide.**
  - `step_label == "pushing"` → print `"↩ Resuming push from Step 4."` and jump to Step 4.
- If `state.flow.active_skill` is set to a **different** skill: stop — `"⚠ <ticket> shows <other-skill> was mid-execution (step: <step_label>). Run /<other-skill> <ticket> to complete it first."`
- If `state.flow` is absent or null: continue to Step 1.

---

## Step 1 — Load state

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`.

If file does not exist → stop: _"No state found for <ticket>. Run /understand-ticket, /plan-ticket, and /implement-ticket first."_

If `phase` is not `implemented` → stop: _"State is '<phase>' — expected 'implemented'. Run /implement-ticket <ticket> first."_

Load into context: `plan.branch`, `plan.branches` (per-repo override map, optional), `plan.commit`, `plan.repos`, `plan.mr_labels`, `implementation.files_changed`, `implementation.ac_validation`, `implementation.self_review`, `implementation.test_guide`, `implementation.test_approved`, `labels`.

**Branch resolution:** for each repo in `plan.repos`, use `plan.branches[repo]` if present, otherwise fall back to `plan.branch`.

**Branch verb check:** extract the verb segment from `plan.branch` (e.g. `feature/PROJ-123_Add_Title` → `Add`). Confirm it is one of: `Implement|Add|Update|Refactor|Remove|Migrate|Enable|Disable|Expose|Extract|Rename|Move|Replace` (feature) or `Fix` (bugfix). (Authoritative list: `FEATURE_VERBS` in `prepare-mr.sh` — keep in sync.)

If the verb is NOT in the list → **stop immediately** before the test gate (Step 2):
_"⚠ `plan.branch` uses an unapproved verb: '<verb>'. Suggest: `feature/PROJ-XXX_<ApprovedVerb>_Title`. Please confirm the corrected branch name and I will update the state file before continuing."_

Wait for user confirmation, update `plan.branch` and `plan.commit` in the state file, then proceed to Step 2.

> **Exception — UI submodule repos.** UI / shared-library submodules use the `PROJ-XXX-short-description` convention (no `feature/`/`bugfix/` prefix, no verb). **Skip this verb check** for those repos — see [`submodule-and-shared-repos.md`](submodule-and-shared-repos.md).

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 2 — Verification approval

**Approval already recorded?** If `implementation.test_approved == true` in the state file (set by the complete-ticket implementation review gate when the user replied "evidence reviewed and approved" — or "tested and approved" on a legacy ticket), do NOT re-present anything. Print:
`"✓ Verification approved at the implementation review gate — proceeding to pre-push checks."`
Then run `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> push-ticket 3 test_approved` and jump to Step 3. (Step 3's unexpected-changes check still guards against the working tree having drifted since approval; if the user mentions anything changed since they tested, void the approval — clear the flag via the state helper — and gate below instead.)

Otherwise:

> **Flow checkpoint** (**before** presenting the guide): `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> push-ticket 2 awaiting_test_approval` — this ensures a context reset always re-presents the guide rather than skipping it.

### 🛑 GATE — FULL STOP. DO NOT RUN ANY GIT COMMANDS.

> This gate is the instance of **REQUIRED: superpowers:verification-before-completion** — push is a
> completion claim, so it requires fresh, reviewed evidence (the approval reply) before any git command.
> The discipline does not weaken the wording below; the explicit "evidence reviewed and approved" reply
> is the required evidence.

**This gate is a safety net** — normally `complete-ticket` runs `verify-ticket` and records approval before push is reached, so this fires only when `/push-ticket` is run directly. Branch on what verification exists:

**(a) AUTO specs exist (`$WORKSPACE_ROOT/e2e/tests/<ticket>/`) but no `verification` block** — verification hasn't run. Do not gate on a manual read of stale specs; tell the user to run **`/verify-ticket <ticket>`** first (it runs the specs + emits the evidence pack), then review the evidence + any MANUAL items and reply **"evidence reviewed and approved"**. Present the MANUAL scenarios (from `test_guide.scenarios`) here so they're not missed.

**(b) Legacy ticket — no specs and no `verification`** — present the persisted manual guide as the fallback. Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.test-guide.md` (authored by implement-ticket Step 8) and present it, prefixed with:

```
Before I create branches and push, please work through the manual test guide:

<full guide content>

Reply "evidence reviewed and approved" (or "tested and approved") to continue.
If anything fails, describe the issue and I will fix it.
```

**Fallback within (b) — no guide file either** (ticket implemented before guides existed, or the file was deleted): author it now using **implement-ticket Step 8 manual-guide authoring rules only** — ask the detail level (Basic / Standard / Full, with a recommendation), apply the every-level rules (concrete expected values; a separate negative-case item per filter/exclusion AC; for sweep/bulk-delete fixes, before/after diagnostic queries plus the mandatory "excluded values survive" data-loss guard), persist via `save-test-guide.sh`, then present as above. Do **NOT** run implement-ticket's flow checkpoints or step transitions — you are still in push-ticket Step 2 and the flow stays `push-ticket 2 awaiting_test_approval`. Say so if the implementation session's knowledge is gone (the guide will be weaker).

**You must receive "evidence reviewed and approved" (or "tested and approved" / clear equivalent) before proceeding.**

> **Flow checkpoint — immediately on receiving approval, before any git command:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> push-ticket 3 test_approved`. Run this first. Only then proceed to Step 3.

- Any previous approval from /implement-ticket does NOT count here. (The only approval that bypasses this gate is the recorded `implementation.test_approved == true` from the complete-ticket review gate — and that path skips this message entirely, at the top of Step 2.)
- Do not create branches, commit, or push under any circumstances until the user replies to this message.

If the user reports a failure (root-cause it before touching code — **REQUIRED: superpowers:systematic-debugging**; the journalled `Root cause` below must be a real cause, not a guess):
1. Journal the failure before fixing — a manual-test failure is a dead-end discovered late and is exactly what must survive a compaction during the fix:
   ```bash
   bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> DEADEND "Manual test failed: <what the user saw>. Root cause: <cause>. Fix: <what changed>"
   ```
2. Fix the issue
3. Re-run build check: `<build command> "$WORKSPACE_ROOT/<repo>/<solution-or-project>" 2>&1 | grep -E "error|^\s+[0-9]+ Error\(s\)" | head -30`
4. Re-validate the affected ACs
5. Update `implementation.ac_validation` in the state file (and clear `implementation.test_approved` if it was set — the approval is void after a fix)
6. If the fix changed any expected result or step, update the persisted guide: read `.claude/tickets/<ticket>.test-guide.md`, write the full updated markdown to `$WORKSPACE_ROOT/<ticket>.test-guide.md` (Write tool), then `bash "$WORKSPACE_ROOT/.claude/scripts/save-test-guide.sh" <ticket> "$WORKSPACE_ROOT/<ticket>.test-guide.md"`
7. Present the guide again

Repeat until approved.

---

## Step 3 — Pre-push checks

**Repo-set reconciliation (run FIRST — the push set comes from what was actually touched, not from trust in the plan):**

Derive the touched-repo set from `implementation.files_changed` (first path segment of each file; map UI SPA/submodule paths to their real repos per the submodule block below). Compare it with `plan.repos`:
- A repo in `files_changed` but **NOT** in `plan.repos` → 🛑 stop: _"⚠ Implementation touched repos outside the plan: <list>. These were never gated at the plan step. Reply 'include' to add them to the push set (I'll update `plan.repos` in the state file), or run /plan-ticket <ticket> to re-gate the expanded scope."_ On 'include', update `plan.repos` (and `plan.branches` if per-repo names are needed) via the state helper before continuing. Without this check, an unplanned repo silently misses the branch, commit, push, and MR — the work stays stranded on the working tree.
- A repo in `plan.repos` with **no** entry in `files_changed` → warn (planned but untouched) and ask whether to drop it from the push set.

**All later steps — sync, branch, commit, push, MR — use the reconciled set wherever they say `plan.repos`.**

Then run these checks for each repo in the reconciled set:

**Submodule & shared repos.** If the reconciled set includes any UI SPA / nested submodule
(`repo-ui`, `repo-ui-app`, `ui-core`, `common-ui`) or a consumer's shared submodule (`api/Shared`, …),
read **[submodule-and-shared-repos.md](submodule-and-shared-repos.md)** — it holds the per-repo bases,
the `PROJ-XXX-short-description` branch-naming exception (Step 1 verb check skipped), the producer→consumer
ordering, the "freshen via `create-branch.sh --from <base>` not `sync-repos.sh`" rule, the shared-first
ordering, and the **never stage the shared submodule pointer** rule. Apply it before the base-freshness check below.

**Base branch freshness check:**

If `plan.mr_target_branch` is set (stacked MR — this ticket's MR targets another feature branch, not the integration branch):
```bash
# Do NOT run sync-repos — it syncs to the integration branch and would put you on the wrong branch.
# Instead, ensure the target branch itself is up to date:
git -C "$WORKSPACE_ROOT/<repo>" fetch origin -q
git -C "$WORKSPACE_ROOT/<repo>" checkout <plan.mr_target_branch>
git -C "$WORKSPACE_ROOT/<repo>" pull
```
If checkout or pull fails, stop and report — the target branch must exist and be current before branching from it.

If `plan.mr_target_branch` is NOT set (normal MR targeting the integration branch):
```bash
bash "$WORKSPACE_ROOT/.claude/scripts/sync-repos.sh" --repos "<plan.repos space-separated>"
```
This pulls the latest base for each affected repo (stash/restore handled automatically). If any repo fails to sync, stop and report before branching — branching from a stale base will create MR conflicts. On a `CONFLICT|` result (stash pop conflicted), root-cause it before acting (**REQUIRED: superpowers:systematic-debugging** — read the conflict, don't blindly resolve), then follow sync-repos' conflict handling — including **proving the stash is redundant (`git stash show -p` vs the working tree + passing build/tests) before any `git stash drop`** (the evidence rule, **REQUIRED: superpowers:verification-before-completion**), stated in the same message as the drop.

**Scoped on purpose — do NOT full-sync here.** The "sync ALL repos" rule belongs to plan-ticket (exploration is cross-repo); at push time implementation is finished and only the repos receiving MRs need a fresh base. Always pass `--repos` exactly as shown — a bare `sync-repos.sh` here wastes minutes and churns repos this ticket never touches.

If the branch **already exists on remote with this ticket's commits AND open MRs already exist** (e.g. the user pushed and opened the MRs manually before this step), do **not** re-create anything — switch to **verify-only**: confirm the committed file set matches `implementation.files_changed`, the commit message matches `plan.commit`, and each MR is mergeable with no conflicts (one `search`/`get_merge_request` call to the Git host's MCP). If all check out, skip Steps 3–4's branch/commit/push entirely and go to Step 6 (mark shipped), recording the MR URLs in the state. If the committed set diverges from the plan (wrong files, `.md`/shared pointer staged, extra noise), surface the difference and stop.

If you are pushing a branch that **already exists** (e.g. the MR is open and the branch is behind target), do not sync — instead, stop and tell the user: _"Your branch is behind origin. Run `/resolve-conflicts <ticket>` to rebase before pushing."_

**Unexpected changes check:**
```bash
git -C "$WORKSPACE_ROOT/<repo>" status --short
```
Compare the working tree against `implementation.files_changed` from the state file.
- Files in `files_changed` but not in working tree changes → warn: "Expected changes to <file> but found none."
- Files in working tree changes but NOT in `files_changed` → surface them: "Found unexpected changes in <file> — should this be staged?"
  Wait for user to confirm yes/no for each unexpected file before staging.

  **Common noise files that are almost always excluded** (group them and offer "exclude all" rather than asking one-by-one): local run/launch configs, environment/app settings files, lock files (e.g. `package-lock.json`), local certs. Only ask individually for real source files (e.g. `.cs`, `.ts`, `.tsx`, `.sql`) not in the plan.

**DB script check** (database repo only):
For each DB script file in `implementation.files_changed`, open it with the **Read tool** and confirm it has real content — not an empty file or a leftover stub.
If empty or missing → stop: _"⚠ DB script <file> has no content. Write the script before pushing."_
Do not proceed until the DB script has content.

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 4 — Branch, commit, push, MR links

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> push-ticket 4 pushing`

**Runs only after all pre-push checks pass.**

**UI lint gate (before any commit).** If `implementation.files_changed` includes any file under a UI SPA (`web/repo-ui` or `web/repo-ui-app`), run the linter on that SPA — and the style linter if any stylesheet changed — and require a clean result before committing (the build/type-check does not cover these; review/CI enforces them):
```bash
(cd "$WORKSPACE_ROOT/web/repo-ui" && npm run lint)    # or .../repo-ui-app
(cd "$WORKSPACE_ROOT/web/repo-ui" && npm run slint)   # only if a stylesheet changed
```
If either reports violations, fix them (keep any `--fix` scoped to your changed lines) and re-run before committing.

For each repo in `plan.repos`, run in sequence:

```bash
# 1. Create branch
# Replacing an authorized stale remote branch: if the plan/state records that an existing remote
# branch is to be REPLACED (stale work the user explicitly authorized replacing at a gate),
# create-branch.sh will refuse with "ERROR|branch already exists on remote" — delete it first:
#   git -C "$WORKSPACE_ROOT/<repo>" push origin --delete <branch>
# Never delete a remote branch without that recorded authorization.
# If plan.mr_target_branch is set, pass --from so the branch starts from the right base:
bash "$WORKSPACE_ROOT/.claude/scripts/create-branch.sh" --repo <repo> --branch <plan.branch> [--from <plan.mr_target_branch>]

# 2. WIP commit check — now that the branch exists, check its history
# git -C "$WORKSPACE_ROOT/<repo>" log --oneline | head -5
# If any commit message contains "WIP": warn "⚠ <repo> has WIP commits that will appear in the MR.
# Squash them before pushing? (recommended)" — wait for user confirmation.

# 3. Stage specific files only — use implementation.files_changed list
# git -C "$WORKSPACE_ROOT/<repo>" add <file1> <file2> ...
# Submodule pointers — test: "did YOU change this submodule's content THIS ticket?"
#   YES (e.g. you committed ui-core on its own branch) → you MUST `git add <submodule>` in the parent so
#       the parent references your submodule commit (a stacked MR). Omitting it points the parent at the OLD
#       submodule → broken build.
#   NO (pointer shows modified only from `npm install` / pre-existing drift — e.g. common-ui,
#       ui-collaboration-core) → leave it UNSTAGED (noise).
#   A shared submodule / vendored dependency pointer is NEVER staged, regardless.
# git -C "$WORKSPACE_ROOT/<repo>" commit -m "<plan.commit>"  ← use the EXACT plan.commit: ONE line, "PROJ-XXX Verb …".
#    Do NOT append a "Co-Authored-By:" trailer or any body. Commits are single-line — this OVERRIDES the
#    global Claude Code default. prepare-mr.sh filters Co-Authored-By out of its no-body check, so a PASS
#    there does NOT mean the trailer is wanted (team uses it 0× on the integration/main branches).

# 3b. CURRENT-WITH-TARGET GATE — NEVER push (or share an MR link for) a branch that is behind its
#     MR target. The target advances while you work, so the Step-3 base-freshness check is NOT enough on
#     its own — re-verify at the LAST moment, right before push:
#       TARGET = plan.mr_target_branch if set, else the repo's default integration branch (what prepare-mr resolves)
#       git -C "$WORKSPACE_ROOT/<repo>" fetch origin -q
#       behind=$(git -C "$WORKSPACE_ROOT/<repo>" rev-list --count <branch>..origin/<TARGET>)
#     If behind != 0, bring the branch current BEFORE pushing (do not push a behind branch):
#       git -C "$WORKSPACE_ROOT/<repo>" rebase origin/<TARGET>          # stash launch/noise configs first if it blocks
#       git -C "$WORKSPACE_ROOT/<repo>" submodule update --init Shared  # a moved target can move the shared submodule pointer
#       rebuild + rerun the affected tests (the rebase replays your commit onto new code) → re-confirm green
#       (the green claim needs fresh output — REQUIRED: superpowers:verification-before-completion;
#        if the rebase introduces a failure, root-cause it via REQUIRED: superpowers:systematic-debugging
#        before re-attempting — a rebase conflict/break is not a "retry until it passes" situation)
#     then push with --force-with-lease (the rebase rewrote the tip), and re-check behind == 0.
#     This gate holds EVEN when shipping ad-hoc (hand-rolled git, outside a full /push-ticket run) — it is
#     exactly what prevents an MR that opens "N commits behind target". Do not hand-roll a push that skips it.

# 4. Push
bash "$WORKSPACE_ROOT/.claude/scripts/push-branch.sh" --repo <repo> --branch <plan.branch>

# 5. Get MR URL — pass --target if plan.mr_target_branch is set (stacked MRs)
#    Otherwise omit --target and the script resolves the default integration branch.
if plan.mr_target_branch is set:
  bash "$WORKSPACE_ROOT/.claude/scripts/prepare-mr.sh" --repo <repo> --branch <plan.branch> --target <plan.mr_target_branch>
else:
  bash "$WORKSPACE_ROOT/.claude/scripts/prepare-mr.sh" --repo <repo> --branch <plan.branch>

# ⛔ NEVER use the Git host's MCP tool (create_merge_request) to open the MR.
# Your job is ONLY to output the URL from prepare-mr.sh for the user to open themselves.
# Creating the MR is the user's action — it notifies reviewers and is visible to the whole team.
```

---

## Step 5 — Final output

```
✓ PROJ-XXX complete — open these MRs:

  api       → <URL>
  web       → <URL>
  database  → <URL>

If `plan.mr_target_branch` is set, note it clearly:
> ⚠ Stacked MR — target is `<plan.mr_target_branch>`. The URL above already uses the correct target.

Labels to add on each MR: <from plan.mr_labels>

---
MR description (copy-paste):

## Summary
<One-sentence summary of what this MR does and why>

## Changes
- <key change 1>
- <key change 2>
- <key change 3>

## How to test
- <step-by-step test instruction for AC 1>
- <step-by-step test instruction for AC 2>

## Notes
<Only include relevant sections below — omit the rest>
- **DB migration:** <is it additive/safe, any manual steps needed?>
- **Breaking change:** <what breaks, what other repos/teams need to update>
- **Config change:** <which app settings keys were added/changed>
```

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 6 — Mark shipped

Update state file: set `phase` to `shipped` and `flow` to `null` (save-state.sh stamps `saved_at`) — this skill is complete.

Then tell the user:

```
✓ Ticket shipped.
```

Do not prompt for /improve-skills here — /complete-ticket handles that as Step 5.
