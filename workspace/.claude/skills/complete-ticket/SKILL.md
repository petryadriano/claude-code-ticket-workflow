---
description: Entry point for the ticket lifecycle — guides you through all 5 steps in sequence with confirmation at each gate. Usage: /complete-ticket PROJ-XXX
arguments:
  - name: ticket
    description: Tracker ticket ID (e.g. PROJ-123) or full tracker URL
    required: true
allowed-tools:
  - Read
  - Skill
  - Bash
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

> **Three workspace conventions every step follows:**
> 1. **Persist state via the helper, never the Write/Edit tool.** Write the full JSON to a temp
>    file (Write tool, a NON-dot path like `$WORKSPACE_ROOT/<ticket>.state.json`), then run the plain
>    command `bash "$WORKSPACE_ROOT/.claude/scripts/save-state.sh" <ticket> "$WORKSPACE_ROOT/<ticket>.state.json"`
>    — the helper validates the JSON, writes `.claude/tickets/<ticket>.json`, stamps timestamps,
>    and deletes the temp. Do NOT feed JSON via a heredoc / `<` redirect / `&&` chain (they make the
>    command compound, which Claude Code prompts on every time) and do NOT Write/Edit
>    `.claude/tickets/*.json` directly (its dot-dir path prompts on Windows). Both re-introduce the
>    approval prompt the helper exists to avoid. **Flow checkpoints are the exception:** when only
>    the `flow` field changes (the per-step "Flow checkpoint" notes), do NOT rewrite the whole
>    document — run the plain command `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket>
>    <active_skill> <step> <step_label>` (or `… <ticket> --clear` for `flow: null`). It patches just
>    the `flow` field in place, stamps `updated_at`, and is auto-approved — avoiding the
>    full-document regeneration (and its latency / token cost) on every checkpoint.
> 2. **Parse tool-result JSON with `node` or PowerShell `ConvertFrom-Json`, never `jq`** — `jq` is
>    not installed in Git Bash on Windows dev machines. For API responses, prefer fetching to a
>    **file** then parsing it (`curl -sf … -o <tmpfile>`, then `node -e '…' <tmpfile>`) over a
>    `curl | node` pipe — and never pipe a download into a **bare** interpreter (`| node`, `| bash`):
>    that executes the remote bytes and the safety hook will stop it. (`curl … | node -e '…'` is
>    allowed — stdin is data there — but the file form is still cleaner to quote and debug.)
>    On Windows write the temp file under `$WORKSPACE_ROOT` (e.g. `$WORKSPACE_ROOT/<name>.json`), never `/tmp`
>    — git-bash's `/tmp` is invisible to Windows `node`; delete it after parsing.
> 3. **Explore with the Grep / Glob / Read tools — not raw shell (Bash *or* PowerShell).** Use Grep
>    (content), Glob (file names), and Read (file contents) to explore code. Avoid `cd … &&
>    grep/find/cat/ls/head` and `Get-ChildItem -Recurse | … | ForEach-Object {…}` pipelines: a
>    compound shell command auto-runs only if *every* segment is pre-approved (and PowerShell script
>    blocks are flagged "arbitrary code"), so raw-shell exploration triggers an approval prompt each
>    time — the dedicated tools never do, and are faster.
> 4. **Git HTTPS auth failure → self-heal.** On `HTTP Basic: Access denied` from any git command,
>    re-seed the credential manager from the PAT and retry once:
>    `TOKEN=$(tr -d '\r\n' < "$HOME/.claude/git-token"); printf "protocol=https\nhost=<git-host>\nusername=oauth2\npassword=%s\n\n" "$TOKEN" | git credential approve`
>    Still failing → run `check-token.sh`; on `MISSING`/`INVALID` have the user re-issue the token (/setup Step 0).
>    But when a REST/API call returns `401` with body `Token is expired` (the stored PAT itself is dead, not a transport hiccup), the re-seed is futile — go straight to `check-token.sh` → have the user re-issue. Git transport (push/pull) uses the OS credential manager, not this file, so it is unaffected by an expired PAT.
> 5. **Connector first, token second.** When both can do the job, prefer the tracker's / Git host's MCP tools
>    over raw `curl`+PAT REST calls; use the REST/token path only as the fallback when a tool is
>    missing, fails, or returns thinner data than needed. (Git transport — clone/fetch/push — and
>    tracker attachment binaries have no connector equivalent; those legitimately stay on the token.
>    MR **creation** is excluded entirely: never via MCP or curl — the user opens MRs.)

