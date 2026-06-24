---
description: Step 2 of 5 — Sync repos, explore the codebase, and build an implementation plan for a ticket. Reads state saved by /understand-ticket and saves the approved plan to disk. Usage: /plan-ticket PROJ-XXX
arguments:
  - name: ticket
    description: Ticket ID (e.g. PROJ-123) or full tracker URL
    required: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - Agent
  - EnterPlanMode
  - ExitPlanMode
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Step 2 of 5 in the ticket lifecycle.

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

This skill is the **domain** layer for turning an understood ticket into an approved plan. The
generic engineering discipline is delegated to Superpowers skills — do not re-derive it here. Load and
follow each at the point marked below:

- **REQUIRED: superpowers:writing-plans** — the generic plan-construction discipline: map the files each task touches, design focused units with well-defined interfaces, bind tasks to exact signatures, and write a plan with no placeholders that an engineer with zero codebase context could execute (Steps 3 & 7). Per the test-timing decision, the plan must anticipate **test-first** implementation — each unit's task carries its own failing-test-first cycle. What this skill **keeps** on top of it: the plan JSON schema, the producer-order `repos` rule, and the AC-by-AC approval gate (Steps 7 & 8) — those are this product's contracts, not delegated.
- **REQUIRED: superpowers:brainstorming** — when a non-trivial architectural decision needs the design explored with the user before it's settled: explore intent, propose 2–3 approaches with tradeoffs, get approval before committing the choice to the plan (Step 5). Use it for the decisions Step 5 names as requiring it (new endpoints, data model changes, cross-repo contracts, caching, async messaging).
- **REQUIRED: superpowers:verification-before-completion** — evidence before *any* "this contract is X / this is the only Y / this matches the existing pattern" claim (Step 3 consumed/produced-contract ledger, and the coverage claims at the Step 7 gate). Instance: bind every contract to the producer's **real code** (read it now), and cite the grep/read behind any "only" / "no" / "follows the pattern" assertion — never the tracker/wiki description.

Product-specific mindsets these do **not** cover, active throughout: multi-repo / database / submodule
conventions, environment-specific configuration, and security-by-default (every new endpoint authorized,
every input validated) — these stay inline at their steps.

---

> **Journal in the moment.** The instant a real architectural decision (with *why*), a rejected approach (`DEADEND`), or a constraint the user states in passing occurs, append one line via `append-journal.sh`. Do it as it happens — not saved for later — because `/compact` can fire mid-step and only what's already on disk survives. A short ticket may produce zero entries; that's correct, not a miss. See the journal note in `complete-ticket`.

---

## Step 0 — Flow resume check

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. Check `state.flow`:

- If `state.flow.active_skill == "plan-ticket"`: first read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` if it exists (restores decisions, dead-ends, and open questions from before the context reset — honor every `DEADEND`, surface unresolved `QUESTION`s). Then print `"↩ Resuming plan-ticket from: <step_label>"` and jump directly to that step.
- If `state.flow.active_skill` is set to a **different** skill: stop — `"⚠ <ticket> shows <other-skill> was mid-execution (step: <step_label>). Run /<other-skill> <ticket> to complete it first."`
- If `state.flow` is absent or null: continue to Step 1.

---

## Step 1 — Load state

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`.

If the file does not exist → stop: _"No understanding found for <ticket>. Run /understand-ticket <ticket> first."_

If `phase` is not `understood` → stop: _"State is '<phase>' — expected 'understood'. Check the state file or re-run /understand-ticket."_

Load into context: title, goal, ACs (all of them), labels, epic constraints, dependencies (what was built), proposed repos, comments, attachments.

> **Coverage & gaps.** Before exploring code, check what `understand-ticket` actually read (tracker fields, ACs, comments, **attachments**, **the wiki**, **mockups**) and **re-attempt anything left as a gap** — attachments via `fetch-attachment.sh` + token, mockups via `WebFetch`, wiki pages via the tracker's MCP. During exploration, if an expected symbol/file/repo isn't found, widen the search across all repos + the shared submodule before concluding it's absent; if still missing, say so. Show a one-line coverage status before the plan gate — never plan over silent gaps.

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 2 — Sync repos

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> plan-ticket 2 syncing_repos`

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/sync-repos.sh"   # no --repos — sync ALL repos
```

