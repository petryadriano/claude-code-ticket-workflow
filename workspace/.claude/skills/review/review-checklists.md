# MR review checklists & known non-findings

Reference for **review Step 5 (Analyse and output the review)** — specifically Step 5b (code review
findings) and Step 5c (conventions checklist). Load this when grouping findings by severity and
when checking an MR against the team conventions.

> **The generic review rigor — severity triage, a concrete fix per finding, checking against the
> requirements not just the diff — is delegated.** **REQUIRED: superpowers:requesting-code-review.**
> This file is only the domain-specific layer on top of it: the conventions an MR must follow, and
> the things that *look* like findings but are documented, expected workflow.

## Known non-findings — do NOT raise these

These are known workflow, not defects. Raising them is noise.

- **Unbumped shared submodule / vendored-dependency pointer.** The shared-submodule gitlink is **never**
  bumped inside a consumer MR (the apps, the services) — it is staged by the team's own process *after*
  the sibling `shared` MR merges (`plan-ticket` and `push-ticket`/`prepare-mr.sh` forbid staging it in a
  consumer MR). So an unbumped pointer, a missing shared-submodule change, references to symbols not yet
  present in the pinned shared commit, and "won't compile in CI until the shared MR merges and the pointer
  is bumped" are all the **documented, expected** state — never flag them as a blocker or finding. At most,
  note the cross-repo dependency **only if the author did not already mention it** in the MR description (the
  convention asks them to write "Depends on shared MR …; merge shared first"). See
  `docs/ticket-workflow.md` (Submodules row).

## Conventions checklist

Flag any violation against your team's documented conventions, e.g.:
- Naming conventions for private fields / constants (per your code style)
- Required braces / formatting rules on control-flow bodies
- Import/`using` placement rules
- New persisted model → needs the matching DB script + the `db_script_required` label on the MR
- No ORM-generated migrations against environment-managed schemas
- Tests use your unit-test framework
- Commit message: `PROJ-XXX Short description`
- No N+1 DB patterns — pre-load sets, resolve in-memory
- DB context per-request only — never captured in a singleton
- DI registration: no duplicate interface registrations