## Required disciplines (Superpowers substrate)

This skill is the **lifecycle orchestrator** — the 5-step sequencing, the gates, the routing
table, and the state-machine handoffs to the sub-skills are all product-specific and stay here. The generic
discipline behind the *gates* is delegated to a Superpowers skill — do not re-derive it:

- **REQUIRED: superpowers:verification-before-completion** — evidence before *any* "advance / clean /
  done / merged" claim. This orchestrator never asserts a state it has not re-read from disk. Instances:
  re-read `<ticket>.json` to confirm the phase actually advanced before announcing the next
  step (a sub-skill returning is not proof its state saved); at the **implementation review gate**,
  the evidence pack — not the implementer's word — is what authorizes push; in the **MR health check**,
  never report a clean check when a lookup actually failed (surface the gap with a route to the fix).

Orchestration mechanics these do **not** cover stay inline at their points of use: the
`is_spike` routing table, the auto-advance-vs-stop transitions, the MANDATORY evidence gate and its
approval-lock wording, the flow-resume / `flow.active_skill` checks, the journal protocol, and every
state-machine handoff to a sub-skill (`/understand-ticket`, `/plan-ticket`, …).

> **Why not delegate the orchestration itself?** `superpowers:executing-plans` /
> `subagent-driven-development` execute a single written plan file and end by *finishing a branch*
> (and assume git worktrees). This lifecycle instead drives a **tracker ticket through five sub-skills**
> with per-step gates, a branch-per-repo + MR model, and no worktrees — so the orchestration is product-specific and
> is kept inline; only the gate-honesty discipline above is delegated.

---

Extract the ticket ID from `$ticket` (strip URL if needed).

> **Session title is automatic — nothing to run here.** The `title-hook` (a SessionStart +
> UserPromptSubmit hook wired in `.claude/settings.json`) sees the `/complete-ticket PROJ-XXX`
> submission and titles the session `PROJ-XXX` immediately. It upgrades to
> `PROJ-XXX — <tracker title>` once `understand-ticket` caches the title, and re-asserts it every
> turn so it never drifts. See `title-hook.mjs`.