Sync **everything**, not just `proposed_repos`: Step 3 explores **across** repos — producer contracts, shared-submodule models, precedents in sibling services — and a stale side repo yields stale conclusions (a confidently wrong plan the AC gate can't catch, because the user reviews the same stale evidence). All repos are already cloned, so a full sync is a parallel fetch + fast-forward pulls — a minute or two, once per ticket, at the point where freshness matters most. The shared submodule syncs automatically under its parent repos (read shared models via `<parent-repo>/<shared-submodule>/…`). Parse results. If any repo fails to sync:
- List which repos failed and why.
- If a failed repo is in `proposed_repos` **or owns a contract this ticket consumes**, stop and ask: _"The following repos failed to sync: <list>. Is it safe to continue without them, or should we resolve this first?"_ Wait for the answer.
- A failed **side** repo (not in the plan, no consumed contract) is noted as stale-but-skipped — continue, but flag it if Step 3 ends up reading precedents from it.

**After all repos sync successfully → go directly to Step 3. Do not ask the user anything.**

---

## Step 3 — Explore the codebase

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> plan-ticket 3 exploring`

Use the loaded tracker context to guide exploration. Start from `proposed_repos` in the state file — treat them as the initial set and expand if exploration reveals more repos are affected.

The generic plan-construction discipline that exploration feeds — map the files each task touches, design focused units, bind to exact signatures — is **REQUIRED: superpowers:writing-plans** (applied here and at Step 7). What is product-specific is **what** to read in each repo and **how** to verify a contract against real code.

**Work through the exploration recipes in [codebase-exploration.md](codebase-exploration.md)** for each repo — it holds the per-repo always-do list, the **consumed/produced-contract verification gate** (read the producer's/consumer's real code, including in-flight branches; record a verification-ledger line per contract — a do-it-now gate, not "verify later"), the ORM-model nav-property and analogue checks, the DB-script (`db_script_required`) checks, and the per-label expansions (`Breaking_Changes`, `Configuration`, events/async messaging). It also carries the **Grep/Glob/Read-not-raw-shell** rule (and how to propagate it to Explore subagents) and the close-out note for repos added beyond `proposed_repos`.

The contract-verification ledger is the instance of **REQUIRED: superpowers:verification-before-completion** — bind every consumed/produced contract to real code now, and never assert a shape from the tracker/wiki description. The ledger is a required plan section (Step 7) and a gate blocker (Step 7 gate).

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 4 — Security and authorization design

Before writing the plan, answer these explicitly:

- **New endpoints:** what role/permission is required? Is `[Authorize]` with a policy, or `[AllowAnonymous]` with justification?
- **New data returned:** does the response expose fields that should be restricted based on caller role or environment?
- **Object-level access:** if the ticket operates on a resource by ID, how is ownership/environment scoping verified?
- **Input sources:** what inputs come from the caller? Are they validated at the boundary?

Record the authorization approach in the plan. If the answer to any item above is "unclear", flag it and ask the user before continuing.

---

## Step 5 — Efficiency and design check

Before writing the plan, ask:
- **Is the change even NECESSARY — and where does the behavior actually run?** Trace the runtime data-flow that produces the target behavior end to end (read the read-time / client / async layers, not just the persistence layer you intend to edit). If another layer already produces the result, the change is **redundant — do not plan it**; a change is justified only if the behavior would be wrong or absent without it. (This flow once planned + implemented an entire ticket that a read-time + save path already delivered — caught only at verify, after a wasted implementation. Confirm necessity HERE, before any code is written; `verify-ticket`'s negative-control discipline is the verification-time backstop for the same trap.)
- Is there existing code that already does part of this? Can it be reused or extended?
- Is the simplest approach sufficient, or does complexity add real value?
- Is the design testable — are dependencies injected and mockable without hitting real infrastructure?
- Does any AC require cross-repo coordination? If so, define the exact contract now (DTO shape, endpoint signature, or message schema) — do not leave it implicit.
- Are there edge cases in the ACs the obvious approach would miss?
- What should be logged for observability? Key entry points, errors, and significant state transitions.
- **Repo implementation order:** if one repo produces a type, interface, or endpoint that another repo consumes, the producer must be listed first in the plan's `repos` array — implement-ticket processes them in order.

**Regression fixes (Defect ticket type where a previous version worked correctly):**
When fixing a regression, validate the proposed behavior against the working reference (UAT / previous version) — not just what is technically correct.
- Reuse existing messages, constants, and code paths where they apply rather than introducing new ones
- Only introduce new behavior (new constants, new messages, new flows) when the reference behavior is genuinely insufficient for the fix
- If reusing an existing construct, note it explicitly: _"UAT handled this via X — reusing X to match."_
- If proposing new behavior that differs from UAT, flag it explicitly and confirm with the user before proceeding

For any non-trivial architectural decision, explore the design with the user before committing it to the plan — **REQUIRED: superpowers:brainstorming**: explore intent, present **2 approaches with tradeoffs**, lead with your recommendation, and get approval before settling. Required for: new endpoints, data model changes, cross-repo contracts, caching, async messaging. (This is the design-exploration loop only — the plan itself is still gated AC-by-AC at Step 7, not by brainstorming's spec gate.)

> **Journal:** When a decision is settled (here, or a divergence flagged against the ticket/UAT reference above), record the choice *and the why* — not just what was picked. The reasoning is what lets a post-compaction resume avoid relitigating or contradicting it.
> ```bash
> bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> DECISION "Chose <X> over <Y> because <reason>"
> ```
> If an approach was explored and rejected, record it as a dead-end so it is not retried:
> ```bash
> bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> DEADEND "<approach> rejected — <why it doesn't work here>"
> ```

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 6 — Determine branch name

All repos use the **same** branch name and commit message:

- Feature: `feature/PROJ-XXX_Verb_Short_Title` — verb **must** be exactly one of: `Implement`, `Add`, `Update`, `Refactor`, `Remove`, `Migrate`, `Enable`, `Disable`, `Expose`, `Extract`, `Rename`, `Move`, `Replace`. Default: `Implement` for new functionality, `Update` for changes. **Do NOT use any verb outside this list.** If the ticket title uses a word like "Instrument", "Wire up", "Document", or "Hook up", map it to the nearest approved verb (usually `Implement` or `Add`). This list is enforced by `prepare-mr.sh`; a mismatch at push time requires a branch rename, commit amend, and force push.
- Bugfix: `bugfix/PROJ-XXX_Fix_Short_Title` — always `Fix`
- Commit: branch suffix with underscores → spaces, e.g. `PROJ-XXX Implement Short Title`
- First word after ticket number must be capitalised. Single line — no body.

**Per-repo branch names:** If repos have genuinely different changes (e.g. different bugfix scopes with different names), record per-repo names in `plan.branches` as a map in addition to `plan.branch`. push-ticket reads `plan.branches[repo]` first and falls back to `plan.branch`.

Example for a two-repo bugfix with different branch names:
```json
"branch": "bugfix/PROJ-XXX_Fix_Primary_Fix",
"branches": {
  "api":      "bugfix/PROJ-XXX_Fix_Api_Side",
  "database": "bugfix/PROJ-XXX_Fix_Db_Side"
}
```

**Stacked MR check — run for each repo in plan.repos:**

For each done dependency in `state.dependencies`, check if its feature branch is still active on remote and hasn't landed on the develop base:

```bash
git -C "$WORKSPACE_ROOT/<repo>" fetch origin -q
# Does the dependency's branch exist on remote?
git -C "$WORKSPACE_ROOT/<repo>" branch -r | grep "origin/feature/PROJ-<dep-ticket>"
# Is it ahead of the develop base (i.e. not yet merged)?
git -C "$WORKSPACE_ROOT/<repo>" log "origin/<develop-base>..origin/feature/PROJ-<dep-ticket>_..." --oneline 2>/dev/null | wc -l
```

If the branch exists AND has commits not in develop → this is a **stacked MR**. This ticket's branch must be created from that dependency's branch, and the MR must target it (not develop).

Record as `plan.mr_target_branch = "feature/PROJ-<dep>_..."` and note it prominently in the plan:
> ⚠ Stacked MR: branch from and target `feature/PROJ-<dep>_...`. push-ticket will use `--from` on create-branch and `--target` on prepare-mr.

If multiple deps have active branches → ask the user which one is the direct parent before continuing.
If no deps have active branches → `mr_target_branch` is `null` (normal MR to develop).

**A shared submodule in `plan.repos`:** plan it as its **own MR** in the submodule repo targeting `develop`, ordered **first** (producer). Never plan a shared-submodule **pointer bump** into any consumer repo's MR — `prepare-mr.sh` rejects it (`CHECK|FAIL`); the pointer is bumped by the team's own process after the submodule merges. Record the CI consequence in the plan's failure modes: consumer MRs referencing the new shared symbol won't compile in CI until the submodule MR merges and the pointer is bumped.

---

## Step 7 — Enter plan mode

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> plan-ticket 7 in_plan_mode`

Call `EnterPlanMode` now. The full session context is already loaded — tracker ticket, ACs, clarity-check answers, codebase exploration, security/auth design decisions from Step 4, and efficiency decisions from Step 5. Use all of it to write a rich, detailed implementation plan.

**Construct the plan under REQUIRED: superpowers:writing-plans** — its bar applies here: write for an engineer with zero codebase context, map the exact files each change touches, give complete content (no "TBD" / "add error handling" / "similar to above" placeholders), bind to exact signatures, and size each task so it carries its own **test-first** cycle (failing test → minimal code → refactor — the test-timing decision). The plan's *form* below — the per-repo file-change layout, the required sections, and the AC-by-AC gate — is the product contract layered on that discipline; do not drop it.

**For each file change**, write enough detail that an implementer needs no other context: the exact class/method/component being added or modified, what it does, which existing pattern it follows, and which ACs it satisfies. Use this format as the bar for detail:

```
─── api ──────────────────────────────────────────────────────────────

  Modify: src/Features/Foo/FooHandler.cs  [AC 1, AC 2]
    Add method `HandleAsync(FooCommand command)`. Follows the existing
    CQRS handler pattern in this folder. Must call `_fooRepository.SaveAsync()`
    and return the mapped `FooDto`. Guard against null entity — throw
    `NotFoundException` if not found (matches pattern in BarHandler.cs).

  Create: src/Features/Foo/FooDto.cs  [AC 2]
    New response DTO: Id (int), Name (string), Status (FooStatus).
    Place in the same namespace as other DTOs in this feature folder.

  Modify: Program.cs  [DI]
    Register `IFooService` → `FooService` as scoped (matches all other
    services in this file).

─── web ───────────────────────────────────────────────────────────────

  Modify: src/components/FooPanel/FooPanel.tsx  [AC 1]
    Add a `status` badge below the title using the existing `StatusBadge`
    component from `src/components/common/StatusBadge`. Pass `status`
    from the API response (already in FooPanelDto from the dependency).

─── database ─────────────────────────────────────────────────────────
  (include only if db_script_required label or schema/ORM-model change)

  Create: <next-version>/PROJ-XXX_add_foo_status.sql  [AC 2]
    Add column `Status` (tinyint NOT NULL DEFAULT 0) to `Foo` table.
    Use IF NOT EXISTS pattern (see recent scripts for the template).
    Rollback safety: additive — safe to deploy before code
    Index impact: no query filtering on this column; no new index needed
    ⚠ SQL script content must be written at implement time before pushing
```

**Required sections at the end of the plan:**

- **AC coverage** — every AC from the state file mapped to the exact file(s) + change that satisfy it, each with a status marker: `[covered]`, `[partial]`, or `[not covered]`. This is the section the user signs off **AC-by-AC** at the gate below, so make each AC's coverage concrete and checkable. Text markers only — no emoji (renders as `?` in some terminals).
- **Impact map** — for each file the plan modifies, list its **consumers** (one grep: who imports/renders/calls it), and mark every consumer site `affected & handled` / `affected & out of scope (why)` / `not affected (why)`. Planning is goal-directed ("where does the change go?") and silently skips the consequence question ("who else uses this?") — this section forces it. The classic miss: a visible element added to a **shared component** with its behavior wired in only **one** of N render sites → a dead control on the other N−1 (caught in review, not by the AC gate, because no AC mentions those surfaces).
- **Authorization approach** — role/policy required, data restriction, object-level ownership check, input validation (from Step 4); or "no new endpoints" for DB-only changes
- **Cross-repo contracts** — exact DTO shape, endpoint signature, or async message schema (only if applicable; from Step 5)
- **Consumed-contract verification** — the Step 3 ledger: one line per contract this ticket consumes (endpoint, request/response DTO, message, enum), each marked `verified @ <repo>/<path>[@branch]` or `documented-only, code unread — <why>`. Every consumed contract must appear, bound to the producer's **real code**, not the tracker/wiki description. Include the reverse entries too: `produced-for <consumer> — verified @ <path>@<branch>` for every contract a named in-flight consumer will bind to (or the explicit agreed-contract note when the consumer is a negotiable draft).
- **Dependency integration** — which interface/file from each done dependency, and exactly what to call and when
- **Observability** — what to log, at what level, in which file, and why (from Step 5)
- **Potential failure modes** — runtime, rollout, rollback, load, race condition risks (from Step 5)
- **MR labels** — only relevant from: `db_script_required`, `Breaking_Changes`, `Configuration`, `no_qa`, `Future_release`

If the plan is too broad for one ticket, flag it before presenting: _"This plan is broad — consider splitting into sub-tickets."_

If repo impact is unclear for any repo, ask before including it.

Call `ExitPlanMode` to present the plan to the user. If the user requests changes, re-enter plan mode, revise, and re-present.

### The gate is an AC-by-AC sign-off — not a blanket "ok"

The plan gate is the cheapest place to catch a thin or wrong approach: no code exists yet. So approval is a **per-AC coverage sign-off**, not a single "looks good". Present the **AC coverage** as the closing, can't-miss part of the plan — a line per AC with the exact file(s)/change that satisfy it and its status — then ask the user to confirm each:

```
Confirm coverage for each AC before I save the plan. Go through them and reply
"all confirmed" once you've checked each, or name any AC that's wrong, thin, or
not actually covered. This is a real check, not a rubber stamp — it's the cheapest
point to catch a wrong approach.

  AC 1 — <short text>  → api/.../Foo.cs (adds HandleAsync)     [covered]
  AC 2 — <short text>  → web/.../Bar.tsx (renders badge)       [covered]
  AC 3 — <short text>  → nothing yet                           [not covered]
```

Gate rules:
- **An incomplete Impact map is a blocker.** Every modified file must have its consumers enumerated, and a shared component gaining UI whose handler/data is wired in only some render sites is a blocker until each remaining site is explicitly handled or the element is hidden there.
- **Any `[partial]` or `[not covered]` AC is a blocker.** Resolve it by revising the plan to cover it — or, only if the user **explicitly** says it's out of scope for this ticket, record it in `plan.acs_out_of_scope` (Step 8) and journal it: `bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> DECISION "AC <n> out of scope — <reason>"`. Never silently drop an AC.
- **Any consumed contract not verified against producer code is a blocker.** Every entry in the Consumed-contract verification ledger must be `verified @ <path>` — or `documented-only` *with a concrete reason the code couldn't be read*. A contract whose shape was taken from the tracker/wiki description without opening the producer code (or deferred to "implement time") blocks the gate: read it now. Casing, enum serialization, required params, and object-vs-scalar shape all count.
- **Do not accept a bare "approve" / "ok" / "looks good" while a blocker AC is open** — re-point the user at the specific AC(s) and ask again.
- If the user flags an AC (wrong/thin/miscovered), re-enter plan mode, revise, re-present the coverage, and ask again. Repeat until every AC is confirmed or explicitly accepted out of scope.
- Keep it **proportional** — a coverage check, not a signature ritual. A two-AC ticket is two quick lines; the point is that the user *looks at each AC's coverage*, not that they retype the same word.

Only once every AC is confirmed (or explicitly accepted out of scope) is the plan approved → proceed to Step 8.

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 8 — Save plan to state file

After the user approves the plan in Step 7, extract the structured data from the approved plan and update `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. Set `flow` to `null` — this skill is complete. Preserve all existing fields, update `phase` to `planned`, and add:

```json
{
  "phase": "planned",
  "plan": {
    "branch": "feature/PROJ-XXX_Verb_Title",
    "branches": { "api": "bugfix/PROJ-XXX_Fix_...", "database": "bugfix/PROJ-XXX_Fix_..." },
    "commit": "PROJ-XXX Verb Title",
    "repos": ["api", "web"],
    "changes": [
      { "repo": "api", "action": "Modify", "file": "src/path/File.cs", "reason": "...", "acs": [1, 2] },
      { "repo": "web", "action": "Modify", "file": "src/Component.tsx", "reason": "...", "acs": [1] }
    ],
    "ac_coverage": {
      "AC 1 full text": ["api/src/path/File.cs", "web/src/Component.tsx"],
      "AC 2 full text": ["api/src/path/File.cs"]
    },
    "acs_out_of_scope": [],
    "authorization": "<approach>",
    "contracts": "<cross-repo contract definitions if applicable>",
    "observability": ["<logging plan>"],
    "failure_modes": ["<failure mode>"],
    "mr_labels": ["db_script_required"],
    "mr_target_branch": null
  },
  "saved_at": "auto"
}
```

`acs_out_of_scope` holds any AC the user **explicitly** accepted as out of this ticket's scope at the gate (the reason is in the journal) — leave it `[]` when every AC is covered. `implement-ticket` and `review` skip these so they aren't re-flagged as gaps.

Then tell the user:

```
✓ Plan saved for PROJ-XXX.

Next step: run /implement-ticket PROJ-XXX
```
