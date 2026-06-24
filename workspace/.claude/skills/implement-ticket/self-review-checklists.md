# Self-review checklists

Reference for **implement-ticket Step 7 (AI self-review)**. Read every file changed in the ticket and run
through every checklist below. Categorise each finding **HIGH / MEDIUM / LOW** and handle it per the
Findings rules at the bottom.

> This is the domain checklist. The *honesty discipline* behind it — never claim "reviewed / clean /
> done" without the evidence — is **REQUIRED: superpowers:verification-before-completion**.

## Depth checks (run FIRST — any miss here is HIGH)

These catch what a green build and a passing happy-path test do **not**: shallow execution that *looks*
done. A 3-run comparison on the same ticket shipped real defects past every green gate — a missing
soft-delete filter, precedence logic duplicated despite "route through one helper," and an override-vs-import
behavior that source-reading called correct and a runtime round-trip proved broken. Run each against the
**actual code**, not from memory.

- [ ] **Match the codebase's data-access patterns.** For every query you added or changed, grep a sibling
      query on the same entity/table and confirm you replicated its filters — soft-delete
      (`IsDeleted`/`Inactive`/`IsActive`), environment scoping, and any status/visibility predicate. A query that
      omits an established filter is a latent bug (leaks deleted / other-environment rows) even though it compiles
      and the happy-path test passes.
- [ ] **One helper, verified — not just intended.** If you centralized logic (precedence, mapping, a calc)
      in a helper, grep the codebase for *the logic itself* (its keywords/operations), not just the helper
      name, and confirm every call site routes through it. A second copy that "looks right" diverges
      silently. Duplicated logic is HIGH — collapse it.
- [ ] **Insertion-point / order proven.** If the change adds to a pipeline (overlay, distribution,
      middleware, filter chain), state where it runs relative to the others and trace one input through to
      confirm it wins/loses exactly as the AC requires (`+=` accumulate vs `=` override; a step that runs
      after can clobber yours). Read the order — don't infer it.
- [ ] **Consumer-trace before claiming an AC holds.** For each AC about a value the user sees or a behavior
      realized downstream (a client apply path, a renderer, a save/recompute), trace the value from your
      code to that consumer and confirm the consumer actually surfaces it. **For any precedence / override /
      merge / "is preserved / not replaced" behavior, a code-read is NOT proof — a layer you didn't read can
      clear or overwrite it, so that AC's verdict must come from running the path (verify-ticket), never from
      the model alone.** (Twice on one ticket a source-only "the override wins" read was wrong; only the
      round-trip revealed the client clears it first.)
- [ ] **Approach fidelity & blast radius (hot/shared/delicate path).** Confirm you took the
      lowest-blast-radius approach that mirrors the nearest existing analogue — an **additive hook /
      post-pass** over the unchanged flow, not a **control-flow change** in a delicate ("sequence matters" /
      bidirectional) method. A control-flow re-route is HIGH unless you have A/B'd it against the analogue
      and confirmed it drops/reorders **no sibling output** (a value/field the old path produced). If a
      leaner additive approach exists and you didn't take it, that's a finding — switch to it. (This is the
      review-time catch for the Step-3 "choose the approach" rule.)

## Security checklist
- [ ] Every new API endpoint has `[Authorize]` or explicit `[AllowAnonymous]` with a comment justifying it
- [ ] Object-level authorization: does the caller own/have access to the resource being acted on?
- [ ] All inputs validated at the entry point (validation library, data annotations, or manual guard)
- [ ] No raw SQL — or if present, fully parameterized with no string interpolation
- [ ] No sensitive data (PII, tokens, passwords) written to logs or returned in responses
- [ ] No secrets or connection strings hardcoded in code or config committed to source

## Performance checklist
- [ ] Read-only ORM queries use `.AsNoTracking()`
- [ ] No N+1 queries — `.Include()` used where navigation properties are accessed
- [ ] All queries have a `WHERE` clause or explicit pagination/limit — no unbounded table scans
- [ ] `CancellationToken` threaded through all async call chains
- [ ] No `.Result` or `.Wait()` on async code (deadlock risk)

## Correctness checklist
- [ ] Null guards on all external inputs and optional fields before use
- [ ] Collections checked for null/empty before iteration
- [ ] ORM entity properties match the DB schema (column names, types, nullability)
- [ ] No `async void` (except event handlers) — always `async Task`
- [ ] Disposable resources wrapped in `using` or properly lifetime-managed via DI

## Style conformance checklist
**Any violation here is HIGH — auto-fix without asking.**
For each file written or modified, re-read 5–10 lines of surrounding existing code and verify:
- [ ] Method calls match local formatting — all-args-on-one-line vs one-arg-per-line
- [ ] Log calls use the same placeholder style (`{0}` positional vs named `{Name}`) and the same argument-per-line layout as the rest of the file
- [ ] Object initializers match local style (inline vs multiline, trailing commas)
- [ ] Return/guard patterns match local style (early return vs single-exit)
- [ ] Exception handling shape matches local `try/catch` pattern