**Standards freshness check (run once, here at the top — never mid-flow).** Refresh the shared
skills/scripts before routing, so the whole ticket runs the latest version. This is the *only*
place the lifecycle pulls updates, so nothing changes mid-flow:

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/update-standards.sh"
```
- `BEHIND|<n>|<branch>` → tell the user: _"Your team skills/scripts are `<n>` commit(s) behind. Pull now? It updates every workspace at once. (recommended)"_ On yes → `bash "$WORKSPACE_ROOT/.claude/scripts/update-standards.sh" --pull`, report the result, then continue.
- `UPTODATE|...` → continue silently.
- `DIRTY|...` → the clone has uncommitted local changes (likely `improve-skills` edits awaiting an MR); skip the pull, continue.
- `NOMARKER|...` → workspace not linked to a standards clone (not provisioned by `/setup`); skip silently.

**Superpowers substrate check (run once, here at the top).** This flow's skills delegate engineering
discipline to the Superpowers plugin (`REQUIRED: superpowers:*`). Confirm those skills are available to
you now (e.g. `superpowers:verification-before-completion`, `superpowers:test-driven-development`). If
they are **not** loaded, warn before routing: _"⚠ The Superpowers plugin isn't loaded, so the
engineering-discipline delegations won't apply. Install it once with `/plugin install
superpowers@claude-plugins-official` then `/reload-plugins` (or restart). Continue anyway? The flow
still works — every gate and check is intact — but without the substrate disciplines."_ Honor the
user's choice; if they continue, proceed normally.

State file: `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`

Read the state file if it exists.

**Flow resume check (before phase routing):** If `state.flow.active_skill` is set, a skill was mid-execution when context was last compacted. Before re-invoking it, read the context journal if it exists — `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` — to restore the decisions, dead-ends, and open questions that the JSON does not hold. Honor every `DEADEND` entry (do not retry a recorded failed approach) and surface any unresolved `QUESTION`. Then re-invoke the mid-execution skill — it will read `flow` from the state file and resume from the saved step. Do not apply the normal phase routing table until that skill completes and clears `flow`.

> **Context journal — the one rule:** the moment something happens that you'd be annoyed to re-derive after a context reset, append one dense line to `<ticket>.journal.md` via `append-journal.sh`. That's it. Append *as it happens*, not batched at the end — `/compact` fires asynchronously (often mid-step), so only what's already on disk survives it. The journal holds only what the structured JSON cannot: *why* a choice was made, what was tried and failed, and open questions. Never duplicate task state, plan, or file lists (those live in `<ticket>.json`).
>
> **What's worth a line:** a non-obvious choice between alternatives (`DECISION`, with the *why*); an approach abandoned (`DEADEND`, with cause + replacement); a question raised, then its answer (`QUESTION` → `RESOLVED`); a constraint or preference the user states in passing (`DECISION`/`NOTE`).
>
> **It's proportional — that's the point:** journaling is tied to decisions, not to ceremony. A short ticket with no real decisions produces **zero entries, and that's correct** — not a missed step. A long ticket (the kind that actually hits `/compact`) accumulates lines as decisions pile up, so the protection is there exactly when it's needed. No flush step, no per-turn checklist — just append when a real decision happens.
>
> **Recovery after `/compact`:** the journal is on disk, so it always survives. Each skill's Step 0 (and the flow-resume check above) reads `<ticket>.json` + `<ticket>.journal.md` before doing anything — so resuming the ticket restores the decisions, dead-ends, and open questions. There is no background process; recovery happens because the skill reads the file.

Then run each pending step in sequence by invoking the corresponding skill. Respect every gate — a skill's own confirmation, plus the implementation review gate this orchestrator adds before push — and wait for the user before moving past it. The routing table below is the source of truth for which transitions auto-advance and which stop.

---

## Output discipline — short, decision-first, source-of-truth (applies to EVERY step + gate)

A long gate is an **unread** gate — developers rubber-stamp walls of text, which defeats the gate. Every message to the user (summaries, gates, findings) must be short and scannable:

- **Lead with the decision** the user must make — put it first, make it obvious.
- **Tables / bullets over prose.** One idea per line. A few lines max; detail only on request.
- **Cut** recaps, caveats, and reasoning unless asked. Surface only what the user must know to decide.
- **Source of truth, never assumptions.** Every claim about scope, contracts, behavior, environments, or data must come from reading **the tracker / the wiki / the actual source code** — not memory or inference. Haven't read it? Say so; don't guess. (Assumptions here have shipped a wrong environment and an unnecessary code change.)

## What each step does

There are **two lifecycles** depending on the tracker `issuetype` captured by `understand-ticket`:

### Implementation lifecycle (Story / Defect / Task / …)

| Step | Skill | What happens |
|---|---|---|
| 1 | `understand-ticket` | Fetches the tracker ticket, reads all ACs, comments, attachments, and the full epic. Resolves dependencies — hard-stops on blockers, finds how done deps were implemented. Saves a summary to disk. **Gate: you confirm the understanding before proceeding.** |
| 2 | `plan-ticket` | Syncs all repos, explores the codebase guided by the tracker context, checks for existing code to reuse, builds a file-by-file plan with AC coverage map. **Gate: you sign off AC coverage AC-by-AC, then approve the plan — before any code is written.** |
| 3 | `implement-ticket` | Implements every file change from the approved plan, writes or updates unit tests (your unit-test framework), runs a build check, validates every AC, does an AI self-review (auto-fixes HIGH issues, surfaces MEDIUM ones), and authors the **verification**: automated UI specs (run next by `verify-ticket`) for everything an assertion can reach, plus a short manual guide for the rest, plus a **coverage matrix**. **Auto-advances to step 3.5.** |
| 3.5 | `verify-ticket` | Runs the AUTO specs against the running local stack (fresh-context verifier), exercises `@destructive` cases under per-scenario approval, checks the coverage matrix, and emits an **evidence pack** (HTML report + replayable traces + per-AC verdicts). **Gate: after it finishes, this orchestrator stops so you can review the implementation + the evidence + run the remaining MANUAL items, then reply "evidence reviewed and approved" before continuing to push.** |
| 4 | `push-ticket` | Confirms verification approval (recorded at the review gate — or gates on the persisted guide/evidence here if it wasn't). Then creates the branch, stages only the changed files, commits, pushes, and outputs the MR URL and a ready-to-paste MR description. |
| 5 | `improve-skills` | Reflects on the full session — what went smoothly, what caused friction, what required rework. Proposes and applies concrete improvements to the skills and scripts so the next ticket runs better. **This is the most important step: the workflow gets smarter after every ticket.** |

When the ticket is already in the `shipped` phase (MR is open), running `/complete-ticket` triggers an **MR health check** instead of immediately asking about `/improve-skills`. See the MR health check section below. **If instead the user brings a new question or code change for a shipped ticket, refresh first and route as a fresh increment — see "Re-entry on a shipped/closed ticket" in Step sequence.**

### Spike lifecycle (Spike issuetype)

A spike's deliverable is a researched proposal + draft child tickets — not code, not an MR. After `understand-ticket` detects `issuetype.name == "Spike"` and writes `is_spike: true` to the state file, this lifecycle runs instead:

| Step | Skill | What happens |
|---|---|---|
| 1 | `understand-ticket` | Same as above, but spike-aware: ACs are not required (a Spike rarely has them); the **research question** is captured from the description + parent epic. Persists `issuetype` and `is_spike: true`. **Gate: you confirm the understanding.** |
| 2 | `spike-ticket` (Phase A) | Syncs repos, then performs codebase research grounded in the parent epic. Verifies each load-bearing fact against the actual code. Produces a structured proposal (goal · current state · recommended approach · proposed child tickets · coverage map · open product questions · risks · estimates). **Gate: you approve the proposal.** |
| 3 | `spike-ticket` (Phase B) | Helps publish the proposal: a paste-ready tracker comment + each child-story draft. Default is "you paste it"; auto-create via the tracker's MCP is an opt-in alternative with **per-item approval** — every tracker write needs its own explicit yes. |
| 4 | `improve-skills` | Same as above. |

---


## Step sequence

Routing keys off the current `phase` and the `is_spike` flag in the state file (set by `understand-ticket`):

| Phase before step | `is_spike` | Skill to invoke | Confirm before invoking? |
|---|---|---|---|
| (none — file missing) | unknown | `understand-ticket` | No — start immediately |
| `understood` | `false` (or missing) | `plan-ticket` | **No — auto-advance.** understand-ticket's confirmation gate already authorized continuing; print a one-line "Understanding confirmed → planning" and invoke `plan-ticket`. |
| `understood` | `true` | **`spike-ticket`** (Phase A — research) | **No — auto-advance.** The understanding gate authorized it; print "Understanding confirmed → research" and invoke `spike-ticket`. |
| `planned` | any | `implement-ticket` | **No — auto-advance.** plan-ticket's AC sign-off already authorized it; print "Plan approved → implementing" and invoke `implement-ticket`. |
| `implemented`, no `verification` block | any | **`verify-ticket`** | **No — auto-advance** into verification (it has its own stack/destructive asks). Print "Implementation complete → verifying" and invoke `verify-ticket`. It runs the specs + emits the evidence pack, keeps `phase: implemented`, and adds the `verification` block — then this orchestrator stops at the gate below. |
| `implemented`, `verification` present | any | **STOP → implementation review + evidence → `push-ticket`** | **YES — stop and ask.** Do **not** auto-advance into push. Present the implementation review (AC validation, self-review findings incl. undecided MEDIUM items, changed files) **+ the evidence pack + the remaining MANUAL scenarios**, then wait for the user to review, run the manual items, and reply **"evidence reviewed and approved"** before invoking `push-ticket`. See "Implementation review gate" below. |
| `shipped` | any | MR health check (automatic, no confirmation) | **Do not ask — run the MR health check immediately. See section below.** |
| `researched` | `true` | **`spike-ticket`** (Phase B — publish) | **No — auto-advance.** The proposal was approved at the `researched` gate; invoke `spike-ticket` (its per-item publish approvals are the next stops). |
| `published` | `true` | `improve-skills` | Ask: "Spike published. Run /improve-skills to reflect?" → invoke on yes → stop |
| (Rule 4: all MRs merged) | any | `improve-skills` | Ask: "Run /improve-skills?" → invoke on yes → stop |

- If the ticket is not started, invoke `understand-ticket` immediately without asking.
- For every subsequent step, display a brief summary of what that step produced — read it from the state file so the user can see what is advancing (the previous step's own gate already showed the full detail). The summary shape depends on `is_spike`:
  - After `understood` (`is_spike == false`): title, goal, ACs (numbered list), proposed repos, dependencies, epic constraints
  - After `understood` (`is_spike == true`): title, **research question**, parent epic + goal, deliverable note ("proposal posted to the tracker + draft child tickets — no code, no MR"), attachments listed, any unverified content not yet shared
  - After `planned`: branch name, repos affected, file-by-file change list, AC coverage, authorization approach
  - After `implemented`: AC validation results, self-review findings (auto-fixed + medium)
  - After `researched` (Spike only): proposed ticket count + titles, coverage map status, any open product questions, then ask whether to help publish
  - After `published` (Spike only): publish mode used (manual or MCP), child tickets created (with keys) or handed off for manual creation
- Then show the status line and a one-line transition, and **invoke the next skill directly — do not add a separate confirmation asking whether to run the next step.** Each step carries its own internal gate (understand: confirm the understanding; plan: AC sign-off; verify-ticket: its destructive/stack asks; implementation review: evidence-reviewed approval — with push-ticket re-gating if it wasn't recorded) — that is where the user retains control and can say "stop" to pause the lifecycle. **Two transitions are deliberately NOT auto-advanced and require an explicit user OK before the next skill runs: (1) after `verify-ticket` → `push-ticket` — the implementation review + evidence gate (see below); (2) the terminal `improve-skills` step (offered yes/no).** `implement-ticket` → `verify-ticket` DOES auto-advance.
- When invoking a sub-skill, always pass the ticket ID as the argument: e.g. invoke `understand-ticket` with args `<ticket>`, invoke `plan-ticket` with args `<ticket>`, etc. `improve-skills` takes no ticket argument.
- After each skill completes, re-read the state file to confirm progress, then show the brief summary — a sub-skill returning is **not** proof its state saved, so the phase is verified from disk before any "→ next step" claim (**REQUIRED: superpowers:verification-before-completion**). Auto-advance to the next step **except** at the evidence gate: after `implement-ticket` (phase `implemented`, no `verification`) auto-advance into `verify-ticket` (it carries its own stack/destructive asks); after `verify-ticket` (phase still `implemented`, `verification` present), **stop** at the implementation review gate (below) and wait for the user's explicit OK before invoking `push-ticket`.
- If the phase did not advance after a skill ran (e.g. user aborted mid-step or didn't confirm the gate), explain specifically what happened and what to do:
  - After `understand-ticket`: _"The state file was not saved — this means the understanding gate didn't receive explicit confirmation. Re-run /understand-ticket <ticket>, review the summary, and reply 'yes' to save it."_
  - After `plan-ticket`: _"The plan was not saved. Re-run /plan-ticket <ticket> and reply 'go ahead' to approve the plan."_
  - After `implement-ticket`: _"Implementation state was not saved. Re-run /implement-ticket <ticket> to resume."_
  - After `push-ticket`: _"Push did not complete. Re-run /push-ticket <ticket>."_
  - After `spike-ticket` Phase A: _"The proposal was not saved. Re-run /spike-ticket <ticket> and reply 'approved' to save it."_
  - After `spike-ticket` Phase B: _"Publish did not complete. Re-run /spike-ticket <ticket> to resume — it will skip already-published items."_
- **Scope-change re-plan rule.** If, after the `planned` gate, the scope materially expands — new ACs, a new repo, or a product decision that changes the design (not just a clarification) — **stop and re-run `/plan-ticket <ticket>`** to re-gate AC coverage and refresh `plan.repos`/`plan.files`. Do **not** absorb new scope ad-hoc inside `implement-ticket` or `push-ticket`; the AC-by-AC sign-off gate must see the new scope. A pure clarification that changes neither files nor ACs does not require re-planning.
- **Shipped-phase scope-change realignment.** When the user reports the ticket/scope changed **after** MRs are open ("the ticket was updated, align the MRs"), do NOT start adjusting code from the first partial picture — each early conclusion tends to be invalidated by the next source. Gather **all** evidence first, in this order: (1) **sync ALL repos** (`sync-repos.sh`, no `--repos`) — sibling/producer merges frequently changed the very contract mid-flight; (2) re-fetch the ticket **and its changelog** (who edited description/ACs, when) and diff against the cached state; (3) read what merged in producer repos since the state's `saved_at` (commits + MR diffs around the contract); (4) ask the user for any team conversation that motivated the change. Only then present one consolidated scope diff with decision points, get the user's choices, and route: code changes → re-plan or targeted edits per the user's call; conflicts → after scope is settled (rebuilding a branch on the current target often beats rebasing code that's about to be deleted).
  - **Prior increment already MERGED -> fresh increment (not realignment).** The rule above is for MRs still *open*. If the earlier work's MRs are already **merged** when new scope lands, do **not** reuse or force-push the merged branch: treat the new scope as a new increment — reset the state to `understood` and run the full lifecycle, cut a **NEW** scope-specific branch (new approved verb, e.g. the merged `…_Implement_X` becomes `…_Add_Y`), and open **NEW** MRs on top of the merged code. The merged MRs stay as-is; record the merged increment (branch/commit/MR) in the state so no later step mistakes it for unshipped work.
- **Re-entry on a shipped/closed ticket — REFRESH FIRST (the session may be days old).** A bare `/complete-ticket` on a `shipped` ticket runs the MR health check. But the moment the user brings a **new question** or a **code change/adjustment** for that ticket — in this session or one reopened later — do NOT answer or edit from cached session state: local branches, develop bases, and the tracker ticket itself may be stale after a pause, and acting on stale state is how wrong-base branches and missed AC changes happen. Refresh before doing anything:
  1. **Sync** the affected repos (`sync-repos.sh`) so branches/bases are current.
  2. **Re-fetch the ticket** (description, ACs, comments, changelog) — scope may have changed since the state's `saved_at`; diff against the cached state.

  Then route by what was actually asked:
  - **Pure question / "understand X"** → answer from the refreshed ticket + the **current** code (read it now, don't trust session memory); no branch/commit work.
  - **Code change / adjustment** → it is a **NEW increment**: reset to `understood` and run the full lifecycle (understand → plan → implement → push) per the "merged-increment → fresh increment" rule above — new branch, new MRs, every gate. **Never hand-roll the change ad-hoc, and never do it inside/after `improve-skills`.**
- `improve-skills` does not update the state file — it always runs after `shipped` regardless of whether it has run before.

### Implementation review gate (phase: `implemented`, after `verify-ticket`)

This gate runs **after `verify-ticket`** has produced the evidence pack (the `verification` block is present). **Do not auto-advance into `push-ticket`.** Stop here so the user can review the implementation, read the evidence, and run any remaining MANUAL items before anything moves toward commit/push. This is the instance of **REQUIRED: superpowers:verification-before-completion** — the evidence pack (per-AC verdicts + coverage matrix), not the implementer's "it works", is what authorizes push; a code change with stale evidence must never reach push.

> **Green gates are necessary, not sufficient — judge the code, not the ceremony.** Every gate green
> (TDD, self-review, the AC table, the evidence portal) can still ship shallow execution — a missing
> data-access filter, duplicated logic, an override a code-read called safe but a runtime path clears.
> Before approving: (1) confirm the implement-ticket **Depth checks** actually *ran* (the grep/trace/round-trip
> produced output, not just a checked box); and (2) **when a known-good reference exists** — the same
> feature in another repo, a sibling/prior ticket of the same shape, a reference implementation — **A/B the
> produced code against it.** Diffing against a reference is the single check that most reliably catches what
> every green gate misses; a passing gate over an unexamined diff is process theater.

**Approval already recorded?** If `implementation.test_approved == true` (a previous run approved it but the push never completed), do not re-demand it: present the summary below, note _"Verification was already reviewed and approved on a previous run."_, and ask _"Reply 'proceed' to continue to /push-ticket, or tell me if anything changed — then I'll void the approval and we re-verify."_ Any reported change/failure → clear `implementation.test_approved` and run the full gate.

Otherwise, present:
- **AC validation** — each AC → ✓ DONE / ~ PARTIAL / ✗ (from `implementation.ac_validation`).
- **Self-review findings** — the AUTO-FIXED (HIGH) list, the undecided **MEDIUM** "your call" items, plus LOW notes.
- **Changed files** — the full `implementation.files_changed` list, grouped by repo.
- **The evidence pack** (from `verification`): the per-AC verdict table (PASS/FAIL/BLOCKED/SKIP), the **coverage matrix with any uncovered dimensions called out**, and the single evidence link (`http://localhost:<port>/<ticket>` — traces replayable). **Lead with any FAIL or uncovered dimension; never bury it under the passes.**
- **Remaining MANUAL scenarios** — the items `verify-ticket` could not automate (from the test guide / `test_guide.scenarios` where `mode == MANUAL`), presented in full for the user to run by hand.

