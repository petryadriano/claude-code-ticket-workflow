---
description: Step 3 of 5 — Implement, test, build, self-review a ticket, then author its verification — automated specs for what can be automated (run by /verify-ticket) plus a manual guide for the rest, with a coverage matrix. Reads the plan saved by /plan-ticket and saves implementation state to disk. Usage: /implement-ticket PROJ-XXX
arguments:
  - name: ticket
    description: Tracker ticket ID (e.g. PROJ-123) or full tracker URL
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

Step 3 of 5 in the ticket lifecycle.

> **Coverage & gaps.** This implements from the cached plan + the local codebase. If the plan leans on an attachment/mockup/wiki detail that was a gap earlier, re-attempt it (`fetch-attachment.sh` + token / `WebFetch` / the tracker's MCP) rather than guessing; if a planned file/symbol isn't where expected, widen the search across repos + a shared submodule before improvising, and flag any unresolved gap instead of silently working around it.

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

This skill is the **domain** layer. The generic engineering discipline is delegated to Superpowers
skills — do not re-derive it here. Load and follow each at the point marked below:

- **REQUIRED: superpowers:test-driven-development** — the RED-GREEN-REFACTOR cycle for all code (Steps 3 & 5). Per the test-timing decision, code is written **test-first**: failing test → watch it fail → minimal code → refactor.
- **REQUIRED: superpowers:systematic-debugging** — root cause before *any* fix, whenever a build/test fails (Steps 4 & 5) or an implementation approach dead-ends (Step 3). Read the complete error output first; never patch symptoms.
- **REQUIRED: superpowers:verification-before-completion** — evidence before *any* "done / passing / fixed / works" claim (Steps 4–9 and every visual check). Local instances: cite the grep/read behind any "this is the only X", "there's no Y", or "follows the existing pattern" claim; render the view before any visual claim.

Domain-specific mindsets these do **not** cover, active throughout:
- **Security by default**: every new endpoint needs authorization, every input needs validation, no sensitive data in logs.
- **Correctness over cleverness**: null guards, cancellation tokens, async/await done right — always.
- **No surprises**: if something not in the plan needs to change (e.g. DI registration, app settings), note it explicitly and add it to `files_changed` before doing it.

---

> **Journal in the moment.** The instant something journal-worthy happens, append one line via `append-journal.sh` — don't save it for later, because `/compact` can fire mid-step and only what's already on disk survives. On this step the common cases are: a build/test failure that forces a different shape (`DEADEND`, with cause + replacement), a deviation from the plan (`DECISION`, with *why*), and constraints the user states in passing. A short ticket may produce zero entries; that's correct, not a miss. See the journal note in `complete-ticket`.

## Step 0 — Flow resume check

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. Check `state.flow`:

- If `state.flow.active_skill == "implement-ticket"`: first read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` if it exists — on this step it is especially load-bearing: it records which implementation approaches already failed (`DEADEND`) so a resume does not burn time retrying them. Honor every `DEADEND`; surface unresolved `QUESTION`s. Then print `"↩ Resuming implement-ticket from: <step_label>"` and jump directly to that step. Use `implementation.repos_done` alongside `flow.step` to know which repos are already complete.
- If `state.flow.active_skill` is set to a **different** skill: stop — `"⚠ <ticket> shows <other-skill> was mid-execution (step: <step_label>). Run /<other-skill> <ticket> to complete it first."`
- If `state.flow` is absent or null: continue to Step 1.

---

## Step 1 — Load state

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`.

If file does not exist → stop: _"No state found for <ticket>. Run /understand-ticket then /plan-ticket first."_

If `phase` is not `planned` → stop: _"State is '<phase>' — expected 'planned'. Run /plan-ticket <ticket> first."_

Load into context — all of these are required:
- `acs` — all acceptance criteria
- `plan.branch`, `plan.commit`, `plan.repos` (in order — producers first), `plan.changes`
- `plan.ac_coverage`
- `plan.authorization` — the auth approach decided at plan time; implement exactly this
- `plan.contracts` — cross-repo DTO/endpoint/message schemas; implement exactly these
- `plan.observability` — the logging plan; implement these logging statements
- `plan.failure_modes`
- `labels`
- `dependencies`

**If `plan.authorization` is null or missing:** warn — _"No authorization approach was recorded in the plan. Is this intentional (e.g. DB-only change, internal background service)? Reply 'yes, no auth needed' to continue, or run /plan-ticket again to define it."_ Wait for confirmation before proceeding.

**If `repos_done` exists in `implementation`:** resume from there — skip repos already listed in `repos_done` for both implementation and tests.

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 2 — Pre-implementation: load repo conventions

Before writing any code in a repo, read its `CLAUDE.md`:
- Architecture and layer boundaries
- DI registration patterns (where services/handlers/validators are registered)
- Naming conventions and code style rules
- Any repo-specific caveats or gotchas

This must happen before touching a single file in that repo.

> **Read and search with the Read / Grep / Glob tools — not raw shell (Bash *or* PowerShell).** When inspecting existing code (pattern-matching in Step 3, locating files, checking conventions), use Read/Grep/Glob. Avoid `cd … && grep/find/cat/ls` and `Get-ChildItem -Recurse | … | ForEach-Object {…}` pipelines — raw-shell exploration triggers an approval prompt every call (PowerShell script blocks are flagged "arbitrary code"; multi-cmdlet pipelines aren't allow-listed). Shell is for build, test, and the helper scripts.

---

## Step 3 — Implement (test-first)

Implement repos in the order listed in `plan.repos` — this order was set by plan-ticket to ensure producers (types, interfaces, endpoints) are implemented before consumers.

> **Flow checkpoint (per repo):** Before implementing each repo: `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> implement-ticket 3 implementing_<repo>`

**Build each unit of behavior test-first.** Follow the RED-GREEN-REFACTOR cycle from **REQUIRED: superpowers:test-driven-development** — write the failing test, watch it fail for the right reason, write the minimal code to pass, refactor. The test framework, placement, and coverage requirements that cycle must satisfy are in **Step 5** (don't re-derive them here). For repos where unit tests don't apply (database SQL, UI TypeScript/React, trivial config), implement directly — see the Step 5 skip list.

For each repo, implement every file change listed in `plan.changes` for that repo. Do not deviate — if something unexpected requires a change to scope, stop and tell the user before proceeding.

### Pattern matching — mandatory before writing each file

**Before writing any code in a file, read the existing code in that file (or the nearest similar file in the same folder) and identify the exact local style for:**
- Method call formatting — are arguments on one line or one-per-line?
- Logging calls — placeholder format (`{0}` positional vs named `{Name}`?), argument layout
- Exception handling — `try/catch` shape, what gets logged vs rethrown
- Return patterns — early returns vs single-exit, guard clause style
- Object initializers — inline vs multiline, trailing commas
- Any other construct you are about to write that appears nearby

**Write new code to match the surrounding style exactly — not what you consider best practice, not what the framework documentation recommends, not what you have seen elsewhere.** If the file uses `{0}` positional log placeholders with one argument per line, every new log call in that file must do the same. If the file uses named placeholders, follow that. Read first, then write.

If the file is new (no existing code), match the style of the most similar file in the same folder.

### Choose the approach before you code it — for any change to a HOT / SHARED / DELICATE path

Matching local *style* is not enough. When the change touches a distribution engine, a merge/overlay, a
pipeline, a base class, or any "sequence matters / bidirectional" method, **where and how your change hooks
in is the load-bearing decision** — and the first approach that compiles is often not the safest.

- **Mirror the nearest analogue's STRUCTURE, then A/B against it — now, not at the final gate.** Find the
  existing code that already solves the same SHAPE (the sibling feature, the prior ticket, the path you're
  extending) and copy its insertion point and shape. Diff your produced code against that analogue. A
  divergence from how the analogue does it must be a deliberate, stated reason — not an accident of which
  approach you wrote first. (Reading the analogue ≠ mirroring it.)
- **Prefer the lowest blast radius.** An **additive hook / post-pass** — let the existing flow run unchanged,
  then adjust its output — beats a **control-flow change** inside a delicate method (re-routing branches,
  early-returns), because the post-pass cannot drop or reorder what the existing path already produced. A
  control-flow change in a delicate method is the high-risk option, never the default.
- **At a delicate fork, generate 2-3 GENUINELY DIVERSE candidates before coding** (not variants of one idea),
  trace each for dropped/duplicated outputs, and pick the smallest-blast one. **When you escalate the fork to
  the user, present the diverse candidates** with their tradeoffs — never one design dressed up as the only
  "proper fix."

| Rationalization | Reality |
|---|---|
| "I found a fix that compiles and the AC passes — ship it." | A re-routed delicate method can drop a SIBLING output (a value the old path distributed) while the AC's own field looks right. Mirror the analogue + rank blast radius first. |
| "The control-flow change is the proper fix; the alternatives are worse." | You explored one design's variants, not diverse approaches. A post-pass over the unchanged flow is usually lower-risk — write it out and compare. |
| "I read the analogue — that's enough." | Reading isn't mirroring. If you didn't copy where/how it hooks in, A/B your diff against it before moving on. |

> **Opt-in best-of-N for a flagged-delicate unit.** When approach-correctness is high-stakes on a genuinely
> delicate unit, offer the user a best-of-N pass: a small `Workflow` that spawns 2-3 independent candidate
> implementations of that one unit plus an adversarial reviewer that diffs them against each other AND the
> nearest analogue, returning the lowest-blast/most-correct one. Scope to the 1-2 risky units — never every
> file; requires the user's explicit opt-in to the token cost.

**While implementing, actively apply the plan decisions:**
- `plan.authorization` → apply the exact auth approach (attributes, policies, guards) as planned
- `plan.contracts` → implement the exact DTO/interface/message shapes as defined — no variations
- `plan.observability` → add the logging statements specified in the plan

**After each file is written, verify:**
- Follows naming conventions from the repo's `CLAUDE.md` (`_camelCase` private fields, `PascalCase` consts, braces on all blocks)
- Every new construct matches the style of the surrounding existing code (see pattern matching above)
- No hardcoded secrets, connection strings, or environment-specific URLs
- New services, handlers, validators, or consumers are registered in DI — check `Program.cs` or equivalent and add registration if missing
- If `Configuration` label: all relevant app-settings files are updated

**Out-of-plan changes** (DI registrations, app settings, etc.): note them explicitly, and immediately add them to `implementation.files_changed` in the state file so push-ticket stages them correctly. When the out-of-plan change reflects a non-obvious decision (e.g. deviating from the plan's approach because it didn't work), journal it:
> ```bash
> bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> DECISION "<what changed vs plan> because <why>"
> ```

> **Journal dead-ends as you hit them:** Any time an approach is tried and abandoned — a build/type error that forces a different shape, a test that reveals the design is wrong, a library/ORM behavior that blocks the planned path — root-cause the failure first (**REQUIRED: superpowers:systematic-debugging**), then record it immediately so a post-compaction resume does not retry it:
> ```bash
> bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> DEADEND "Tried <approach>; failed because <root cause>. Using <what instead>"
> ```
> Record the root cause and the replacement, not just "it failed" — that is what makes the entry actionable on resume.

After finishing each repo, print a one-line summary of what changed, including any out-of-plan additions.

> ⚠ NO COMMITS HERE — implementation lives on the working tree only.
> Do not run `git add`, `git commit`, `git stash`, or create any branch.
> All git operations happen in push-ticket, after the test gate.

After each repo is done, update `implementation.repos_done` in the state file.

**After all repos are done → go directly to Step 4.**

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 4 — Build check

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> implement-ticket 4 build_check`

Run for each repo (skip repos already in `repos_done` before this run).

**.NET repos:**
```bash
dotnet build "$WORKSPACE_ROOT/<repo>/<Repo>.sln" --no-restore 2>&1 | grep -E "error CS|^\s+[0-9]+ Error\(s\)" | head -30
```
Build is clean when `grep "error CS"` returns nothing and the Error count shows `0 Error(s)`.

**UI (if in plan.repos):**
```bash
npx tsc --noEmit -p "$WORKSPACE_ROOT/web/tsconfig.json" 2>&1 | tail -20
```
TypeScript type errors are caught here — do not skip even if no .tsx file was created (existing types may have been broken). If the change touched a UI SPA, also run **ESLint** (`npm run lint`), and **stylelint** (`npm run slint`) if any `.scss` changed — `npx tsc` does not cover those rules.

> **When build / type-check / lint output is ambiguous, read [build-diagnostics.md](build-diagnostics.md)** — the .NET-specific guide to telling real `error CS####` failures from environmental noise (`MSBUILD` target lines, `MSB3027` file-locks, `MSB3492` obj-cache locks, transient `N Error(s)` with no detail, pre-existing upstream breaks, LSP false positives), the `--fix` scoping rule, and the "UI change not appearing" protocol.

If any build or type check fails: **REQUIRED: superpowers:systematic-debugging** — read the complete error output and understand the root cause before writing any fix. Fix errors before proceeding.

Build check runs before the full test suite — no point running tests against broken code.

**After all builds and type checks pass → go directly to Step 5.**

---

## Step 5 — Test conventions & coverage

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> implement-ticket 5 running_tests`

The RED-GREEN-REFACTOR cycle and the test-first timing come from **REQUIRED: superpowers:test-driven-development** (applied per unit in Step 3) — this step does not restate them. What is domain-specific is *how* the tests are built and *what* they must cover. The tests written test-first in Step 3 must satisfy all of the following; this step is where you run the full suite and confirm that coverage.

Tests use **your unit-test framework**, placed in the repo's `*.Tests` project under the same namespace as the source. Prefer helpers in `<Project>.Tests/Helpers/` over custom in-memory DB setups.

Every test class must cover:
- **Happy path** — expected inputs produce expected outputs
- **Error / failure cases** — invalid input, missing entity, dependency throws
- **Boundary / edge cases** — null inputs, empty collections, zero/max values
- **Authorization** (if applicable) — unauthenticated or unauthorized callers are rejected
- **All distinct outcomes** (if the class persists status logs at multiple exit points) — one test per reachable status value; do not leave `Processed` or `PartiallyProcessed` untested when skip/error paths are covered

```bash
dotnet test "$WORKSPACE_ROOT/<repo>/<Repo>.Tests.csproj" 2>&1 | tail -20
```

If tests fail: **REQUIRED: superpowers:systematic-debugging** — read the complete output, identify root cause, fix implementation or test, re-run. Do not proceed until all pass.

Skip for: database SQL-only changes, UI TypeScript/React changes, trivial config-only changes.

**After all tests pass → go directly to Step 6.**

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 6 — Validate ACs

For each AC from the state file (skip any listed in `plan.acs_out_of_scope` — show those as `out of scope (accepted at plan gate)`, never as a gap):

```
AC 1: <full text> → ✓ DONE / ~ PARTIAL / ✗ NOT ADDRESSED
```

For any PARTIAL or NOT ADDRESSED: explain what's missing and fix it before moving on.

**Visual verification (UI SPA changes).** A passing type-check and lint do not prove a UI change *looks* right — padding, icon size/alignment, wrapping, disabled/empty states, and layout regressions only surface when rendered. For any **visual** AC, render the changed view in the running SPA and capture a screenshot (use the `start-stack` skill to launch it, or `verify-ticket` to drive it) before marking that AC ✓ DONE — this is the visual instance of **REQUIRED: superpowers:verification-before-completion**. If it genuinely can't be rendered locally, say so and mark the AC visually-unverified — never treat a green build as visual proof.

**After all ACs validated → go directly to Step 7.**

---

## Step 7 — AI self-review

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> implement-ticket 7 self_review`

Read every file changed in this ticket and run it through **every** checklist in
[self-review-checklists.md](self-review-checklists.md): **Depth checks (run FIRST — data-access patterns,
one-helper-verified, insertion-order, consumer-trace)**, then Security, Performance, Correctness, Style
conformance, Code quality, Frontend/React (UI only), Blast-radius, and Cross-artifact consistency.
Categorise every finding **HIGH / MEDIUM / LOW** and report it in the Findings format defined there.

The **Depth checks** are correctness-critical and non-negotiable: they catch shallow execution a green build
and a passing happy-path test hide (a missing soft-delete filter, duplicated precedence, an override a
code-read calls safe but a runtime path clears). A green gate is not the verdict — the grep/trace/run is.

Honesty discipline for this step is **REQUIRED: superpowers:verification-before-completion** — do not report a checklist item as clean without the grep/read/render that proves it.

- **HIGH** — auto-fix and list every fix with file, line, and reason
- **MEDIUM** — show to user, wait for decision before fixing
- **LOW** — list only, do not fix

After auto-fixing HIGH items, re-run the build check (Step 4) **and re-run the Depth checks on the fix itself** — not just the original code. An auto-fix is fresh code written mid-review: a re-routed control flow can drop a sibling output, a new query can miss the soft-delete filter, a moved block can duplicate logic — the exact defects the Depth checks exist to catch. A HIGH fix is not done until it passes the Depth checks too.

**After self-review → go directly to Step 8.**

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 8 — Test scenarios: automate what you can, guide the rest

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> implement-ticket 8 test_guide`

> **Resume guard:** if you are RESUMING at this step (after compaction) and `$WORKSPACE_ROOT/.claude/tickets/<ticket>.test-guide.md` already exists **and** the AUTO specs under `$WORKSPACE_ROOT/e2e/tests/<ticket>/` are present, do **not** re-author them — they were written with the full implementation context, and a post-compaction rewrite would be weaker. Present the existing guide + spec list and go to Step 9. (On a fresh re-implementation after a scope change, author anew; it overwrites the stale set.)

Scenarios are derived and authored **here** — while the full implementation knowledge is still in context — never in push-ticket (which often runs post-compaction, where a checklist degrades to AC paraphrasing). Each scenario becomes one of two things, both persisted so the verify/review gate re-presents them instead of rebuilding:

- **AUTO** → an automated spec — a Playwright spec on the `$WORKSPACE_ROOT/e2e` harness, or (for the grid UI) a feature on your existing UI test suite (Step 8.5). `verify-ticket` runs these and emits evidence. **This is the goal for *every* scenario, including the complex ones** — they are exactly the ACs worth proving. Difficulty (specific external data needed, a multi-step admin→user reopen flow, a grid interaction, a multi-source/mixed combination) is **not** a reason to skip automation — it is a reason to (1) pick the right surface and (2) **ask the user for the specific input you're missing** (the record with the right shape, a flag, a reopen flow) and build it *with* them. The whole point of the harness is one shareable report proving **all** ACs were exercised.
- **MANUAL** → a checklist item in the manual guide (8b/8c). This is **never the agent's default or fallback.** A scenario becomes MANUAL **only** when (a) it is genuinely unautomatable on *any* surface (e.g. a subjective visual/aesthetic judgement) **and** (b) the user has **explicitly decided** to leave it manual. Never classify a scenario MANUAL because the setup is hard or needs your help — propose the automation and ask. Unit-covered ACs (a GREEN unit test already proves them) are a separate category — neither AUTO-e2e nor MANUAL.

### 8.0 — Ensure the e2e harness (lazy bootstrap — do this BEFORE classifying)

> **Reuse before authoring (read-only, cross-workspace).** Sibling workspaces accumulate specs + fixtures that are gold for similar ACs (external-data, mix vs non-mix, …). Before writing specs or fixtures from scratch, glance at the other workspaces and **adapt** what fits into THIS workspace's `e2e/` (copy/adapt — never depend on another workspace's files at runtime):
> ```bash
> for d in "$WORKSPACE_ROOT"/../*/; do [ "$d" = "$WORKSPACE_ROOT/" ] && continue; [ -d "$d"e2e/tests ] && echo "has e2e: $d"; done
> # then read promising ones: <other>/e2e/tests/  and  <other>/e2e/fixtures/  for a matching shape
> ```

The AUTO path needs the harness at `$WORKSPACE_ROOT/e2e`. It is **not** created by `/setup` (kept lean) — it is provisioned on first use. **Do not fall back to MANUAL just because `$WORKSPACE_ROOT/e2e` is absent — provisioning it is the whole point.** Run:

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/ensure-e2e.sh"
```

Branch on the final stdout line:
- **`E2E|ready`** / **`E2E|installed`** → harness present → classify AUTO normally (8a).
- **`E2E|needsenv|…`** → `.env` isn't built. **This is YOUR step — build it now** (you have Bash; the only human input is creds). `.env` is a prerequisite: do **not** discover data (8.6), prove specs green (8.5), or suggest specific test data until it exists. Run this exact sequence, in order:
  1. **Find the environment — exhaustively.** Use `test_scope.environment`; if it's unset/unconfirmed, search in order: the **ticket → its dependencies → the epic → the epic's related/child tickets** (QA comments often name the environment + record used to test a sibling). If a candidate is found, **use it**. Only if **none** is found, ask the user (suggesting a known QA/dev environment). Never assume a default, and **never propose a production environment** (QA/test only; if a candidate looks like prod or you are guessing, ask).
  2. **Load creds — privately.** The **username** is fine to ask for in chat (not secret). For the **password, never have the user paste it in the session** (it lands in the transcript): ask them to write it into a gitignored drop file — `e2e/.login` (just the password, one line) — and reply "done". (Only if the user explicitly says session-sharing is fine may you take it in chat.) If `.env` already holds creds, none of this is needed.
  3. **Build `.env` yourself**, reading the password from the drop file so it never enters the transcript: `cd "$WORKSPACE_ROOT/e2e" && E2E_LOGIN_PASSWORD="$(cat .login)" node build-env.mjs <environment> <user>` (add `--with=<domain>` per the ticket), then **delete the drop file**: `rm -f .login`. The password now lives only in the gitignored `.env`. Infra/credentials are assumed up — only if it errors do you refresh your cloud credentials / check connectivity. Never echo the password.
  4. **Next steps** — only now: discover data (8.6), author specs (8.5), prove green, against the built `.env`.
- **`E2E|noscaffold|…`** → this workspace genuinely has no scaffold (not provisioned by a `/setup` that ships `workspace/e2e`). **Only now** is MANUAL the right fallback — say so with the reason and continue as a manual guide.
- **`E2E|failed|…`** → report the error; retry or fall back to MANUAL with the reason stated. Never hide it.

### 8a — Plan automation for every scenario (MANUAL only by explicit user decision)

List the scenarios from *this ticket's implementation* (one per AC + the mandated negative/boundary cases — same derivation rules as the guide). For **each**, decide how you will **automate** it — do **not** pre-sort any into a MANUAL bucket:

- **Pick the surface:** Playwright (this harness) for API/DB and UI — including the **`ui` fixture** for SPA UI; your existing UI test suite is the alternative for heavy grid flows (the framework-selection rule, Step 8.5). A grid/overlay/subtotal flow is automatable — it is **not** "manual."
- **For the complex ones, name the specific input you need from the user** to build the spec rather than punting: the record with the right shape (e.g. one with both external actuals and a toggle-on measure), a feature flag, a DB precondition, an admin→user reopen flow. Offer to **discover the data yourself** in the `test_scope` environment if the user prefers (the understand-ticket "find it, don't assume" path).
- **Unit-covered** ACs (an existing GREEN unit test already proves them) are recorded in the **coverage matrix** as `unit-covered` (Step 8.6) — not an AUTO/MANUAL scenario, not e2e, not manual.
- **Logic YOU authored is never MANUAL-only.** A self-authored branch (a new distribution pass, a precedence/merge helper, an overlay) must be proven by a **unit test** or an **AUTO spec that executes it** — exactly as you'd unit-test the mapper. If an e2e spec can't reach it this run, **write the unit test** rather than deferring your own logic to a human eyeball. MANUAL is for product/visual/data-setup judgement, never for proving code you wrote runs correctly — the insertion-order/consumer defects the Depth checks hunt live precisely in those self-authored paths.

Then present the plan and **wait for the reply.** The question is *what help you need to automate the hard ones* — and whether the user wants to **explicitly** exempt any to manual. It is **not** a "pick a manual-guide level" prompt:

```
Verification plan for PROJ-XXX — I will automate every AC (specs run by verify-ticket → one shared evidence report).
  Ready to automate now:   <AC → surface (Playwright / UI suite) → what it asserts>
  Unit-covered already:    <AC → which GREEN unit test (no e2e needed)>
  Need your input to automate (complex — I'll build it WITH you):
     <AC> — <automation approach + surface> — needs: <the exact data / flag / flow you must supply or confirm>
     ...

Reply with the inputs for the complex ones (or "find it" and I'll discover the data in the environment).
MANUAL is NOT a default: if you want any AC left manual instead of automated, say so explicitly and
name it — otherwise I automate all of them.
```

Only scenarios the user **explicitly** marks manual become MANUAL (authored in 8b at the level they ask — see [manual-guide-levels.md](manual-guide-levels.md)). Everything else is built as a spec in 8.5. If the user exempts nothing, there is no manual guide — go straight to 8.5.

### 8b — Author the guide

Author the MANUAL guide at the chosen level following **[manual-guide-levels.md](manual-guide-levels.md)** — it holds the rules that apply at every level (derive from *this* implementation, concrete expected results, a separate negative item for every filter/exclusion AC, the data-loss guard for sweeps/bulk-deletes, skip out-of-scope ACs, the closing "evidence reviewed and approved" line) and the Basic / Standard / Full structures. Only the scenarios the user **explicitly chose to leave MANUAL** in 8a go in the guide; everything else is automated (specs in 8.5).

### 8c — Persist and present

Write the full guide markdown to a temp **non-dot** path with the Write tool (`$WORKSPACE_ROOT/<ticket>.test-guide.md`), then persist it via the helper (plain command — auto-approved, deletes the temp):

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/save-test-guide.sh" <ticket> "$WORKSPACE_ROOT/<ticket>.test-guide.md"
```

Then present the guide in chat. Do **not** ask for test approval here — that gate belongs to the implementation review (complete-ticket) and push-ticket.

**After the manual guide is persisted (or skipped because no scenario was left MANUAL) → Step 8.5.**

### Step 8.5 — Write the AUTO specs on the e2e harness

For each `AUTO` scenario, write/extend a spec at `$WORKSPACE_ROOT/e2e/tests/<ticket>/<name>.spec.ts` on top of the fixture library (`fixtures/core` + only the domain modules the ticket needs). These are what `verify-ticket` runs.

- **Pick the surface tool (framework selection).** Default to **Playwright** (this harness) for API/DB scenarios and UI. For **SPA UI**, two routes both work — pick per scenario:
  - **Playwright `fixtures/ui` (default).** Drives the SPA via `openRecord` / `authParam` / `selectFirstItem`, cross-checks against the API via `apiValues` (authoritative). Target-agnostic via `E2E_UI_URL`/`E2E_UI_PATH` — drives the UI dev server (default) or the host in Docker, whichever `start-stack` brought up, pointed at YOUR local API so working-tree changes are exercised. **Biggest win: the UI outcome and the API/DB mechanism land in ONE layered report.**
    - **🔴 PRECONDITION #1 — point the SPA at your LOCAL API, or the UI test is meaningless.** The SPA
      resolves its data host from `ENV_MAP[env].hostname` in `web/ui/client/utils.js`; the auth  // EXAMPLE — replace with your app's specifics
      param's `env: 'QA'` defaults to the **deployed** API host, and **`API_SERVER` on
      `npm run dev` does NOT redirect it**. So the dev-server SPA reads ALL data from deployed QA (no
      unmerged code) unless you override `ENV_MAP.QA.hostname` → `https://localhost:<port>` (debug-only;
      hot-reloads). Symptom when wrong: a backend-populated value renders BLANK while the API returns it.
      See start-stack Option B step 2. Verify a request actually hits `localhost:<port>` before trusting a blank.
    - **Read the grid with `readGrid`** (the proven READ_GRID technique): it reads the SELECTED item's  // EXAMPLE — replace with your app's specifics
      console row (`ConsoleSelection-module-root`), matching header↔value by left-x, keyed by column **label**
      (e.g. `pairs['Actual Gross Cost']`). This correctly reads backend-derived values.
      Run the dev server with `AUTOMATED_TEST=true` for semantic `data-test` where helpful. **Do NOT rely on
      `readConsoleGrid`** for derived values — its base `tableCell` cells read BLANK for them (the value lives
      in the selection row); it's only useful for raw non-derived columns. Precondition: the asserted columns
      must be **displayed in the record's grid view** (column config) — a per-ticket data precondition.
  - **Your existing UI test suite** (the maintained feature set) — prefer when the grid interaction is heavy enough that the product's `data-test` selectors + built-in scroll handling beat the DOM-read approach. Local-capable (point `ENV_URL`/`__API_SERVER__`/`__AUTH_SERVER__` at your local API so it sees unmerged changes), auths via the same base64 `?auth=` param; fold its `testReports/` screenshots into the evidence.
  Keep the API/DB **mechanism** as a Playwright spec here either way (layered evidence). AUTO/MANUAL classification and the evidence pack are framework-agnostic — they wrap whichever ran.
- **Self-seed, self-restore.** Create state via UI/API in `beforeAll`/`beforeEach`; reset anything toggled in `afterEach`/`afterAll`. SELECT-only DB reads are fine; any write/DDL/save must be tagged `@destructive` (verify-ticket runs those under per-scenario approval — the DB-write-approval rule).
- **🔴 Per-AC data STATE — never reuse one record to test everything.** The product is state-dependent: the same column reads blank / read-only / populated depending on the item's state (externally-actualized vs editable, single-vs-mix-combination, has-override, flag on/off, source type). Forcing one "source of truth" record onto every AC produces false conclusions. For EACH AC: (1) read the **source** to learn the exact state it needs (which model flag, `field.disabled`/`isEditable`, override, source type, which view renders it); (2) **query the environment DB** for a record genuinely in that state (discover the richest matching record — don't assume); (3) use a DIFFERENT record per AC as needed; clone+seed only when no natural record exists; (4) if nothing is in the needed state, that's a finding — surface it, don't fake the value.
- **Assert contracts, not live values.** Discover the record at runtime (shared QA data drifts in days) and assert the relationship/mechanism (e.g. "standard actual == Σ the external source"), not a hard-coded number or a live record name.
- **Layer the evidence.** For a user-facing AC, assert both the API mechanism **and** the user-visible UI outcome; cross-check the UI value against the API value (authoritative). Capture screenshots/traces (the shared config already does `trace: 'on'`).
- **Prove green now** (needs the harness's `.env`: if Step 8.0 reported `E2E|needsenv`, author the specs now but defer this green run until the user has built `.env` via `build-env.mjs`). Run `cd "$WORKSPACE_ROOT/e2e" && npx playwright test tests/<ticket>/` and confirm green before persisting — never hand `verify-ticket` red or never-run specs (this is **REQUIRED: superpowers:verification-before-completion** for the specs themselves). A scenario you genuinely cannot automate end-to-end (only feasible at unit level) is covered by a unit test instead — note which, and reclassify it out of AUTO.

### Step 8.6 — Coverage matrix (test-case sufficiency)

**One test case rarely covers a ticket.** Before finishing, prove the cases are sufficient:

1. From the ACs + implementation, enumerate the **variation dimensions** — each input/condition that changes behavior (each measure/target, each source, precedence, on/off, single-vs-mixed / multi-combination, each code path, feature flag, manual-override-preserved, …).
2. Build a **coverage matrix**: dimension/combination → the minimal set of distinct cases that exercise it. Note which dimensions need a **different** record than the first.
3. **Query the `test_scope` environment for the richest case**, don't settle for the first feasible one (e.g. find a multi-combination record for the mixed-source dimension). Prefer naturally-occurring data; seed via UI/API; DB writes only with approval. If the data needed for a dimension can't be found, that's a finding — surface it (the understand-ticket "ask, never assume" rule), don't fabricate a value.
4. Add cases until **every** dimension is exercised by a spec (or, where only feasible at unit level, by a named unit test — say so).
5. Record the matrix in state and **name any uncovered dimension** — never let one green case imply full coverage.

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> implement-ticket 9 saving_state`

**→ Step 9.**

---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

## Step 9 — Save implementation state

Update `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. Set `flow` to `null` — this skill is complete. Preserve all existing fields, update `phase` to `implemented`, and add:

```json
{
  "phase": "implemented",
  "implementation": {
    "repos_done": ["api", "web"],
    "files_changed": ["api/src/path/File.cs", "api/Program.cs", "web/src/Component.tsx"],
    "tests_passed": true,
    "build_passed": true,
    "ac_validation": [
      { "ac": "<AC 1 full text>", "status": "DONE" },
      { "ac": "<AC 2 full text>", "status": "DONE" }
    ],
    "self_review": {
      "auto_fixed": ["<description>"],
      "medium": ["<description>"],
      "low": ["<description>"]
    },
    "test_guide": {
      "manual_level": "basic | standard | full | none",
      "path": ".claude/tickets/<ticket>.test-guide.md",
      "scenarios": [
        { "id": "ac1-positive", "ac": "<AC text>", "mode": "AUTO", "spec": "e2e/tests/<ticket>/<name>.spec.ts" },
        { "id": "ac2-negative", "ac": "<AC text>", "mode": "MANUAL" }
      ],
      "coverage_matrix": [
        { "dimension": "<variation dimension>", "covered_by": "<spec path or unit test>", "status": "covered | unit-covered | uncovered" }
      ]
    },
    "test_approved": false
  },
  "saved_at": "auto"
}
```

`test_approved` is **always written as `false` here — including on a re-implementation** where a previous round's state had it `true` (the old approval covered code that no longer exists; "preserve all existing fields" applies to the other top-level fields, never to this flag). The complete-ticket implementation review gate sets it `true` when the user replies "evidence reviewed and approved" there (after verify-ticket), which lets push-ticket skip straight to the git work.

`files_changed` must include every file touched — planned files AND out-of-plan files (DI registrations, app settings, etc.). Push-ticket uses this list to stage exactly the right files.

Then tell the user:

```
✓ Implementation complete for PROJ-XXX.

AC validation:
  AC 1 → ✓ DONE
  AC 2 → ✓ DONE

Self-review: <N auto-fixed, M medium findings shown above>
Verification scenarios: <A> automated (specs under e2e/tests/PROJ-XXX/), <M> manual (guide shown above)
Coverage matrix: <K> dimensions — <all covered | list uncovered>

Next step: run /verify-ticket PROJ-XXX to run the specs + collect evidence, then review the
evidence and any manual items and reply "evidence reviewed and approved" (via /complete-ticket).
```
