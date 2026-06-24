---
description: Step 3.5 of the lifecycle — run a ticket's AUTOMATED verification specs against a running stack, exercise @destructive cases under approval, and emit an evidence pack the human reviews at the complete-ticket gate. Usage: /verify-ticket PROJ-XXX
arguments:
  - name: ticket
    description: Tracker ticket ID (e.g. PROJ-123) or full tracker URL
    required: true
allowed-tools:
  - Read
  - Write
  - Bash
  - Skill
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root. The e2e harness lives at `$WORKSPACE_ROOT/e2e` (fixtures, test config, `.env`); specs live at `$WORKSPACE_ROOT/e2e/tests/<ticket>/`.

> **Persist state via the helper, never the Write/Edit tool on `.claude/tickets/*.json`** — write the full JSON to a temp non-dot path (`$WORKSPACE_ROOT/<ticket>.state.json`), then `bash "$WORKSPACE_ROOT/.claude/scripts/save-state.sh" <ticket> "$WORKSPACE_ROOT/<ticket>.state.json"`. Flow checkpoints use `set-flow.sh` (see other skills). Both are auto-approved; direct edits re-introduce the Windows dot-dir prompt.

## Required disciplines (Superpowers substrate)

This skill is the **evidence engine** — it is the domain layer that turns the generic honesty
principle into a replayable evidence pack. The generic discipline is delegated to Superpowers skills;
do not re-derive it here. Load and follow each at the point marked below:

- **REQUIRED: superpowers:verification-before-completion** — the generic *principle*: evidence before any "done / passing / works" claim, and never record a verdict from a spec that didn't actually run. This skill is the **mechanism** that realizes it — running the AUTO specs, the per-AC verdict discipline (Step 6), the @destructive per-scenario approval (Step 4), and the evidence pack + portal — all of which stay inline below. Apply the principle to the verifier's own claims; keep every evidence mechanic.
- **REQUIRED: superpowers:systematic-debugging** — root cause before *any* fix, whenever a spec **errors** (couldn't reach the API, auth failed, no fresh data) or a stack/env precondition is wrong (Steps 2–3). Read the complete error first; fix the env/precondition, then re-run — never patch a spec to make a BLOCKED run go green.

Product-specific mechanics these do **not** cover stay inline at their steps: the separation-of-duties rule, the AUTO/MANUAL split, the stack/env readiness probes, the DB-write-approval gate, the coverage-matrix check, the evidence-pack/portal format, and the "human approves at the complete-ticket gate" handoff.

---

## What this skill is (and is not)

`verify-ticket` is the **fresh-context verifier**. It runs the AUTO specs that `implement-ticket` (Step 8.5) wrote, collects evidence, and reports verdicts — it does **not** re-derive whether the feature is correct from implementation reasoning. **Separation of duties is non-negotiable:** the specs + `verdicts.json` are artifacts the human can replay (the trace viewer), not assertions to take on faith. Run it in a fresh context where possible; if it runs in the implementing session, still judge only by what the specs actually exercised.

**It replaces the "work through the manual test guide" step for AUTO scenarios.** MANUAL-only scenarios (those `implement-ticket` could not automate) still go to the human as a short guide — this skill lists them, it does not run them.

> **Maturity note (read once):** stack bring-up is handled by the `start-stack` skill (it brings up the UI + any working-tree local API); per-service deterministic `run-*` drivers remain a future step (`docs/automated-verification-design.md`, Phase 1). This skill **invokes** `start-stack` for bring-up (Step 2), then **verifies** readiness — it does not hand-start services. Auth uses `$WORKSPACE_ROOT/e2e/.env` — your environment-management creds (`E2E_USER` + `E2E_PASSWORD`, written once by `build-env.mjs` and reused for every ticket) plus the per-ticket `E2E_IMPERSONATE` (default the standard test user). Say so plainly when something isn't running rather than reporting a false BLOCKED.

## Step 1 — Load the verification plan

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> verify-ticket 1 loading`

- Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. Require `phase` = `implemented` (verification runs on implemented code). If earlier, stop and tell the user to finish `/implement-ticket` first.
- Read `implementation.test_guide` → the per-scenario list `{id, mode: AUTO|MANUAL, spec, ac}` and the **coverage matrix** (the variation dimensions Step 8.6 recorded). These drive what must be exercised.
- Confirm each AUTO scenario's artifact exists at its recorded `spec` path — UI runtime specs under `$WORKSPACE_ROOT/e2e/tests/<ticket>/`, and any grid-UI scenario the framework-selection rule routed to your existing UI test suite under `web/<ui>/tests/automated/`. If `mode: AUTO` scenarios are listed but their spec/feature files are missing, that is a process failure — stop and route back to `/implement-ticket` Step 8.5 (don't hand-write specs here; the implementing context owns them).

## Step 2 — Ensure the stack + env are ready

> ### Tier the evidence by cost per AC — bring up only what an AC's truth requires.
> Before bringing the stack up, decide **per AC where its truth actually lives** and reach for the CHEAPEST
> evidence that can prove it:
> - **Mechanism / mapping / precedence-in-isolation** → unit + API-contract spec. Cheap, reliable, **mandatory**.
> - **How a downstream layer uses the value** → consumer-trace (read the consumer) + the API spec.
> - **Behavior that only exists in the client** (apply path, render, save→reopen, override-vs-import) → a UI
>   runtime round-trip. **Escalate here only when the AC's truth lives in the client AND cheaper evidence
>   can't prove it — but then it's mandatory**, because a code-read of that layer can be wrong (see the
>   precedence callout after Step 5).
>
> Do **not** bring up the full UI stack to re-prove an AC already green at API+unit — that is the single
> biggest cost/fragility sink this flow has hit (a multi-hour screenshot detour that caught nothing).
> **Time-box** any UI/stack bring-up: if it fights back past your box, degrade that AC to a short MANUAL
> checklist item (note why) rather than chasing it for hours. verify replaces **most** manual QA, not 100%.

The specs hit a **running** local stack via `$WORKSPACE_ROOT/e2e/.env`. **Bringing that stack + env up is your job, not the user's** — verify, don't assume, and resolve everything you can yourself before turning to the user.

> **You own the setup; the user owns only the irreducible human inputs.** Work the bullets below and *do* each step yourself. The **only** things you may turn to the user for are: (1) the **login password** (written to the gitignored `e2e/.login` drop file) — and only when `.env` must actually be built; (2) an **external flag flip** you cannot perform (feature-flag service / config-param / environment-admin); (3) an **unmerged-dependency precondition** only they can apply (e.g. an unmerged sibling's DB script against the test environment). Environment discovery, `build-env.mjs`, the `start-stack` bring-up, and the readiness probes are **your work** — never present them as a choice or a blocker. **Don't prescribe infra/credentials upfront** — the developer is normally on the network with valid credentials. Surface a credentials refresh / connectivity check **only** as the diagnosed cause *after* a specific command has actually failed with an auth/network error.

> ### 🛑 Never lead with — or recommend — BLOCKED.
> BLOCKED is a **per-spec verdict** (Step 6) for a spec that genuinely could not run *after you tried to run it*. It is **not** a menu option, **not** a recommendation, and is **never** offered before you've built `.env`, brought the stack up, and run the specs. Presenting "Mark e2e BLOCKED" as a path — especially the *recommended* one — before attempting bring-up is the exact failure this gate exists to stop. Do the setup; run the specs; let the verdicts fall out of what actually executed. Never downgrade a hard AC to BLOCKED / MANUAL / partial to avoid the work.

Work through these, doing each yourself:

- **Harness present (idempotent):** `bash "$WORKSPACE_ROOT/.claude/scripts/ensure-e2e.sh"` — provisions `$WORKSPACE_ROOT/e2e` + installs deps if `implement-ticket` Step 8.0 didn't already. On `E2E|noscaffold` this workspace can't run AUTO specs (report it; those scenarios stay MANUAL); on `E2E|needsenv` build `.env` per the next bullet.
- **Env file (prerequisite — handle first):** `ls $WORKSPACE_ROOT/e2e/.env`. If missing, **build it yourself** (your step, not the user's), in this order: **find the target environment exhaustively** (`test_scope.environment`, else ticket → dependencies → epic → epic's related/child tickets; only if none is found, ask suggesting a known dev environment — never assume it, and **never propose a PRODUCTION environment** (QA/test environments only; if a candidate looks like prod, or you are guessing the name, ask instead of proposing it)) → **load creds in ONE step via the `.login` file** (never ask for creds in chat): run `cd "$WORKSPACE_ROOT/e2e" && node build-env.mjs <environment>`. With no creds yet it prints `LOGIN_NEEDED` and scaffolds a gitignored `e2e/.login` template — **open that file in an editor for the user** (`notepad "$WORKSPACE_ROOT/e2e/.login"` on Windows, best-effort) and ask them to do the **single** thing it needs: fill in `USERNAME` + `PASSWORD` for a user with **admin (or impersonation) access in the app**, **save**, and reply "done". Don't suggest or invent an account. On "done", re-run `node build-env.mjs <environment>` — it reads `.login`, writes the gitignored `.env`, and deletes `.login`. Then set `E2E_IMPERSONATE` to `test_scope.impersonate` (default the standard test user). Credentials/connectivity assumed up; only on an error → refresh credentials / check connectivity. Never commit `.env` or `.login`. **🛑 Never hand-write the `.login` contents, and never reference the file before `build-env.mjs` has scaffolded it: run `build-env.mjs` FIRST (the `LOGIN_NEEDED` path creates the template), THEN `notepad` THAT exact file. Asking for creds against a file that doesn't exist yet, or creating an empty/placeholder `.login` the user has to hunt for, is the exact failure to avoid.**
- **Services:** bring the stack up with the **`start-stack`** skill (`/start-stack <ticket>` — it brings up the UI and any working-tree local API, then reports readiness + URLs). Then confirm each required port answers (`curl -sk -o /dev/null -w "%{http_code}" --max-time 4 https://localhost:<port>/`); for anything still down, surface it with the cause (`start-stack` names what it skipped and why) — and name what is **not** needed.
- **Feature/entitlement flags:** the test guide names the keys; feature-flag service / config-param / environment-admin flips are **external dependencies** — if a flag the feature gates on must change, ask the user to set it (don't fake it), then continue.
- **Unmerged dependencies:** if the ticket depends on an unmerged sibling (DB script / producer branch), confirm its precondition is applied to the test environment (see the "unmerged-dependency" rule) before running.

If a genuine blocker remains **after you've done all of the above**, it is strictly one of the three irreducible inputs above (password drop file / external flag flip / unmerged-dependency precondition) — gather the full set and ask **once**, rather than discovering them one at a time. A blocker is something only the user can resolve; it is never something you could have done yourself but chose to hand off.

**Rationalizations — STOP if you catch yourself here:**

| Rationalization | Reality |
|---|---|
| "This is a QA-environment env; the stack probably can't come up — recommend BLOCKED / MANUAL." | You don't know until you run `start-stack` and probe. Attempt bring-up first; BLOCKED is a verdict from a failed *run*, not a forecast. |
| "It's infrastructure, not the code — BLOCKED is the honest call." | BLOCKED-before-attempt isn't honesty, it's avoidance. Honest = you built `.env`, ran the specs, and a specific spec couldn't execute. |
| "I'll gather creds + cloud session + connectivity + `start-stack` + the DB column and ask the user to handle it all." | Only the password drop file, an external flag, or an unmerged dep are the user's. Environment lookup, `build-env.mjs`, and `start-stack` are yours — don't bundle your own work into the ask. |
| "Better warn them they'll need their cloud session + connectivity up" / "I can't confirm the local stack reaches a cloud QA environment." | Both are assumed up and reachable. Listing them upfront, or asking the user to confirm reachability, is prescribing infrastructure you were told to assume. Raise it only after a command fails with an auth/network error. |
| "`.env` is missing, so I'm blocked on the user." | `.env` missing → *you* build it (find environment → get the password drop file → run `build-env.mjs`). The single user input is the password. |

**Red flags — you're about to repeat the failure:**

- Offering "Mark e2e BLOCKED" (or "leave as MANUAL") as an option **before** the specs have run.
- The word "Recommended" anywhere near BLOCKED.
- Listing "cloud session + connectivity" as a prerequisite/blocker, or asking the user to confirm cloud-environment reachability, rather than treating both as a post-failure diagnosis.
- A single ask that bundles things you could do yourself (environment discovery, `build-env.mjs`, `start-stack`) with the one or two things only the user can.
- Concluding the stack "likely can't be brought up" without having run `start-stack`.

## Step 3 — Run the non-destructive AUTO specs

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> verify-ticket 3 running`

```bash
cd "$WORKSPACE_ROOT/e2e" && npx playwright test tests/<ticket>/ --grep-invert @destructive
```

- The shared test config already sets `trace: 'on'`, screenshots, HTML+JSON reporters, `workers: 1` (shared-environment data is never parallelized).
- **Surface-tool selection:** the default runner runs the UI runtime specs. If `implement-ticket` drove a **grid-UI** scenario via your existing UI test suite instead (the framework-selection rule), the default runner won't run it — run that suite locally for those scenarios (pointed at the local API), and fold its report screenshots into the evidence. Same verdict model + pack; only the runner differs.
- Specs self-seed via UI/API and reset what they toggled (fixtures own this). They assert **contracts** on shared data (not live record names) and discover test data at runtime — a green run means the mechanism held, not that a hard-coded value matched.
- If a spec **errors** (couldn't reach the API, auth failed, no fresh data) that is **BLOCKED**, not PASS and not FAIL — root-cause it (**REQUIRED: superpowers:systematic-debugging** — read the full error; an env failure needs the precondition from Step 2 fixed, not a spec edited to go green), fix the env, and re-run; never record a verdict for a spec that didn't actually exercise the path.

## Step 4 — @destructive scenarios (one at a time, under approval)

For any scenario tagged `@destructive` (seeds rows / flips a shared flag / mutates a saved record):

1. Present the **exact** mutation (the SQL, the API call, or the UI save) and its restore step.
2. **Wait for per-scenario approval** — this is the DB-write-approval rule; SELECT-only reads never need it, but any write/DDL/save does, every time.
3. Run the single scenario, run its **restore** step, and **verify the restore** (re-query / re-read) before moving on.
4. Prefer creating state via UI/API and a naturally-occurring/throwaway record over a raw DB write; use a different record than any "naturally fresh" one the read-path specs depend on, so you don't break their precondition.

## Step 5 — Coverage check (test-case sufficiency)

Before emitting verdicts, confirm the **coverage matrix** from Step 8.6 is actually exercised — one green case rarely covers a ticket:

- For each variation dimension (each target/measure, source, precedence, single-vs-mixed/multi-combination, each code path, flag on/off, etc.), confirm a spec touched it. If the only feasible coverage for a dimension is unit-level (e.g. a save-recompute path that can't run E2E without mutating shared data), record it as **unit-covered** and say which test.
- **Name every uncovered dimension explicitly** in the evidence — never let one passing case imply full coverage. A missing dimension is a finding, not a footnote.

### 🛑 A precedence / override / merge verdict comes from the RUNNING path — never from reading the model.

For any AC about which value **wins** — precedence, override-vs-import, source overlay, merge, "X is
preserved / not replaced" — the verdict MUST come from a spec that drove the real runtime path end to end
(e.g. set the override → let the new data arrive → reopen → read what the user sees). Reading the model and
concluding "the override wins" is **not** evidence: a layer you didn't read (a client apply path, a read
overlay, a save-time recompute) can clear or overwrite the value first.

This is the most expensive failure this flow has seen. On one ticket, **two independent, competent passes**
read the precedence in the model (`_override` before `_externalValue`) and called the override-survives AC satisfied —
both wrong; only a save→new-data→reopen round-trip revealed the front end clears the override before that
precedence ever runs.

| Rationalization | Reality |
|---|---|
| "The model returns the override before the external value — it wins." | You read one layer. A client apply / read overlay / save recompute can clear it first. Only the running path shows what the user sees. |
| "Tracing the precedence in code is faster than building the round-trip." | Faster and wrong — a prior pass did exactly this and recorded an unverified AC; the bug was real. |
| "It's existing/framework behavior, not this ticket — I can reason it's fine." | "Existing behavior" is precisely where the prior pass dismissed the real clobber. Exercise it. |
| "Both code paths agree, so the merged result is obvious." | Paths compose; the composition is what ships. Run it. |

**Red flags — STOP, build the round-trip:** a precedence/override/merge verdict whose evidence is a code
citation not a spec run; "preserved / not replaced" asserted without a save→new-data→reopen simulation;
"existing/framework behavior, so it's fine" on a value-precedence AC.

### 🛑 A PASS proves the CHANGE only if the spec actually executes the changed code — confirm with a negative control.

A green spec is evidence for the change under test **only if the change is in the path the spec runs**. A
spec can go green for reasons that have nothing to do with the code: a value the **client** computed and
saved, **pre-existing** data, or a **deployed / async** recompute running merged code instead of the local
working tree. Before recording PASS for any AC tied to a code change, confirm the spec exercised THAT code.

The proof is a **negative control**: revert (or disable) the change, re-run — the spec MUST go **RED**. If it
stays green, the change is not what produces the result. Cheaper interim check: instrument the changed code
(a log at its entry) and confirm it fired during the run — but validate the instrumentation first (a startup
marker that you see in the log), since a silent logger proves nothing.

This is now the most expensive failure this flow has seen. An AC's e2e was green across many runs, but the
value arrived via a *different* path (the client-applied read-time value, persisted on save) — the code
change was **never executed and turned out to be unnecessary**. Only a negative control (revert → still
green) revealed it. Compounding it: the "save" recompute runs **asynchronously off the request** (an async
entitlement enqueues the recompute, dispatched to a deployed worker → the deployed core API), so a local save
e2e exercised **deployed merged code, not the local change**. To verify local code on
such a path, force it synchronous/local (bypass the async flag on **both** API and client) **and** run the
negative control.

| Rationalization | Reality |
|---|---|
| "The spec is green, so the change works." | Green proves the *outcome*, not the cause. Revert the change — still green ⇒ your code didn't produce it. |
| "It persisted the right value, so my persist code ran." | The value can come from the client, pre-existing data, or a deployed/async recompute. Prove your code ran (negative control / instrument). |
| "I traced the code; the change is obviously on this path." | This flow's persist runs async in a *different process* (deployed API via a queue). Trace WHERE it runs at runtime; don't assume the local process. |
| "No time for a negative control." | A green test you can't flip red isn't evidence — it's the most expensive false confidence (a whole ticket was built on one here). |

**Red flags — STOP and run the negative control:** claiming a change works or "is needed" from a green spec
you never reverted; assuming a local e2e exercised local code when the recompute is async/queued/deployed; a
PASS on the AC the change targets with no instrumentation AND no negative control behind it.

**Verdict includes NECESSITY, not just correctness.** If reverting the change leaves the spec green, the
change may be **unnecessary** — record that and re-scope, rather than shipping a redundant change. "Would
anything break without this?" is part of the verdict.

**When the run reveals a real defect → triage before routing it back to implement.** Classify against three
observable predicates and record the answer in the finding: **Ours?** (code this ticket changed vs a
pre-existing/adjacent layer) · **In scope?** (this ticket's repos vs out-of-scope code) · **Bug or spec?**
(unambiguous violation vs a conflict with another AC = a product decision). Only *ours + in-scope + clear
bug* routes to `/implement-ticket`; otherwise **file the finding** (evidence + a precise product/dev
question), keep the verdict at-risk, and encode it as a `test.fail()` characterization spec — green while the
defect exists, **red the moment it's fixed** — rather than a permanently-red test or a green test that
asserts the bug. Do not expand scope to "fix" pre-existing or contested behavior.

## Step 6 — Emit the evidence pack

Produce, under `$WORKSPACE_ROOT/e2e`:

- **`playwright-report/`** — the HTML report (screenshots + replayable traces), already generated by the run.
- **`tickets/<ticket>/report.md`** (or attach to the state): **per-AC** verdict — `PASS | FAIL | BLOCKED | SKIP`, a confidence note, one line of reasoning, and the screenshot/trace link. Plus the coverage matrix with the uncovered dimensions called out, and the MANUAL scenarios the human still owns.
- **`verdicts.json`** — machine-readable `{ ac, scenarioId, verdict, spec, artifact }[]`.

**Verdict discipline** (the instance of **REQUIRED: superpowers:verification-before-completion** — every verdict is backed by the spec run that produced its artifact, never by reasoning about the implementation): no partial passes. Ambiguity → **FAIL**. A spec that didn't run → **BLOCKED** (with why). Only `PASS` when the spec exercised the path and asserted the contract green.

**Serve it and auto-open it for the user — never make them open a zip.** Start the report server in the **background** (it serves *and* opens the browser, and would otherwise block the foreground): `cd "$WORKSPACE_ROOT/e2e" && npx playwright show-report` — run it via the Bash tool's background mode (or append ` &`). It serves the HTML report (screenshots + replayable traces) at a `http://localhost:<port>` URL and opens the browser; capture that URL from the output and hand it to the user. (`playwright-report/` is self-contained, so it also zips cleanly if they later want to attach it to the tracker card — but the review itself is the served, auto-opened page, not a zip.)

## Step 7 — Save state and hand to the gate

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> verify-ticket 7 saving_state`

Update `<ticket>.json` (temp file + `save-state.sh`). Keep `phase: implemented`; set `flow: null`; add:

```json
{
  "verification": {
    "ran_at": "auto",
    "evidence_path": "e2e/playwright-report",
    "report": ".claude/tickets/<ticket>/report.md",
    "summary": { "pass": 0, "fail": 0, "blocked": 0, "manual_pending": 0 },
    "coverage_uncovered": ["<dimension> — <why / unit-covered by X>"],
    "verdicts": ".claude/tickets/<ticket>/verdicts.json"
  }
}
```

Do **not** set `implementation.test_approved` here — verification produces evidence; **the human approves it at the complete-ticket gate** ("evidence reviewed and approved"). That separation is the whole point.

Then tell the user:

```
✓ Verification run for PROJ-XXX.
  AUTO: <P> pass / <F> fail / <B> blocked   MANUAL still to do: <M>
  Coverage gaps: <none | list>
  Evidence: http://localhost:<port>/PROJ-XXX   (traces replayable)

Next: review the evidence (open a trace/screenshot) + run the MANUAL items, then reply
"evidence reviewed and approved" (via /complete-ticket) to proceed to /push-ticket.
```

If any verdict is **FAIL**, lead with it — never bury a failure under the passes.