Then stop with:
_"Implementation self-reviewed and verification run. Review the changes + evidence above and run the manual items, then reply **'evidence reviewed and approved'** to continue to /push-ticket. Or tell me what to change / which check failed."_

**On "evidence reviewed and approved":** record it before invoking push — read `<ticket>.json`, set `implementation.test_approved: true`, save via the state helper — then invoke `push-ticket`. (The flag name stays `test_approved` for push-ticket compatibility.)

**On a reported failure (a FAIL verdict the user won't accept, a failed manual item, or a MEDIUM finding to fix first):** journal it (`append-journal.sh <ticket> DEADEND "Verification failed: …"`), **clear `implementation.test_approved` if set — any fix voids approval AND voids the evidence**, fix, then **re-run `/verify-ticket`** (re-run the specs, refresh the evidence) before re-presenting this gate. A code change with stale evidence must never reach push.

**Backward-compat (older tickets with no specs):** if there is no `verification` block AND `test_guide.scenarios` lists no `AUTO` entries (older tickets predate automated specs), fall back to the legacy manual-test gate — present the persisted `.test-guide.md` in full and gate on **"tested and approved"** instead; push-ticket re-gates if it wasn't recorded.

**If the user says 'proceed' without approving:** invoke `push-ticket` WITHOUT setting `test_approved` — it holds its own gate before any git command. Never set `test_approved` on anything weaker than an explicit approval.

---

## MR health check (phase: shipped)

When phase is `shipped`, a bare `/complete-ticket` runs an **MR health check** — automatically, no
user confirmation needed before starting. It finds the ticket's MR(s), classifies each
(merged / closed / conflicts / change-requests / under-review), shows a health dashboard, and routes
by priority: conflicts → `/resolve-conflicts`; unresolved comments → `/address-review`;
all-merged or under-review → offer `/improve-skills`. **Honesty property to preserve:** never report a
clean health check when a lookup actually failed — surface every failed lookup (not found, conflicts,
unfetchable notes) with a route to the fix (**REQUIRED: superpowers:verification-before-completion**).

The full procedure — the `plan.repos`/`plan.branch` fallback, Steps A/B/C, the Git host MCP param-name
caveat, the destructive-MR audit, the classification table, and routing Rules 1–6 — is in
[mr-health-check.md](mr-health-check.md). Read it before running this check.

---


## Status line format (show before each confirmation prompt)

```
<ticket> — understood [✓/·]  |  planned [✓/·]  |  implemented [✓/·]  |  shipped [✓/·]
```
