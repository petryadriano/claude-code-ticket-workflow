# Manual test-guide levels

Reference for **implement-ticket Step 8b (Author the guide)**. This applies **only** to scenarios the
user **explicitly chose to leave MANUAL** in Step 8a — MANUAL is never a default or a fallback. Every
other scenario is automated (Playwright, or your existing UI test suite for grid UI); a hard setup is
a reason to ask the user for the data/flow and build the spec *with* them, **not** to write a manual
item. If the user exempted nothing, there is no manual guide — skip 8b/8c. This file defines how to
write the guide for whatever the user *did* explicitly exempt.

## Rules at every level
- Derive each item from *this* ticket's implementation (code, plan, SQL) — never from the AC text alone.
- **Concrete expected results.** "Expected: it works" is not a test. State the value, the toast, the row count, the column name — and where the tester gets the *expected* number from (a SQL query, a prior screen, an input they typed).
- For **filter or exclusion ACs** (any AC that says "only X", "must not include Y", or a condition that omits something), write a **separate item for the negative case**: setup a record that does NOT meet the condition → same action → expected: that record is absent. Never bundle multiple filter conditions into one item.
- **For any sweep / bulk-delete / exclusion fix:** build before/after diagnostic SQL from the ticket's actual value-set, and add a **separate** item proving rows deliberately *excluded* from the sweep are **preserved** (the data-loss guard). A sweep test without the "excluded values survive" case is incomplete.
- Skip ACs listed in `plan.acs_out_of_scope` — there is nothing to test for a deferred AC.
- End the guide with: `Reply "evidence reviewed and approved" once you've reviewed the automated evidence and run these manual items, or tell me which item failed and what you saw.`

## Basic
One checklist item per AC: Setup (preconditions) / Action (exact step or API call) / Expected (concrete
result incl. side effects), plus the mandated negative items.

## Standard
Basic, preceded by **Part 0 — Start the stack**:
- A valid cloud session if the env config reads your cloud environment (assume it's set up; refresh credentials only if a call fails).
- Every service/SPA that must run: exact `cd` path under `$WORKSPACE_ROOT`, run command, and port — derived from `plan.repos`, the workspace `CLAUDE.md` port table, and repo READMEs. Explicitly name what is **NOT** needed (e.g. "the second SPA (:<port>) is not needed for this ticket").
- The branch each repo **and submodule** must be on — including dependency branches (e.g. an in-flight producer ticket's branch the working tree sits on) and "submodule must be on current dev tip because of <dep ticket>" caveats.
- Feature/entitlement flags to set, and where (environment admin, the SPA dev env-setup form) — name the exact flag keys the implementation gates on.
- URLs to open: the environment-prefixed host URL (e.g. `https://app.local/<environment>/`) and SPA dev-server URLs.

## Full
Standard, plus:
- **Data discovery** — SQL against the environment DB to locate usable records (parent/child records, configs) and to capture the **expected numbers before testing**; tell the tester what to write down. Include a legend mapping any magic enum/type values used in the queries.
- **DB preconditions** — confirm this ticket's (and its dependencies') DB scripts are applied to the environment DB the test host resolves to.
- **Test data from related work** — re-read `dependencies` and the related-work findings in the state file (and their tracker QA comments) for known-good environments, records, or import files used to test sibling tickets; name them in the guide.
- **Part 1 — Building blocks** — named, reusable steps (`[TOGGLE]`, `[FRESH]`, `[OPEN]`, `[SAVE]`…) with both the UI path and, where applicable, the SQL equivalent — referenced from scenarios so each scenario stays terse.
- **Part 2 — Scenarios** — one per AC plus the mandated negative cases, composed from the building blocks, with: concrete expected values; a persistence check (save → reopen → same numbers) wherever state is saved; ordering/safety notes (destructive or shared-environment scenarios **last**, with a "restore the flag/data afterwards" step).

## Recommendation heuristic (for the MANUAL guide level)
- **Full** when those scenarios span multiple repos, ship a DB script, depend on flags, or exercise a flow the user hasn't tested recently.
- **Standard** for a single-repo change in a service the user must still start.
- **Basic** when the user demonstrably knows the flow.

If **every** scenario is AUTO, there is no manual guide — skip 8b/8c entirely and go straight to Step 8.5.
