---
description: Research spike — explore the codebase to produce a researched proposal, then (only after explicit approval) help publish it to the tracker. Replaces plan-ticket / implement-ticket / push-ticket for Spike issuetypes. Usage: /spike-ticket PROJ-XXX
arguments:
  - name: ticket
    description: Ticket ID (e.g. PROJ-123) or full tracker URL
    required: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - tracker__getIssue
  - tracker__getIssueRemoteIssueLinks
  - tracker__searchIssuesUsingJql
  - tracker__createIssue
  - tracker__addCommentToIssue
  - tracker__editIssue
  - tracker__createIssueLink
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`). All paths below resolve from this root.

Replacement for `plan-ticket` → `implement-ticket` → `push-ticket` when the ticket's issuetype is **Spike**. A spike's deliverable is a researched proposal + draft child tickets — not code, not an MR.

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

> **Journal in the moment.** Append a dense one-line entry via `append-journal.sh` the instant a real decision (with *why*), a dead-end, a clarifying answer, or a constraint occurs. Spikes journal heavily — every "already mapped point" is a decision worth recording. See the journal note in `complete-ticket`.

## Required disciplines (Superpowers substrate)

This skill is the **domain** layer for a spike — the state contract, the cross-repo exploration
mechanics, the proposal template, and the tracker no-auto-publish safety contract. The generic discipline
for *how to research and shape a proposal* is delegated to Superpowers skills; do not re-derive it here.
Load and follow each at the point marked below:

- **REQUIRED: superpowers:brainstorming** — a spike's deliverable *is* a design: explore the problem
  and intent before recommending, propose more than one approach and name the one rejected, and get
  the user's approval before it's treated as the answer (Steps 3–5). This is what the
  "Recommended approach + one alternative" requirement and the Step 5 approval gate are an instance of.
  (Skip its code-implementation tail — a spike ends at the proposal, not at `writing-plans`.)
- **REQUIRED: superpowers:systematic-debugging** — when the spike is investigating a defect, a
  regression, or an "is X actually happening?" unknown (Step 3): find the root cause through evidence,
  don't theorize from class/file names. Read the implicated code end-to-end before concluding.
- **REQUIRED: superpowers:verification-before-completion** — evidence before any load-bearing claim in
  the proposal (Steps 3–4): every "X already does Y", "Z is the precedent", "this is the only read
  path" must cite a file read in this session, and anything you could **not** verify is listed in the
  `⚠ Unverified content` section, never glossed over.

Product-specific guardrails these do **not** cover stay inline at their steps: the no-auto-publish
per-item approval contract, the state/phase machine, the cross-repo sync-before-explore rule, the
Grep/Glob/Read-not-raw-shell rule (and its subagent variant), and the attachment-fetch protocol.

---

## 🛑 Hard rule — no external writes without explicit per-item approval

This rule overrides everything else in this skill:

- Phase B (Publish) **never** calls a tracker write tool (`createIssue`, `addCommentToIssue`, `editIssue`, `createIssueLink`, …) without an explicit "yes" from the user for that **specific item**.
- Always show the **full content** that would be written, and the **exact MCP call** with all parameters, **before** asking.
- A general "go ahead" or "ok" approves only the most recently shown item — never the rest. Each item needs its own yes.
- Default offering is "paste it yourself"; auto-create via MCP is an opt-in alternative, not the default.

See [[no-auto-publish]] in memory.

---

## Step 0 — Flow resume check

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`. Check `state.flow`:

- If `state.flow.active_skill == "spike-ticket"`: first read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.journal.md` if it exists (restores decisions/dead-ends/open questions — honor every `DEADEND`, surface unresolved `QUESTION`s). Then print `"↩ Resuming spike-ticket from: <step_label>"` and jump directly to that step.
- If `state.flow.active_skill` is a different skill: stop — `"⚠ <ticket> shows <other-skill> was mid-execution (step: <step_label>). Run /<other-skill> <ticket> to complete it first."`
- If `state.flow` is absent or null: continue to Step 1.

---

## Step 1 — Load state and validate

Read `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`.

If the file does not exist → stop: _"No understanding found for <ticket>. Run /understand-ticket <ticket> first."_

If `state.is_spike != true` → stop: _"<ticket> is not a Spike (issuetype='<state.issuetype>'). Use /plan-ticket instead."_

Branch by current `phase`:

| `phase` | What this skill does next |
|---|---|
| `understood` | Run **Phase A — Research** (Steps 2–6) |
| `researched` | Skip to **Phase B — Publish** (Steps 7–9) |
| `published` | Stop: _"Spike already published. Run /improve-skills to reflect."_ |
| anything else | Stop: _"Unexpected phase '<phase>' for a Spike. Inspect the state file."_ |

Load into context: title, parent epic key + constraints, attachments summary, comments summary, and the `research_question` saved by understand-ticket. If `research_question` is missing or empty (older state file), ask the user for one before continuing.

---

# Phase A — Research

## Step 2 — Sync repos

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> spike-ticket 2 syncing_repos`

Run:
```bash
bash "$WORKSPACE_ROOT/.claude/scripts/sync-repos.sh"   # no --repos — sync ALL repos
```

Spike research is cross-repo by nature — sync everything so every precedent and contract is read from the latest code (a stale side repo yields a stale recommendation). Parse results. If any repo fails to sync, list the failures and ask whether to continue without them.

---

## Step 3 — Explore the codebase

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> spike-ticket 3 exploring`

Use the parent epic + research question to guide exploration. Read each touched repo's `CLAUDE.md` first.

> **Explore with the Grep / Glob / Read tools and parallel `Agent` (Explore) — not raw shell (Bash *or* PowerShell).** Avoid `cd … && grep/find/cat/ls` *and* `Get-ChildItem -Recurse | … | ForEach-Object {…}` pipelines; raw-shell exploration triggers an approval prompt every call (PowerShell script blocks are flagged "arbitrary code"; multi-cmdlet pipelines aren't allow-listed) and is slower / token-heavy. Reserve shell for `sync-repos.sh` and the like.
>
> **When you dispatch Explore agents, instruct each one in its prompt to use Glob/Grep/Read only and never raw Bash/PowerShell for file/dir discovery** — subagents do not inherit this rule and will otherwise default to `Get-ChildItem -Recurse`, which prompts and wastes tokens.

**Spike-specific exploration rules** (these are different from plan-ticket):

1. **Verify before recommend** — the instance of **REQUIRED: superpowers:verification-before-completion**. Every load-bearing claim ("X already does Y", "Z is the precedent", "the api handles this") must be confirmed by reading the actual file end-to-end. Class/file-name resemblance is **not evidence** — it is exactly how this kind of spike gets pulled in the wrong direction. If the spike is chasing a defect or an "is this actually happening?" unknown, root-cause it from evidence — **REQUIRED: superpowers:systematic-debugging** — rather than theorizing from names.
2. **Trace read paths AND write paths.** Many features touch both. Confirm each surface (chart, views, exports, admin UI, …) separately rather than assuming one read path covers all.
3. **Resist over-fitting to a familiar precedent.** If you cite "X is what some existing integration does", open that code and confirm what it actually does. Don't infer from naming.
4. **Surface UI route names** by reading the sitemap / routes file (e.g. `Mvc.sitemap`, React route tables) — not by inferring from controller / repository names. Class names lie.
5. **Acronyms in the epic that are not in code** are product terms — ask the user before assuming what they map to.
6. **Attachments matter — fetch them, don't skip them.** Epic/ticket screenshots are auth-gated but **readable**: download each with `bash "$WORKSPACE_ROOT/.claude/scripts/fetch-attachment.sh" <attachmentId> <out>` (tracker API token; run `setup-tracker-token.sh` once via `!` if it reports `NOAUTH`), then **Read** the file. Only if the download still fails (HTTP/permission) ask the user to paste/share. Never draw conclusions from an unread image.
7. **Warn explicitly on any unverified content** — the honest-gap half of **REQUIRED: superpowers:verification-before-completion**. Before showing the proposal in Step 4, surface a `⚠ Unverified content` section listing anything you could not fetch / read / verify — attachments, truncated comments, linked items not opened, wiki pages referenced but unread. If there are no gaps, say so explicitly — list each unreadable source with the exact reason and how to unblock it.

**Journal as you go.** Every decision with its *why*; every dead-end with cause + replacement.

Use parallel `Agent` (Explore subagent) calls when breadth helps — but only after `sync-repos`. Cap each agent's prompt to a single concern (one read path, one config layer, one entity family) and require concrete file paths in the result.

---

## Step 4 — Draft the structured proposal

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> spike-ticket 4 drafting_proposal`

