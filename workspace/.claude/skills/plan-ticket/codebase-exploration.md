# Codebase exploration recipes

Reference for **plan-ticket Step 3 (Explore the codebase)**. Load this when exploring the repos a
ticket touches — it holds the product-specific "what to read, where, and how to verify" recipes: the
per-repo always-do list, the consumed/produced-contract verification gate, the ORM-model and
DB-script checks, and the per-label expansions.

> **The general plan-construction discipline — map the files each task touches, design focused units,
> bind to exact signatures — is delegated.** **REQUIRED: superpowers:writing-plans.** This file is only
> the product layer on top: which repos and files to read, and how to verify a contract against real code
> rather than the tracker/wiki description.
>
> **Use the Grep / Glob / Read tools for everything here — not raw shell (Bash *or* PowerShell).**
> Search content with Grep, find files with Glob, read files with Read. Do **not** shell out to
> `cd … && grep/find/cat/ls/head` *or* `Get-ChildItem -Recurse | … | ForEach-Object {…}` — raw-shell
> exploration triggers an approval prompt for every call (PowerShell script blocks are flagged as
> "arbitrary code"; multi-cmdlet pipelines aren't allow-listed) and is far slower and more
> token-heavy. Reserve shell for the helper scripts (`sync-repos.sh`, etc.) and build/test.
>
> **When you dispatch Explore agents for breadth, propagate this in each agent's prompt:** tell it to
> use **Glob/Grep/Read only** and **never** raw Bash/PowerShell for file or directory discovery.
> Subagents do not inherit this rule and will otherwise default to `Get-ChildItem -Recurse` — which
> prompts and burns tokens.

## Per-repo — always do

- Read the repo's `CLAUDE.md` for architecture, DI patterns, and conventions
- For each AC, search for existing code that handles similar behaviour — do not reimplement what already exists
- Find the domain entities, services, controllers, or components this ticket touches
- Find the files introduced by done dependencies (from state) — the current solution must integrate with them, not duplicate or contradict them
- Check epic constraints that restrict the approach
- Identify all hidden files likely to need updating beyond the obvious ones: DI registrations (`Program.cs` / `Startup.cs`), feature flag config, `appsettings.*.json` for all environments, swagger/OpenAPI definitions, route tables

## Verify consumed contracts against the producer's real code — including in-flight branches

For any contract this ticket binds to (endpoint, request/response DTO, message, enum), confirm the
**exact** shape against the producer's actual code, not the tracker/wiki description (which lags).
The producer is frequently in **another repo** (e.g. the api repo) and often on an **unmerged branch**
for in-flight deps — read it with `git -C "$WORKSPACE_ROOT/<producer-repo>" show origin/<branch>:<path>`
(after `git -C "$WORKSPACE_ROOT/<producer-repo>" fetch origin -q`) rather than checking it out. Bind the
plan to the **verified** field names + casing, required params, enum names + serialization, and
object-vs-scalar shapes. understand-ticket Step 6b should have captured this in each dependency's
summary — re-verify here for anything load-bearing, and bind to the code, not the description.

**This is a do-it-now gate, not a "verify later" note.** Before you draft the plan, read the producer
code for **every** consumed contract and record a one-line **verification ledger** entry per contract:
`<contract> — verified @ <repo>/<path>[@branch]` **or** `<contract> — documented-only, code unread —
<concrete why: repo absent / no branch access>`. "Verify at implement time", "re-verify when the API
lands", or trusting the tracker/wiki shape without opening the code are **not** permitted outcomes —
if the dependency is in-flight or even *To Do*, read whatever code exists (the controller/DTOs are
usually already merged on the dev branch) and bind to it; only a genuinely unreadable producer earns
the `documented-only` mark, with the reason stated. This ledger is a required plan section (Step 7) and
a gate blocker (Step 7 gate).

**The same rule applies in reverse — contracts this ticket PRODUCES.** For every contract this ticket
produces for a named in-flight consumer (a UI branch, a sibling service story), read the consumer's
actual branch code and bind the request/response shape to what it really sends and parses — ledger
entry `produced-for <consumer> — verified @ <repo>/<path>@<branch>`. Ticket text lags consumer code
exactly like it lags producer code (e.g. a consumer that renders errors only from a resolved response
would silently swallow a 4xx the ticket describes). If the consumer is itself an unmerged draft owned
by the team, the contract is **negotiable**: agree it explicitly (best practice wins over draft code)
and record the consumer-side follow-up in the plan rather than bending this ticket to a stale draft.

## For every ORM model the ticket reads from or writes to

- Read the model class file — check for missing navigation properties (e.g. a parent entity with a child table but no `ICollection<Child>` nav property). If the nav property is missing and the ticket needs to traverse the relationship, add it — do not work around it with extra repository methods.
- Before accepting any design choice in the ticket (param signatures, method names, return types, filtering patterns), grep for 2–3 analogous implementations in the codebase and verify the ticket's approach matches. If it diverges, raise it before writing the plan.

## If `db_script_required` label OR any ORM model/property is added or changed

- Read `database/CLAUDE.md`
- Find the latest version folder to determine the next script version number
- Read 2–3 recent scripts to understand the idempotency pattern
- Assess rollback safety: is this change additive (column with default, new table) or destructive (drop, rename, type change)? Flag destructive changes explicitly.
- **DML-only scripts (DELETE/UPDATE, no DDL):** do NOT create a Rollback file. Note in the plan: "No automated rollback — deleted/updated rows cannot be restored; restore from a DB backup taken before the script ran." Rollback stubs add noise without value for data-only changes.
- Identify query patterns introduced — do existing indexes cover them, or is a new index needed?
- **For every FK column in the new schema:** verify the referenced table exists in the codebase (`grep` for it in `database/` or ORM models). Do not omit a FK that the ticket specifies — if a precedent is cited to justify omitting it, read the referenced file first and confirm it actually has the same column before drawing that conclusion. If it doesn't, the precedent doesn't apply — follow the ticket.

## If `Breaking_Changes` label

- Identify all consumers of the changed contract across repos
- Add them to the affected repos list
- Assess whether the change can be deployed without downtime (additive vs breaking)

## If `Configuration` label

- Identify all `appsettings.*.json` files across all environments that need updating

## If ticket involves events, notifications, or async operations

- Check if async-messaging consumers/producers are involved
- Identify the message contract (type name, namespace, properties)
- Check if the consumer is feature-flagged and whether the flag needs updating

At the end of exploration, if repos were added beyond `proposed_repos`, note them explicitly:
_"During exploration I also found <repo> is affected because <reason>."_
