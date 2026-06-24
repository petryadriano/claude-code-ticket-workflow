---
description: Step 5 of 5 — Reflect on the completed ticket session and apply concrete improvements to skills and scripts. The workflow gets smarter after every ticket. Usage: /improve-skills
arguments:
  - name: context
    description: Optional summary of what happened. If omitted, reflects on the current session context.
    required: false
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Glob
  - Grep
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Reflect on what happened during this session and propose concrete improvements to the skill system.

> **Scope guard — this step reflects, it does not implement ticket scope.** `improve-skills` only ever edits **skills / scripts / process** (and memories / repo `CLAUDE.md`). If, during or after this step, the user asks for a **ticket code change**, a fix, or to investigate the ticket's runtime behavior, **stop and hand it back to the flow**: that is a new increment, not reflection. Say so and route to `/complete-ticket <ticket>` (which refreshes repos + ticket and runs understand → plan → implement → push with its gates). Do **not** hand-roll the code change here — doing ticket work under improve-skills skips every gate and is exactly how an off-flow, behind-target push happens.

> **Coverage & gaps.** When this reads across repo-local `CLAUDE.md` files and the standards-repo clone, apply the same mindset: if a file can't be read or the clone is stale/dirty, say so explicitly and skip it deliberately rather than silently. **And when you add or extend any skill that reads external content, give it its own Coverage & gaps callout scoped to exactly what that skill reads** — each skill owns its mindset; there is no shared doc to keep in sync.

Skills directory: `$WORKSPACE_ROOT/.claude/skills/`
Scripts directory: `$WORKSPACE_ROOT/.claude/scripts/`

## Required disciplines (Superpowers substrate)

This skill is the **reflection-and-share** workflow. The generic discipline for the work it
produces is delegated to Superpowers skills — do not re-derive it here. Load and follow each at the
point marked below:

- **REQUIRED: superpowers:writing-skills** — governs **every skill/script edit this step proposes and applies** (Steps 4 & 5, and any skill fix surfaced in Step 2). A skill edit is not a plausible-looking diff: classify the baseline failure and *match the form to it* (discipline failure → prohibition + rationalization table + red flags; wrong-shaped output → positive recipe; omission → a structural slot; conditional behavior → a predicate), respect its Iron Law (an edit needs a failing test first — the baseline behavior the change fixes), and apply its SDO rules whenever you touch a `description`. Its own required background is **superpowers:test-driven-development**.
- **REQUIRED: superpowers:systematic-debugging** — in the Step 2 command audit, root-cause each failed/retried command before deciding a skill/script edit is the fix (an environmental failure needs the precondition fixed, not a skill change).
- **REQUIRED: superpowers:verification-before-completion** — evidence before any "✓ Applied" claim (Step 5) and before claiming the improvement branch is pushed (Step 5b); confirm the edit/commit/push actually happened, don't assert it.

Domain-specific guardrails these do **not** cover stay inline at their steps: the linkage/freshen checks, the "never hardcode ticket business logic into a generic lifecycle skill" rule, the repo-`CLAUDE.md` quality bar, the memory path/format, and the Step 5b share gate.

---

## Step 0 — Confirm improvements will reach the team (linkage check)

The skills/scripts you're about to edit are **junctioned** to the shared standards clone — so edits flow into that clone and ship to the team via MR (Step 5b). That only holds if **this workspace is actually linked**. Verify before doing any work:

```bash
MARKER="$WORKSPACE_ROOT/.claude/standards-root"
if [ -f "$MARKER" ] && [ -d "$(tr -d '\r\n' < "$MARKER")/.git" ]; then
  echo "LINKED → $(tr -d '\r\n' < "$MARKER")"
else
  echo "NOT LINKED"
fi
```

- **LINKED** → continue; edits land in the clone and Step 5b can push the improvement branch (the user creates the MR from the link it hands over).
- **NOT LINKED** (no `standards-root` marker, or `.claude/skills` is a real directory instead of a junction into the clone) → 🛑 **STOP.** This workspace is a standalone copy: any edit here is a **dead end** — it will not reach the team and will be **overwritten** the next time the workspace is provisioned from the standards repo. Tell the user, verbatim:
  > _"This workspace isn't linked to the standards repo, so improvements made here won't reach the team and would be wiped on re-provision. Run `/setup` to link it, or make the change directly in the standards-repo clone."_

  Do not proceed until the workspace is linked (or the user explicitly accepts a throwaway, local-only edit).

---

## Step 0b — Freshen the standards clone (proposals must target the LATEST skills)