## Code quality checklist
- [ ] **Reuse over new (any layer).** For every NEW public construct (class, exception, DTO, wrapper, method overload, response shape): (a) grep for an existing mechanism first — exception families + global error middleware, resource/message classes, sibling response patterns — and match the **dominant** convention *by count across the codebase*, not the first example found; (b) confirm it has an **independent consumer** — a construct that exists only to serve one other new construct gets folded into it. An unjustified new construct is HIGH: simplify without asking.
- [ ] **File layout matches the destination folder** — e.g. one class per file where the sibling folder is one-class-per-file.
- [ ] No magic strings or numbers — use constants or enums
- [ ] No commented-out code left behind
- [ ] No `TODO` / `FIXME` introduced without a corresponding tracker ticket reference
- [ ] Logging added at appropriate levels for new flows (Info for key actions, Warning for recoverable errors, Error for failures)
- [ ] New public contracts (DTOs, interfaces, enums) placed in the correct layer/namespace per repo conventions
- [ ] Methods with >7 parameters — extract a parameter object or named record
- [ ] Private methods returning unnamed tuples with ≥3 elements — extract a private named record instead
- [ ] Private helper methods called from exactly one place and ≤3 lines — inline unless the name adds meaningful clarity

## Frontend / React checklist (UI SPAs — apply only if this ticket changed a SPA)
The checklists above are backend-shaped; for a UI/SPA change, also verify:
- [ ] **Stable references into pure children.** Handlers/objects/arrays passed to `PureComponent`/`React.memo` children are stable across renders (class methods or `useCallback`/`useMemo`), not created inline — an inline `() => …` or `{…}` defeats the memo and can break expected re-render behavior.
- [ ] **Async request races.** Every fetch that can be superseded (typeahead, refetch-on-filter-change) guards against out-of-order responses — `AbortController` or a sequence/`latest` ref — and the guard is applied to **every** such path in the change, not just one.
- [ ] **Reuse existing helpers/components first.** Grep the SPA's `api/`, `utils/`, `elements/`, shared `apps/` for an existing helper or component (e.g. a JSON-casing reader, a shared Input/Select/Button/Modal/Icon) before writing your own.
- [ ] **CSS Modules class hashing.** A `*.scss` imported as a module has its class names hashed at build time, so writing a *global* class name inside a module silently won't match. To affect a global class, put a scoped class on the element and target that — confirm how styles are wired (e.g. `config/webpack/.../styles.js`) rather than assuming.
- [ ] **Read a shared component's props/source before using a non-obvious prop.** A misused prop (e.g. a `fluid`/sizing flag) can silently distort layout — confirm its meaning in the component, don't infer from the name.
- [ ] **Hook dependency arrays** are complete and correct (no stale closures, no missing deps).

## Blast-radius checklist
**Any miss here is HIGH.** A diff review sees the lines changed, not the contexts they run in:
- [ ] For every **shared/reused** file changed (component, helper, base class), grep its importers/render sites/callers and verify the change is correct at **each** — or list the site as explicitly out of scope with why. If the plan has an Impact map, re-verify it against the final code; if a site was discovered that the plan missed, add it to the verification scenarios (Step 8).
- [ ] **Optional-prop gating smell (UI):** an element rendered unconditionally whose behavior comes from a prop that can be `undefined` at some render sites is a dead-control bug — gate the element's render on the prop (`prop && (...)`) or make the prop required.

## Cross-artifact consistency checklist
**Any mismatch here is HIGH.** If this change altered a *set of values* — an enum list, a magic-number set, status codes, a whitelist/blacklist — the same set is frequently duplicated in another artifact that does **not** appear in this repo's diff:
- [ ] Searched sibling repos — especially the database SQL (one-time cleanup / backfill scripts) — for the same value-set, and confirmed they match. A code fix to a value-set paired with a stale SQL `DELETE`/`UPDATE` using the *old* set is a data-loss bug. Map any raw magic numbers in SQL to their enum names to verify.
- [ ] If a sibling artifact must change too, it is listed in `files_changed` (and the producing repo is in `plan.repos`).

## Findings format

```
Self-review complete.

AUTO-FIXED (HIGH):
  - api/src/path/File:42 — <what and why>

MEDIUM (your call):
  - api/src/path/File:87 — <issue>

LOW (deferred):
  - api/src/path/File:12 — <note>
```

- **HIGH** — auto-fix and list every fix with file, line, and reason
- **MEDIUM** — show to user, wait for decision before fixing
- **LOW** — list only, do not fix

After auto-fixing HIGH items, re-run the build check **and re-run the Depth checks on the fix itself** (not just the original code) — an auto-fix is fresh code that can introduce the very defects those checks catch (a re-routed flow dropping a sibling output, a new query missing a soft-delete filter, duplicated logic). The fix isn't done until it passes them.