The proposal is the spike's deliverable — it *is* a design, so shape it under **REQUIRED:
superpowers:brainstorming**: lead with the recommendation, name a real alternative considered (not a
strawman) and why it lost, and apply YAGNI. Use this template — keep section order:

```
## Spike: <ticket title>

### Goal
<one paragraph: the research question + parent-epic outcome>

### Current state (verified in code)
- <fact 1 — with concrete file path / class / method>
- <fact 2 — with concrete file path / class / method>
- …

### Recommended approach
<2–3 paragraphs. Lead with the recommendation. Explicitly name one alternative considered and why it was rejected (this is the spike's actual product — without the alternative, the team can't audit the choice).>

### Resolved design decisions
- <decision> — <one-line reason>
- …

### Proposed implementation tickets
1. **<Title>** — <one-sentence scope>. Repos: <list>. Estimate: <small/medium/large or days>.
2. …

### Coverage map (epic → tickets)
| Epic phrase | Covered by |
|---|---|
| <quoted phrase from epic> | <ticket # or "out of scope (reason)"> |

### Open product questions
- <question> — *needs decision before <ticket #> can start*
- …

### Risks
- <risk> — <mitigation or "accepted">
- …
```

**Quality bar before showing the proposal to the user:**

- Every "Current state" bullet cites a concrete file path. No hand-wavy claims.
- Every "Proposed ticket" maps to at least one epic phrase in the Coverage map.
- Every epic phrase is either covered or explicitly listed as out of scope with a reason.
- The "Recommended approach" names a real alternative, not a strawman.
- Estimates are honest ranges, not single points pretending to be precise.

---

## Step 5 — Gate: proposal approval

This is the design-approval gate of **REQUIRED: superpowers:brainstorming** — the proposal is not the
answer until the user approves it. Present the full proposal as written above. Then ask:

> _"Does this proposal match what you want to take to the team? Reply 'yes' (or 'approved' / 'looks good') to save it. If anything is wrong or missing, tell me and I'll revise."_

**What counts as approval:** explicit yes / approved / looks good / go ahead.
**What does not:** a question, a correction, silence.

If the user requests changes:
1. Revise in place — do **not** re-invoke this skill.
2. Re-present the full proposal.
3. Ask again.

Repeat until explicit approval is received.

---

## Step 6 — Save researched state

After approval, update `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`:

```json
{
  "phase": "researched",
  "flow": null,
  "spike_proposal": "<the full proposal text>",
  "proposed_repos": ["<repos confirmed during research>"],
  "saved_at": "auto"
}
```

(Preserve all existing fields.)

Then tell the user:

```
✓ Spike research saved for <ticket>.

Next step: run /complete-ticket <ticket> — it will ask whether to help publish
the proposal to the tracker (Phase B). Or stop here if you only wanted the research output.
```