The skills you're about to improve may have changed since this session loaded them — by an
improve-skills run in **another workspace** (junctions share one working tree, visible on disk
immediately) or by **merged team improvements on the remote** (on disk only after a pull). Before
investigating:

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/update-standards.sh"
```
- `BEHIND|<n>|<branch>` → offer the pull (`update-standards.sh --pull`) so proposals are written against the team's latest version — otherwise the MR in Step 5b will conflict or undo merged work. Then continue.
- `DIRTY|…` → expected (local improvements awaiting an MR — possibly from other sessions); they are part of the current state Step 1 reads. Continue without pulling.
- `UPTODATE` / `NOMARKER` → continue.

---

## Step 1 — Read current skill and script files (fresh — never from memory)

> **The skill versions loaded earlier in this session are stale by definition.** A skill invoked at
> ticket start may since have been edited by another session or a pulled update. Every `CURRENT`
> block in a Step-4 proposal must come from a **fresh Read performed in this step** — never from
> what's remembered in context: a proposal formed against a stale version can re-introduce a problem
> another session already fixed, or "fix" something that no longer exists. If a listed file is
> missing or new skills exist, `Glob` `.claude/skills/*/SKILL.md` and `.claude/scripts/*` for the
> real set — the lists below can lag.

Read files in two passes to avoid loading everything unnecessarily:

**Pass 1 — always read (the 6 lifecycle skills are always relevant):**
```
.claude/skills/complete-ticket/SKILL.md
.claude/skills/understand-ticket/SKILL.md
.claude/skills/plan-ticket/SKILL.md
.claude/skills/implement-ticket/SKILL.md
.claude/skills/push-ticket/SKILL.md
.claude/skills/improve-skills/SKILL.md
```

**Pass 2 — read only if the session touched them or if a proposal requires it:**
```
.claude/skills/new-branch/SKILL.md
.claude/skills/prepare-mr/SKILL.md
.claude/skills/sync-repos/SKILL.md
.claude/skills/resolve-conflicts/SKILL.md
.claude/skills/address-review/SKILL.md
.claude/scripts/sync-repos.sh
.claude/scripts/create-branch.sh
.claude/scripts/prepare-mr.sh
.claude/scripts/detect-wip.sh
.claude/scripts/push-branch.sh
.claude/scripts/rebase-branch.sh
```

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 1b — Read the ticket context journal (if one exists)

If `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` exists for the ticket worked this session, read it. It is a distilled record of exactly what this reflection step wants:
- `DEADEND` entries → approaches that failed. Each is a candidate for a plan-ticket/implement-ticket improvement so the next ticket avoids the same dead-end.
- `DECISION` entries → choices and their reasons; check whether any recurring decision should become a documented convention or a memory.
- `QUESTION` entries that recurred across tickets → a sign the understand-ticket clarity check or a CLAUDE.md is missing guidance.

Use the journal as primary evidence in the command/friction audit below — it captures friction that the raw transcript buries.

---

## Step 2 — Command audit (always run first)

Scan the session for every command that failed, was retried, or required a workaround. Fix each one before anything else — these are the highest-ROI improvements because they cause wasted round-trips every time.

**For each failed or retried command, record:**
```
Command: <exact command that failed>
Error:   <what it returned>
Fix:     <the working command that replaced it>
File:    <skill or script to update>
```

Check the session against all three command categories — tracker MCP calls, git commands, and bash/shell
commands — using the known-cause catalog in **[command-audit-catalog.md](command-audit-catalog.md)** (the
list of recurring failures and their known-good replacements; add new entries there as you find them).

Before recording a command as a skill/script fix, **REQUIRED: superpowers:systematic-debugging** — read the
complete error and find why it failed. An environmental failure (dirty tree, missing restore, wrong base)
needs the precondition fixed, not a skill edit.

For each genuine fix found: update the relevant script or skill immediately, before moving to Step 3 — and
when the fix is to a **skill**, apply it under the writing-skills discipline (Step 4/5 below), not as a raw diff.

---

## Step 3 — Reflect on the session

Review the full session context (or `$context` if provided) and look for:

**Things that could be scripted (token waste):**
- Did the LLM reconstruct logic that could live in a script?
- Were there repeated git/shell commands that ran the same way every time?
- Did the LLM do file parsing that a grep/sed script could do faster?

**Things that caused friction or errors:**
- Did any script fail or produce unexpected output?
- Did the LLM have to ask questions that could be answered from the tracker or the codebase automatically?
- Were there edge cases not handled by the current scripts?
- Did any phase need to be repeated (build failure, AC gap, test failure)?

**Things that were unclear in the skill instructions:**
- Did the LLM hesitate or take a wrong turn because a phase was ambiguous?
- Were there decisions that needed to be made that the skill should pre-answer?

**Patterns discovered in this codebase:**
- New file/folder conventions found while exploring?
- New repo-specific patterns that should be documented in that repo's CLAUDE.md?
- Recurring code structures that a future LLM should know about?

**Improvements to the ticket lifecycle:**
- Was a phase too slow? Could it be split or parallelised?
- Was a gate too aggressive or not aggressive enough?
- Verification: was the AUTO/MANUAL split right? Did the AUTO specs actually prove the ACs, and did the coverage matrix catch every variation dimension (or did one case masquerade as full coverage)? Did the evidence pack convince at the review gate? Was the MANUAL guide (for what couldn't be automated) at the right detail level?

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 4 — Produce improvement proposals

**Skill and script proposals follow the writing-skills discipline — REQUIRED: superpowers:writing-skills.**
A proposal is not just a better-sounding paragraph. Before writing a `--- PROPOSED ---` block for a skill:
- **Classify the baseline failure** this session actually exposed, and **match the guidance form to it** — discipline failure (knew better, did it anyway) → prohibition + rationalization table + red flags; wrong-shaped output → a positive recipe stating what the output IS; an omitted element → a structural slot in the template the author fills; conditional behavior → a predicate on something observable, not an exemption clause.
- **Honor its Iron Law** — an edit needs a failing test first. The baseline behavior the change fixes *is* the test: for a discipline edit, that's the exact rationalization you observed this session (cite it), not a hypothetical one. No observed failure → no edit.
- **Touching a `description`?** Apply its SDO rules (triggering conditions only; never summarize the workflow).

For each improvement found, produce a structured proposal:

```
## Improvement N: <short title>

Type: script | skill | memory | repo-claude-md
File: <exact file path>
Problem: <what went wrong or was inefficient>
Proposal: <what to change and why>

--- CURRENT ---
<relevant current content>

--- PROPOSED ---
<the new content>
```

Group proposals by impact:
- **High** — prevented correct behavior or wasted significant tokens
- **Medium** — caused friction or minor errors
- **Low** — polish, clarity, or nice-to-have

**Guardrail — never hardcode ticket-specific business logic into a generic skill.** These lifecycle skills are reused by every ticket. Do not bake in specific magic values (enum IDs, status codes, value lists), domain rules, table/column names, or one-ticket SQL. Keep skill guidance **principle-based** ("derive the set from the ticket; add a negative test for excluded values"); the concrete values belong in the ticket/plan/code, not frozen in the skill. If a past proposal added such specifics, treat removing them as a high-impact fix — stale hardcoded business logic silently propagates the original bug to every future ticket.

**A/B against a known-good reference — the highest-yield reflection.** When the ticket has a known-good
counterpart — the same feature implemented in another repo/workspace, a sibling or prior ticket that solved
the same shape, or a reference implementation — **read it and diff the produced code against it, judging by
the code rather than by which gates went green.** In practice this A/B is the single check that catches what
every green gate misses (a missing filter, duplicated logic, an over-built path, a precedence that's
unverified at runtime). Classify each divergence as a deliberate, explainable difference *or* a defect /
skill-gap to encode as a proposal below. A "all gates passed" session is not trusted as good until its
output has been compared against a reference where one exists. (Beware the inverse error: "the reference is
leaner, so copy it" — leaner is not better when the reference also lacks a depth-check; compare on
correctness and depth, not line count.)

Show all proposals before applying any. Ask:
_"Apply all high-impact changes automatically? I'll show you medium and low ones individually."_

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 5 — Apply approved changes

Apply changes in order of impact. For each:
- Show a clear diff (old → new)
- Apply the edit
- Confirm `✓ Applied: <file>` **only after** re-reading or diffing to prove the content actually changed — **REQUIRED: superpowers:verification-before-completion**; the Edit tool returning is not proof the file now reads the way you intended.
- If the Edit fails with "file has been modified since read" (another session wrote it mid-run), **re-read the file and re-derive the diff** against the new content — confirm the problem still exists before re-applying; never force the old edit over someone else's change.

For **repo CLAUDE.md changes**: these go in the individual repo's `CLAUDE.md` (e.g. `$WORKSPACE_ROOT/api/CLAUDE.md`), not the root. Read the existing file first to ensure the addition fits the existing structure. **Quality bar for entries:** durable, non-obvious, repo-specific. Do NOT add component-prop API docs, port numbers, lint-rule names, or anything discoverable in 30 seconds by reading the source — those go stale and are greppable; the durable part is the principle (e.g. "read a shared component's source before using a non-obvious prop"), not the catalog.

For **memory changes**: write to the Claude Code project-memory directory for this workspace — `~/.claude/projects/<project-key>/memory/` — following the memory format (frontmatter + body), then update its `MEMORY.md` index. `<project-key>` is the workspace path with **every non-alphanumeric character** replaced by `-` (e.g. `C:/source/ws1` → `C--source-ws1`, and `C:/source_test/ws1` → `C--source-test-ws1` — note the underscore also becomes `-`). Never hardcode a username or absolute home path — resolve it from `~`/`$HOME` so it works for every developer.

---

## Step 5b — Share improvements with the team (gated MR to the standards repo)

Skills and scripts are **junctioned** to the shared standards-repo clone, so the edits you just
applied already live in that clone's working tree (uncommitted, on its default branch). Offer to
**push an improvement branch** so the team gets them — branch, commit, push, then hand the user the
MR-creation link + a paste-ready description. **The user always creates the MR themselves**, and
nothing is pushed without their explicit approval. (Memory and per-repo `CLAUDE.md` changes are not
part of the standards repo.)

**1 — Locate the clone.** Read `$WORKSPACE_ROOT/.claude/standards-root` (written by `/setup`); call it
`$STD`. If the marker is missing, tell the user you can't prepare the branch, print the manual git
steps instead, and skip to Step 6.

**2 — Anything to share?** Check for pending skill/script changes:
```bash
git -C "$STD" status --porcelain -- workspace/.claude/skills workspace/.claude/scripts
```
If this is **empty**, there's nothing to push — say _"No skill/script changes to share."_ and
**skip the rest of this step** (do not branch, commit, or prompt). Only continue if it lists files.

**3 — Show what would be shared.** The share set is **only the files this run's applied proposals
touched** (the Step 5 list) — never the clone's whole dirty tree, which may carry other sessions'
not-yet-shared improvements:
```bash
git -C "$STD" diff -- <file1> <file2> …
```
Present that diff. List any **other** uncommitted files from step 2's status separately as
"left local — other sessions' work, untouched by this MR". Then the proposed share:
```
Share these skill/script improvements with the team?

  Files:      <this run's files>
  Left local: <other uncommitted files, or "none">
  Branch:     improve/<ticket>_<short-slug>   (off the default branch)
  Commit:     "<ticket> Improve <short description>"
  MR:         you create it — I'll push the branch and hand you the link + description

Reply "push branch" to proceed, or "skip" to keep everything local.
```

### 🛑 MANDATORY GATE — nothing is pushed without the user's explicit approval.

> No `git checkout -b`, `git add`, `git commit`, or `git push` may run in the standards clone until
> the user replies **"push branch"** in THIS session. This lock holds even on a resume after `/compact`,
> even if the diff was already shown, and even if a previous session got as far as this prompt.
> Silence, "looks good", or a generic "ok" do NOT count — only "push branch". On anything else the
> edits stay local in the clone — that is a valid, complete outcome, not a failure.

**4 — On "push branch" only:**
```bash
DEF=$(git -C "$STD" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
git -C "$STD" checkout -b "improve/<ticket>_<slug>"
# Stage ONLY this run's files — a blanket `git add skills/ scripts/` would bundle other
# sessions' uncommitted improvements into this MR.
git -C "$STD" add <file1> <file2> …
git -C "$STD" commit -m "<ticket> Improve <short description>"
git -C "$STD" push -u origin "improve/<ticket>_<slug>"
git -C "$STD" checkout "$DEF"   # back to default; other sessions' uncommitted work stays in the working tree
```
Confirm the push actually landed (the `push` output reports the new remote branch, or
`git -C "$STD" ls-remote --heads origin "improve/<ticket>_<slug>"` returns it) before handing over the
link — **REQUIRED: superpowers:verification-before-completion**; never construct an MR link for a branch
that didn't push. Then build the MR-creation URL — ⛔ **never create the MR itself** (no MCP `create_merge_request`, no
`curl -X POST`; same rule as push-ticket — creating the MR is the user's action):
```bash
echo "https://<git-host>/org/ai-development-standards/-/merge_requests/new?merge_request%5Bsource_branch%5D=improve%2F<ticket>_<slug>&merge_request%5Btarget_branch%5D=$DEF"
```
Hand the user, in one message:
- the **URL** (source/target prefilled by the Git host),
- the **title**: `<ticket> Improve <short description>`,
- a **paste-ready MR description**:
```
## Summary
<one line: which part of the workflow got smarter and why>

## Improvements
- <skill/script> — <what changed> (<the session friction it fixes>)
- …

## Origin
Reflections from <ticket>.
```
The improvement is **in review** once the user creates the MR — it returns to every workspace on
merge + the next start-of-ticket pull. To keep using it locally before merge:
`git -C "$STD" checkout "improve/<ticket>_<slug>"`.

On **"skip"**: leave the edits uncommitted in the clone (they stay active locally); a later
`improve-skills` run or a manual MR can still share them.

---

## Step 6 — Summary

After applying:

```
Improvements applied: N
  High:   X changes to <files>
  Medium: Y changes to <files>
  Low:    Z skipped / deferred

Next time /complete-ticket runs, it will benefit from:
- <bullet per meaningful change>
```
