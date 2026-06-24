# Clarity-check catalog

Reference for **understand-ticket Step 7 (Clarity check)**. Before presenting the summary, evaluate
the ticket for ambiguities that would block or derail implementation. Check **every** class below,
categorise each issue found, and ask before proceeding.

> **The discipline of surfacing intent/requirement/design ambiguity *before* building — clarifying
> questions one at a time, never proceeding on an unexamined assumption — is delegated.**
> **REQUIRED: superpowers:brainstorming.** This file is the domain-specific ambiguity catalog and the
> 🔴/🟡/🟢 categorisation it feeds; brainstorming governs *how* you raise and resolve the questions.

## What to check

**Scope and goal:**
- Is the goal clearly bounded — is it obvious what is in scope and what is not?
- Does the ticket describe a complete feature or is it half of something that depends on an unstated other half?
- Are there any contradictions between the description and the comments?
- **Description/epic vs ACs:** does the prose mention scope (a surface, button, app, field) that **no AC covers** — or do the ACs cover something the prose contradicts? A prose-vs-AC scope mismatch is a discrepancy: surface it as a 🟡 question before planning, don't silently follow one side. (E.g. the description says the button appears in **both** view A **and** view B, but AC1 says view A only.)

**Acceptance Criteria:**
- Is every AC specific and testable? Flag any that use vague language: "improve", "handle correctly", "appropriately", "as needed", "etc."
- Does every AC have a clear pass/fail condition?
- **AC ownership:** flag any AC that restates a *dependency's* already-delivered/QA'd behavior (its transport, background machinery, another repo's feature). Propose trimming it to this ticket's integration slice — or removing it — at the understanding gate, not after implementation. Also flag vestigial "X is unaffected" regression ACs when the ticket's scope touches no code shared with X (they send QA to test a flow this ticket cannot reach).
- Are there obvious scenarios the ACs don't cover (e.g., error paths, empty states, concurrent access)?

**Dependency alignment:**
- Does the ticket reference interfaces, services, classes, or contracts that differ from what the dependency actually delivered?
  - Example: ticket says `IFooService` but the dependency delivered `IFooRepository` — this is a contradiction that must be resolved before planning
- Do the error codes, enum values, or schema referenced in the ACs match what the dependency defined?
- **Mockup vs verified contract:** if a design mockup (Step 3c) shows fields, sections, or a data structure that the **verified API contract** (Step 6b) does not return — or shapes them differently (e.g. a shared "Includes" block vs per-record fields) — that is a discrepancy. The producer's actual code and the dependency tickets are **authoritative over a stale mockup**. Flag the mismatch as a 🟡 before planning so the UI is built to the real contract, not the picture.

**Technical clarity:**
- Are there implementation decisions the ticket assumes but doesn't specify (e.g., "persist in the finally block" — but what transaction scope? what if persistence fails?)
- Are there race conditions or ordering constraints not addressed by the ACs?

## Categorise each issue found

- 🔴 **Blocker** — cannot implement correctly without an answer (e.g., wrong interface name, contradictory ACs)
- 🟡 **Assumption** — can proceed with a stated assumption, but should be confirmed (e.g., an implicit error handling pattern)
- 🟢 **Minor** — cosmetic or low-risk ambiguity, note it but don't block

If there are any 🔴 blockers or multiple 🟡 assumptions, compile all questions into a single message and ask them before proceeding:

```
Before I save this understanding, I have questions that need answers:

🔴 [Blocker] <question — cannot implement without this>
🟡 [Assumption] <question — will assume X unless told otherwise>
...

Please answer these before I continue.
```

Wait for answers. Update the extracted context with the answers. Then proceed to Step 8.

If everything is clear (no blockers, no significant assumptions): proceed directly to Step 8 without asking.