Stop here when invoked standalone. `/complete-ticket` re-invokes this skill for Phase B when `phase == "researched"`.

---

# Phase B — Publish

Entered when this skill is re-invoked and `state.phase == "researched"`.

## Step 7 — Show the planned outputs

> **Flow checkpoint:** `bash "$WORKSPACE_ROOT/.claude/scripts/set-flow.sh" <ticket> spike-ticket 7 showing_outputs`

Reconstruct from `state.spike_proposal`:

1. **The tracker comment** that would go on this spike ticket — paste-ready, in the same structured shape as the proposal but without internal-only headings ("Goal", "Recommended approach", "Resolved design decisions", "Coverage map", "Open product questions", "Risks", and a numbered list pointing at the child tickets).
2. **Each child story draft** — one block per ticket, with: title, type (Story / Defect / etc.), parent (the epic from `state.epic.key`), description (user story + scope), acceptance criteria (numbered list), implementation overview (high level, with file/method paths where the spike found them), and the suggested estimate.

Present everything in a single message so the user can read and copy in one pass.

---

## Step 8 — Decide publish mode

Ask:

> _"How do you want to publish these?_
> _**(a)** I'll paste them into the tracker myself — recommended._
> _**(b)** Create them via the tracker's MCP, item by item — I'll show you each call and wait for your yes before any write."_

If the user picks **(a)** → skip to Step 9 directly. **Do not call any tracker write tool.**

If the user picks **(b)** → run the per-item approval loop below. Treat the loop as the heart of this skill's safety contract.

### Per-item approval loop (mode b only)

For each item to publish (the comment, then each child story, in order):

1. Show the **full content** for this single item again (already shown in Step 7, repeat for clarity).
2. Show the **exact MCP call** with all parameters, formatted like:
   ```
   Call: tracker__createIssue
     instance:      "your-instance"
     projectKey:    "PROJ"
     issuetype:     "Story"
     summary:       "<title>"
     parent:        "<epic key>"
     description:   <body>
     acceptanceCriteria: <structured body>
     labels:        [<if any>]
   ```
3. Ask: _"Create this one now? (yes / no / skip / stop)"_
4. Honor the answer:
   - **yes** → call the MCP tool. Show the resulting ticket key + URL. Continue to the next item.
   - **no** → revise this item per the user's feedback, then re-ask. Do not move on.
   - **skip** → don't create this one; mark it as skipped in the publish log; continue.
   - **stop** → end the publish loop immediately. Save state to mark which items were published and which were not.
5. Repeat.

**Never batch.** Even if the user says "go ahead" generically, treat it as approving only the item currently shown. Re-ask for the next.

**If any MCP call fails** → show the error verbatim, mark the item as failed in the publish log, ask whether to retry, skip, or stop.

---

## Step 9 — Save published state

After the publish loop ends (or after the user confirms they've pasted manually), update `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json`:

```json
{
  "phase": "published",
  "flow": null,
  "publish": {
    "mode": "manual" | "mcp",
    "comment_published": true | false,
    "child_tickets": [
      { "title": "<title>", "key": "<PROJ-XXX>" | null, "status": "created" | "skipped" | "failed" | "manual", "url": "<url>" | null }
    ],
    "published_at": "<ISO timestamp>"
  }
}
```

Then tell the user:

```
✓ Spike published.

Summary:
  Comment:        <created / pasted manually / skipped>
  Child tickets:  <list with keys, or "drafts handed off for manual creation">

Next step: run /complete-ticket <ticket> — it will offer /improve-skills to reflect on this spike.
```

---

## Notes for `/complete-ticket` routing

This skill is invoked twice over the spike's lifecycle:

1. Once when `phase == "understood"` → runs Phase A, ends at `phase == "researched"`.
2. Once when `phase == "researched"` → runs Phase B, ends at `phase == "published"`.

After `published`, `/complete-ticket` should offer `/improve-skills`, not re-invoke this skill.
