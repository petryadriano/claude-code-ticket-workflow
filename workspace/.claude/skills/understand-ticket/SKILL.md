---
description: Step 1 of 5 — Fetch and understand a tracker card. Reads the tracker, resolves dependencies, extracts all ACs and context, and saves to disk. Run before /plan-ticket. Usage: /understand-ticket PROJ-XXX
arguments:
  - name: ticket
    description: Tracker ticket ID (e.g. PROJ-123) or full tracker URL
    required: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - WebFetch
  - mcp__tracker__getIssue
  - mcp__tracker__getIssueRemoteIssueLinks
  - mcp__tracker__searchIssues
  - mcp__tracker__getWikiPage
  - mcp__tracker__fetch
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Step 1 of 5 in the ticket lifecycle.

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

This skill is the **ticket-ingestion** layer. The generic engineering discipline is delegated to
Superpowers skills — do not re-derive it here. Load and follow each at the point marked below:

- **REQUIRED: superpowers:verification-before-completion** — evidence before any "read / verified / covered" claim, across the whole skill. Instances: the acquisition principle's "never silently treat an unread source as covered" (Steps 3–6), and the reading-audit + coverage-map honesty (Step 7b). Mark a source *read* only with the evidence (the file you Read, the page you fetched) — never assert coverage you didn't establish.
- **REQUIRED: superpowers:brainstorming** — surface intent/requirement/design ambiguity *before* planning: clarifying questions one at a time, never proceed on an unexamined assumption (Step 7 clarity check, and the Step 8 gate's question/correction loop). The ambiguity catalog and 🔴/🟡/🟢 categorisation are domain-specific; brainstorming governs *how* you raise and resolve them.
- **REQUIRED: superpowers:systematic-debugging** — when a fetch fails, read the **exact** failure (HTTP code / "SPA shell" / "NOAUTH") and root-cause *why* before recording it as a gap or guiding remediation (Steps 3d, 6, and the acquisition fallbacks). Don't record "couldn't read it" without the precise cause.
- **REQUIRED: superpowers:dispatching-parallel-agents** — when Step 6c surfaces multiple `[NOT analyzed]` related tickets the user asks you to read, fan them out: they are independent reads (different tickets, no shared state), so dispatch one focused agent per ticket in a single message and fold the returned summaries back in — rather than reading them serially.

Domain-specific mechanics these do **not** cover stay inline at their steps: the multi-source fetch
procedures, the state schema this skill writes, the dependency-resolution + producer-contract rules,
the spike lifecycle, the MANDATORY understanding gate, and the flow/journal/state-helper contract.

---

> **Journal in the moment.** The instant a real decision (with *why*), a dead-end, a clarifying answer, or a constraint the user states in passing occurs, append one line via `append-journal.sh`. Do it as it happens — not saved for later — because `/compact` can fire mid-step and only what's already on disk survives. A short ticket may produce zero entries; that's correct, not a miss. See the journal note in `complete-ticket`.

---

## Step 0 — Flow resume check

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json` if it exists. Check `state.flow`:

- If `state.flow.active_skill == "understand-ticket"`: first read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` if it exists (restores decisions, dead-ends, and open questions from before the context reset — honor every `DEADEND`, surface unresolved `QUESTION`s). Then print `"↩ Resuming understand-ticket from: <step_label>"` and jump directly to that step. Do not re-execute earlier steps.
- If `state.flow.active_skill` is set to a **different** skill: stop — `"⚠ <ticket> shows <other-skill> was mid-execution (step: <step_label>). Run /<other-skill> <ticket> to complete it first."`
- If `state.flow` is absent or null: continue to Step 1 as normal.

---

## Step 1 — Check for existing state

If `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json` already exists, read it and show the phase-aware message. Pick the row by `phase` and `is_spike`:

**Implementation lifecycle (`is_spike == false` or missing):**

| Current phase | Message |
|---|---|
| `understood` | "Understanding already saved. Run /complete-ticket <ticket> to continue to planning." |
| `planned` | "Plan already saved. Run /complete-ticket <ticket> to continue to implementation." |
| `implemented` | "Implementation done. Run /complete-ticket <ticket> to continue to push." |
| `shipped` | "This ticket is already shipped. Run /complete-ticket <ticket> to run /improve-skills." |

**Spike lifecycle (`is_spike == true`):**

| Current phase | Message |
|---|---|
| `understood` | "Understanding already saved. Run /complete-ticket <ticket> to continue to research." |
| `researched` | "Spike proposal saved. Run /complete-ticket <ticket> to help publish it to the tracker." |
| `published` | "Spike already published. Run /complete-ticket <ticket> to run /improve-skills." |

In all cases, also offer: _"Reply 'restart' to re-fetch from the tracker and overwrite the existing state."_

Wait for the user's reply. If "restart" → continue. Otherwise → stop.

---

## Step 2 — Check for saved WIP

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/detect-wip.sh"
```

If a `STATE|<ticket>|...` line is found, show it and ask: _"There is saved WIP for this ticket. Did you mean to run /complete-ticket to resume instead?"_ Wait for reply before continuing.

**Cross-workspace check (read-only — don't restart blind).** Tickets are worked one-per-workspace, but a *different* workspace may already hold WIP or finished work for this ticket. If there is no local `.claude/tickets/<ticket>.json`, scan sibling workspaces before starting from zero:
```bash
for d in "$WORKSPACE_ROOT"/../*/; do [ "$d" = "$WORKSPACE_ROOT/" ] && continue; [ -f "$d.claude/tickets/<ticket>.json" ] && echo "FOUND <ticket> in: $d"; done
```
If found elsewhere, tell the user where, and **suggest they resume in that workspace's session (its state + journal live there) or knowingly start fresh here** — never copy another workspace's state/journal in; each workspace still owns its own ticket work. Found nowhere → proceed fresh. (Sibling journals are worth a read for related-ticket lessons even when the key differs.)

---

> ## ⛏ Acquisition principle — try to read EVERYTHING, degrade gracefully, never silently skip
>
> Steps 3–6 gather context from many sources (tracker fields, comments, attachments, the wiki,
> external mockups, dependencies). Apply the acquisition principle and guided-remediation playbook
> to **every** source, every run — attempt the best method first, fall back in order, never treat an
> unread source as covered, and **guide the user through any auth gate then retry**. The full
> principle + the gated-source → remediation table live in
> **[source-acquisition.md](source-acquisition.md)**.
>
> The honesty discipline under it is **REQUIRED: superpowers:verification-before-completion**; the
> "read the exact failure before recording a gap" rule is **REQUIRED: superpowers:systematic-debugging**.

## Step 3 — Fetch from the tracker (all in parallel)

> **Flow checkpoint** (before fetching): `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> understand-ticket 3 fetching_tracker` — creates the state stub if it doesn't exist yet; never rewrite the document for a flow tick.

The exact MCP calls, field rationale, custom-field `*all` discovery, comment-pagination handling, and
the wiki (3b) / external-mockup (3c) / attachment (3d) retrieval procedures — plus the
"parse tool-result JSON with `node`/PowerShell, never `jq`, and never write into `.claude/**`" rule —
are all in **[tracker-fetch-procedures.md](tracker-fetch-procedures.md)**. Use the exact parameters there;
do not deviate. Apply the acquisition principle (above) to every fetch.

**The non-negotiables to carry from that file:**
- **Fire Call 1 (main ticket) + Call 2 (remote links) + Call 3 (epic, if `parent.key`) in one batch**, with the exact `fields` lists.
- **ACs live in the AC custom field** (`customfield_ac`), not `description` — missing that field means missing every AC. See [[reference-tracker-calls]].
- **Read every comment in full** (author, date, full text) and **every attachment** — decisions and AC refinements are often in the **last few comments**, not the description. Missing one causes wrong implementation.
- **Comment pagination:** if `comment.total > comment.comments.length`, the list was truncated — re-fetch the later comments via the tracker's query language.
- **Custom-field discovery:** do one `fields: ["*all"]` pass per ticket and surface any non-null `customfield_*` not already covered.
- **Wiki pages are readable** — fetch and read each (Step 3b); a linked page is a gap only if the fetch actually failed.
- **Attachments:** attempt the authenticated download (`fetch-attachment.sh` + token, with the one-time `setup-tracker-token.sh` guidance), then **Read the bytes**; ask the user to paste only when every method fails.

---

## Step 4 — Extract every field

Extract and record **all** of the following. Write "none" for absent fields — never leave blank:

| Field | Source |
|---|---|
| Title | `summary` |
| Type | `issuetype.name` |
| Status | `status.name` |
| Assignee | `assignee.displayName` |
| Description | `description` — full text, do not truncate |
| Acceptance Criteria | See extraction procedure below. |
| Labels | `labels` array — every label |
| Epic/Parent | `parent.key` + `parent.fields.summary` (or "none") |
| Fix Version | `fixVersions` |
| Linked issues | from `getIssueRemoteIssueLinks` — type, key, title, status. |
| Wiki pages | Any `/wiki/` link on the ticket, epic, or in remote links — **fetched and read** in Step 3b. Record the page contract (required fields, validation/error codes, mappings). |
| Comments | **Read every comment in full** — author, date, full text. Extract decisions, scope changes, AC refinements, constraints. Never skim. |
| Attachments | **Download and read each** via Step 3d (`fetch-attachment.sh` with the API token → Read the file); for images describe every visible UI element, label, and value. Record `filename · type · author · date`. Only when the download fails (NOAUTH / HTTP) fall back to asking the user (Step 3d → Step 7b.2). |

**Spike detection (run before AC extraction):**

If `issuetype.name == "Spike"`, this ticket follows the spike lifecycle and produces a researched proposal — not code. **Skip the AC extraction procedure below.** Instead, capture a **research question** in 1–2 sentences:

1. If the spike's `description` contains a clear research question / goal, use it verbatim.
2. Otherwise, derive it from the spike `summary` + the parent epic's `description`. Example: spike titled "Research X Implementation" with epic goal "introduce Y" → research question: *"Investigate the best way to implement Y, and propose the implementation tickets to deliver it."*
3. If the spike has no description AND no parent epic to infer from, ask the user for the research question explicitly.

Persist `is_spike: true` and `research_question` in Step 9. Then jump to Step 5 (epic — mandatory for spikes).

**AC extraction procedure — do not skim** (skip when `is_spike == true`):

1. Read the full `description` text without truncating. Locate every section labelled "Acceptance Criteria", "AC", "Done when", "Definition of Done", or similar. **The tracker AC custom field is `customfield_ac`** — check it explicitly in addition to the description.
   - **Defect tickets:** the "Expected Result" section is the AC source. Treat every numbered/bulleted item in it as an AC candidate, including items phrased as questions (e.g. "do we need X?") — check comments before deciding whether to raise them (see rule 5 below).
2. Extract every item that describes a testable outcome — numbered bullets, unnumbered bullets, and inline criteria all count.
3. Treat each **distinct testable condition** as its own AC. If a bullet contains two conditions joined by "and" or separated by a semicolon, split them into separate ACs.
4. After extracting, re-read the raw AC section **one item at a time** and confirm each one is in your list. Count the items in the source and compare to your list count — they must match.
5. Check **every comment** for ACs added or modified post-creation — a later comment may override or extend an AC in the description. The latest comment on the ticket is the authoritative source.
   - **If an item in the description is phrased as a question**, search the comments for an answer before flagging it as ambiguous. If any comment says "Added the AC", "AC added", "added ACs", or similar (even without quoting the item), treat ALL items in the Expected Result / AC section as confirmed — the commenter is confirming the entire list, not adding new items.
   - Only raise a question about a description item if NO comment resolves it.
6. State the final count explicitly: _"Found N ACs (M from description, K added/modified by comments)."_

**If ACs are not found** (and not a spike): stop. Ask: _"I could not find Acceptance Criteria in this ticket. Please paste them here before I continue."_

---

## Step 5 — Extract from epic/parent

**If no parent/epic exists: skip this step entirely** (but for Spikes with no description, this means stopping and asking the user for the research question — a Spike needs *something* to research).

Otherwise, read the epic in full — **every field, every comment, every attachment**. **For Spikes, this step is mandatory** — the epic is usually the actual spec for what the spike must investigate:
- Full description — do not truncate
- **Every comment**, regardless of apparent relevance — author, date, full text. Epic comments often contain cross-ticket decisions, scope constraints, or design choices that apply to all child tickets including this one.
- **Every attachment** — same rules as the main ticket (describe images fully, note document contents)
- Any ACs or requirements at epic level that apply to all child tickets

Do not filter epic comments by "relevance" before reading them — you cannot know what is relevant until you have read it.

---

## Step 6 — Resolve dependencies

> **Build the dependency set from MORE than `issuelinks` — that field is often empty.** A ticket's
> real dependencies are frequently named only in prose, not as formal links (this is common for
> cross-team API contracts). Before resolving, assemble the candidate set from **all** of:
> 1. **`issuelinks`** on the main ticket (formal links).
> 2. **`subtasks`** on the main ticket (child issues — read each like a dependency).
> 3. **Issue keys mentioned in the main ticket `description` and comments** — scan for `PROJ-\d+`
>    and other `[A-Z]+-\d+` keys (e.g. an "API Contract" table that lists the endpoints'
>    tickets). These are dependencies even though they aren't in `issuelinks`.
> 4. **The epic's ticket-breakdown** — epics often carry a "Ticket Breakdown / Order & Dependencies"
>    comment or table that states exactly what this ticket consumes; treat those as dependencies too.
> Dedupe the keys, then run the resolution below on each. For each, note **where it was discovered**
> (link vs. description vs. epic) so a reviewer can see nothing was inferred silently.

For each linked issue (and each key discovered above):

**If blocker status is not Done/Closed:**
```
🚫 Blocked: <key> (<title>) is a dependency and is still <status>.
This ticket cannot be implemented until that dependency is resolved.
```
Stop. Wait for user to decide.

> **Hard blocker vs. in-flight producer — don't over-stop.** The stop above is for a *functional
> blocker* (this ticket genuinely cannot work until the dep ships). A dependency that is merely an
> **in-flight producer** — it provides a contract/code you *consume* but you can build against it now
> (typical for cross-team API stories in Code Review / QA / "final adjustments") — is **not** an
> automatic stop. Read its branch code per Step 6b and surface it in Step 6c for the user to confirm
> building against, rather than halting the ticket.

**If Done/Closed** — fetch with exact parameters:
```
mcp__tracker__getIssue
  cloudId:               "<your-tracker-cloud-id>"
  issueIdOrKey:          "<dep-key>"
  responseContentFormat: "markdown"
  fields:                ["summary", "description", "comment", "attachment",
                          "issuelinks", "status", "labels"]
```
Then:
- Read its **full description** — do not truncate
- Read **every comment** — implementation decisions are often recorded there, not in the description
- Read **every attachment** — may contain schemas, wireframes, or specs for what was built
- Apply the same comment pagination check as Step 3
- Search the codebase for related code using the ticket key and domain terms
- Record: what was implemented, which files, what contracts or interfaces were introduced

For each dependency, explicitly note: "Read N comments on <key>." If a dependency has no comments, note that too. Missing dependency context is a leading cause of wrong integration assumptions.

> **Fetch before reasoning about current code or merge status — the clone is NOT synced yet.**
> understand-ticket runs *before* plan-ticket's `sync-repos`, so the local repos may be stale.
> Whenever understanding requires reading a repo's **current code** or judging **git/merge state**
> — a defect/escalation on already-shipped code, a "see the related MR" investigation, or "is this
> fix already merged?" — run `git -C "$WORKSPACE_ROOT/<repo>" fetch origin -q` **first**, then reason
> against `origin/<branch>`. To decide whether work is merged, use `git -C <repo> log --grep
> <TICKET> origin/<base>` or content (`git grep "<changed string>" origin/<base>`) — **never**
> `git merge-base --is-ancestor <branch> <base>`, which false-negatives on squash/rebase merges
> (the merge lands a new SHA, so the original branch tip is never an ancestor even when merged).

### Step 6b — Verify consumed contracts against the producer's real code (not just the tracker)

Tracker/wiki descriptions **lag the code**, and a producer ticket that is still *in-flight*
(In Progress / "final adjustments" / in QA / Code Review) frequently changes the very contract this
ticket binds to *after* its description was written. For **every contract this ticket consumes**
(HTTP endpoint, request/response DTO, message/event, enum, status codes), do not trust the
documented shape — **read the producer's actual code** and record what it really is.

1. **Identify the producer of each consumed contract.** Beyond the formal/`issuelinks` deps, sweep
   the **epic's children** for *producer-side* siblings (API / mapper / model / "data collection" /
   "endpoint" stories) that shape what you consume — they are dependencies even when nothing links
   them. List epic children with a **minimal-field** query (`fields:
   ["summary","status","issuetype","assignee"]`, **no `description`**) — results are still verbose,
   so parse the saved tool-result file with `node` (per the parsing note above), never inline.
2. **Read the producer's real code**, in the **producer repo** (often the `api` repo — *not* the repo
   this ticket changes):
   - Merged producer → read the files on the current branch.
   - **In-flight producer (unmerged branch)** → read it without checking out:
     `git -C "$WORKSPACE_ROOT/<producer-repo>" fetch origin -q` then
     `git -C "$WORKSPACE_ROOT/<producer-repo>" show origin/<producer-branch>:<path/to/controller-or-model>`
     (the branch is usually named in the producer's ticket, an MR link, or an epic comment).
   - Capture the **verified** contract: exact field names + **casing** (PascalCase vs camelCase),
     required vs optional params, enum **names and how they serialize** (int vs string), and which
     fields are nested objects vs scalars.
3. **Record the verified contract** in that dependency's `summary`, and **flag any divergence from
   the ticket/wiki description** — the code wins; note it so plan-ticket binds to the real
   shape (this is exactly the gap that ships contract bugs).
4. **"Build against the documented contract" is a fallback only** — use it *after* confirming the
   producer's code genuinely can't be read (no branch access, repo absent), and say so explicitly
   rather than silently trusting the description.

> **Coverage & gaps (Step 6b):** every consumed contract is either *verified against producer code*
> or *explicitly marked "documented-only, code unread — <why>"*. Never leave a consumed contract
> silently assumed from the description.

### Step 6c — Surface related work that already has implementation, and ask

Reading the *full* implementation of every related ticket is wasteful — but the user must be **told**
which related items already carry real code, so they can decide whether any deserves a deeper look
beyond the consumed-contract verification in Step 6b. After resolving dependencies, classify the
related set — **the epic, epic children/siblings, dependencies, subtasks, and linked issues** — and
flag each that has **actual implementation**:

- **Shipped code** — Done / Closed / Dev Complete with a merged MR, or
- **In-flight code** — an open MR or a feature branch with commits (In Progress / Code Review / QA /
  "final adjustments").

Present them at the understanding gate as an explicit, can't-miss prompt. **This warning is mandatory —
show it every run**: even when every related item was already analyzed (mark them `[analyzed]`), and
even when there is none (state `No related work with implementation found.`). Mark **each** item
`[analyzed]` (its code was read this run — e.g. a consumed contract from Step 6b) or `[NOT analyzed]`
(it has shipped/in-flight implementation but was not read), so the not-analyzed ones are impossible to
miss:

```
⚠ Related work with real implementation — confirm relevance before planning:
  - <KEY> (<title>) — <status> — <code: merged / branch <name>> — [analyzed | NOT analyzed] — <why it may matter to us>
  - ...
Step 6b already read the code behind the contracts THIS ticket consumes (marked [analyzed]). The
[NOT analyzed] items above have implementation done but were not read — do you want me to read any
before I finalize the understanding?
Reply with which keys (or "just the consumed contracts" / "all" / "none").
```

**Do not present the Step 8 understanding summary/gate until this warning has been shown and the user
has chosen for the `[NOT analyzed]` items.**

Read whatever the user selects, fold it into the understanding, and record the choice in the journal
(`DECISION: read <keys> / skipped <keys> — <why>`). This keeps coverage a **conscious** decision, never
a silent omission. (Finding this set reuses the epic-children sweep from Step 6b step 1 — minimal-field
query, parsed from the saved file with `node`.)

> **When the user asks to read 2+ `[NOT analyzed]` tickets, fan them out — REQUIRED: superpowers:dispatching-parallel-agents.**
> Each is an independent read (a different ticket's code/comments, no shared state), so dispatch one
> focused agent per ticket in a single message — give each its key, its repo/branch, and "return what
> was implemented, which files, and any contract this ticket consumes" — then fold the returned
> summaries in. A single selected ticket you can read inline. Verify each agent's summary against the
> real source before trusting it (the verification-before-completion rule applies to agent reports too).

### Step 6d — Capture the test scope (environment · login identity · data)

Verification later needs to know *where* to run, *as whom*, and *with what data*. Capture it now from
what you've read — and where a value is genuinely unknown, **ask; never assume one.** This is the
brainstorming "no unexamined assumption" rule applied to test data.

- **Environment** — the target environment whose data the scenarios use. Look for a candidate in this order: the
  **ticket**, its **dependencies**, the **epic**, and the **epic's related/child tickets** (their QA
  comments often name the exact environment + record used to test a sibling — a known-good source). **If you
  find one, use it.** **If none is found, ASK the user** which environment to use, **suggesting
  the default dev environment** — never silently assume it. This is the test-data
  "ask, never assume" rule applied to the environment.
- **Login identity** — the login is always the **developer's own management credentials** (stored once in
  the gitignored `e2e/.env` and reused for every ticket — not something you capture per ticket here).
  What varies per ticket is **who you impersonate**: default to the **standard privileged user** unless the ticket scope
  calls for a specific role/user (e.g. an approver, a restricted user). Record the impersonation
  target — never a password.
- **Test data** — note any concrete data the ticket/related tickets reference (a record, child record, account,
  record id) that a scenario should reproduce. If none is found, record that the data must be
  **discovered at test time by querying the chosen environment** (the specs discover at runtime — see
  implement-ticket Step 8.6). When the data needed to prove an AC is unclear, raise it as a clarity
  question (Step 7) — **do not invent a record or value.**

Record this as `test_scope` in the state file (Step 9).

---

## Step 7 — Clarity check

Before presenting the summary, surface ambiguities that would block or derail implementation — and
**resolve them before planning, not after**. This is the instance of
**REQUIRED: superpowers:brainstorming**: explore intent/requirements/design with the user, ask
clarifying questions, never proceed on an unexamined assumption.

Check **every** ambiguity class (scope/goal, ACs, dependency alignment, technical clarity — including
the prose-vs-AC scope mismatch, AC-ownership, and mockup-vs-verified-contract discrepancies — and
test-data/test-scope: the environment, impersonation target, or concrete data needed to verify an AC when
it is not derivable from what you read), then
categorise each finding **🔴 Blocker / 🟡 Assumption / 🟢 Minor**, and — if there are any 🔴 or
multiple 🟡 — compile the questions into one message and **wait for answers** before Step 8. The full
catalog, the categorisation, and the question template are in
**[clarity-check-catalog.md](clarity-check-catalog.md)**. If everything is clear (no blockers, no
significant assumptions), proceed directly to Step 8 without asking.

> **Journal:** As each question is raised, record it; as each is answered, record the resolution. These answers are the first thing lost on compaction and the most expensive to reconstruct.
> ```bash
> bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> QUESTION "<the open question, one line>"
> bash "$WORKSPACE_ROOT/.claude/scripts/append-journal.sh" <ticket> RESOLVED "<question> → <the user's answer>"
> ```

---

## Step 7b — Reading audit + unverified-content warning (mandatory before summary)

Before showing the summary, do **two** things — first a positive accounting of what was read, then an explicit warning about anything that could not be read or verified. See [[warn-on-unverified]]. This is the instance of **REQUIRED: superpowers:verification-before-completion**: a source is "read/verified" only with evidence; gaps are surfaced, never hidden by silence.

Produce all three sub-sections following **[coverage-and-gaps.md](coverage-and-gaps.md)**:

- **7b.0 — Full source-coverage map** — one row per discrete source (tracker fields + ACs, the `*all` discovery, each comment count, **each** attachment, inline images, worklogs, **each** wiki page, **each** mockup, epic fields/comments/attachments, **each** dependency's desc + comments, and anything deliberately skipped), each marked **READ ✓ / PARTIAL ◐ / NOT READ ✗** with method and (if not read) the why + fallback. Close with the `Coverage: X READ ✓ · Y PARTIAL ◐ · Z NOT READ ✗.` tally.
- **7b.1 — What was read** — the per-source reading audit (comments + attachments read per ticket/epic/dependency). If any source returned zero comments and you did **not** see an empty list in the response, re-fetch — the data may be truncated.
- **7b.2 — What could NOT be verified** — the gap list, shown **even when empty** (state `All ticket content read and verified.` if so). The catalog covers the per-source gap rules: still-unread attachments (with exact failure + browse URL + fallback), missing ACs, comment pagination, unfetchable links, failed wiki fetches, unrenderable mockups, and expected-but-null custom fields.

**Do not proceed to Step 8 until both 7b.1 and 7b.2 are shown to the user.**

---

## Step 8 — Show summary and wait for confirmation

> **Flow checkpoint** (before showing summary): `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> understand-ticket 8 awaiting_confirmation`


**Implementation tickets** (Story / Defect / Task / …):

```
Ticket: PROJ-XXX — <title>
Type:   <type>
Status: <status>
Labels: <all labels>

Goal:
<2-3 sentences>

Acceptance Criteria:
1. <full text>
2. <full text>
...

Epic: <key> — <title>  (or "none")
  Constraints: <any constraints from epic description/comments>
Fix Version: <version>
Attachments: <list with descriptions>
Comments: <all relevant decisions and scope notes>

Dependencies:
  - <key> (<title>) — <status> — <what was built and how it affects this ticket>

Test scope:
  Environment: <environment | default dev environment>
  Impersonate: <standard privileged user (default) | specific user/role>   (login = your management creds, stored in gitignored e2e/.env, reused every ticket)
  Test data:   <concrete records/ids named | "discover at test time by querying the environment">

Proposed repos: <list — see criteria below>
```

**Spike tickets** (use this format when `is_spike == true`):

```
Ticket: PROJ-XXX — <title>
Type:   Spike
Status: <status>
Labels: <all labels>

Research question:
<the question this spike must answer, captured in Step 4>

Parent epic: <key> — <title>
  Goal (from epic):
  <epic description / goal>
  Constraints / context:
  <anything from epic comments / attachments that bounds the research>

Attachments: <list with descriptions — including any from the epic>
Comments on the spike: <usually just an effort placeholder; flag anything more>

Deliverable:
  A researched proposal posted to this ticket + draft child stories under the epic.
  No code, no MR.
```

**How to determine proposed repos:** reason from the ACs, labels, and dependencies:
- Any AC involving UI or browser behaviour → `web`
- Any AC involving business logic, data, or APIs → `api`
- Any AC involving schema changes or new columns → the database repo
- `db_script_required` label → the database repo
- `Breaking_Changes` label → check which repos consume the changed contract
- Done dependencies that live in a specific repo → include that repo
- When in doubt about a repo, include it with a "?" note and confirm at plan time

### 🛑 GATE — FULL STOP

**DO NOT write the state file until the user gives explicit confirmation.**

Ask: _"Does this match your understanding? Reply 'yes' (or 'looks good', 'confirmed', 'correct') to save and continue. If anything is wrong, tell me and I will fix it and ask again."_

**What counts as confirmation:** "yes", "looks good", "confirmed", "correct", "go ahead", or any clear equivalent.

**What does NOT count as confirmation:**
- A question ("did you get all the ACs?", "what about X?")
- A correction ("AC 3 is wrong")
- Silence or no reply

**If the user raises a question or correction:**
1. Answer it or fix the summary in-place — do NOT re-invoke `understand-ticket` as a new skill call
2. Re-present the updated summary in full
3. Ask for confirmation again

Repeat until explicit confirmation is received. Only then proceed to Step 9.

---

## Step 9 — Write state file

After confirmation, write `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. Set `flow` to `null` — this skill is complete.

```json
{
  "ticket": "PROJ-XXX",
  "phase": "understood",
  "issuetype": "<Story | Defect | Task | Spike | ...>",
  "is_spike": false,
  "research_question": null,
  "title": "<title>",
  "type": "<type>",
  "goal": "<goal>",
  "acs": ["<AC 1 full text>", "<AC 2 full text>"],
  "labels": ["<label>"],
  "epic": {
    "key": "<key or null>",
    "title": "<title or null>",
    "constraints": "<constraints from epic or null>"
  },
  "fix_version": "<version>",
  "dependencies": [
    {
      "key": "<key>",
      "title": "<title>",
      "status": "<status>",
      "summary": "<what was built and how it affects this ticket>"
    }
  ],
  "comments": "<all relevant decisions and scope notes>",
  "attachments": "<attachment descriptions>",
  "proposed_repos": ["api", "web"],
  "test_scope": {
    "environment": "<target environment>",
    "impersonate": "standard privileged user",
    "data_notes": "<concrete records/ids, or 'discover at test time by querying the environment'>"
  },
  "saved_at": "auto"
}
```

**For Spikes**, set `issuetype: "Spike"`, `is_spike: true`, `research_question: "<captured in Step 4>"`, `acs: []`. `proposed_repos` and `test_scope` may be omitted (a spike produces a researched proposal, not verified code) — `spike-ticket` will determine the final repo set during exploration.

Writing the state file above **is** the title update — nothing to run. The `title-hook` reads
`title` from `<ticket>.json`, so the session title becomes `<ticket> — <title>` on your next
message (and on every `claude -r` resume), and stays locked there. See `title-hook.mjs`.

Then tell the user:

```
✓ Understanding saved for PROJ-XXX.

Next step: run /plan-ticket PROJ-XXX
```
