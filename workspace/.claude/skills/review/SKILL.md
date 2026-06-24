---
description: Review MR(s) for a ticket against its tracker ACs. Usage: /review <MR URL | PROJ-XXX>
arguments:
  - name: target
    description: Either a full MR URL (review that one MR) OR a tracker ticket id like PROJ-123 (discover and review every open MR for the ticket across repos)
    required: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - WebFetch
---

> **$WORKSPACE_ROOT** = parent of `.claude/` = current workspace root (e.g. `C:/source/ws1`, `C:/source/ws2`).

Review MR(s) against the ticket's tracker ACs. Accepts **either** a single MR URL **or** a ticket id (`PROJ-XXX`); in ticket mode it discovers and reviews **every open MR for the ticket across repos**. For each MR it fetches data via the Git host connector (MCP) with REST+token fallback; it gathers the ticket's business/product context by reusing **understand-ticket**'s acquisition logic (so the rich context — ACs, epic, dependencies, wiki, mockups, attachments — lives in one skill, not duplicated here), verifies AC coverage, and always writes a review entry per MR to the ticket JSON (creating it if needed).

> **Reviewer role — read only, never drive the lifecycle.** `/review` is the *reviewer's* entry point, usually run against **someone else's** ticket, so a local `<ticket>.json` plan usually does **not** exist — that is normal, never a blocker. Do **not** fold review into `complete-ticket`, do **not** drive the ticket through lifecycle phases, and do **not** write a `phase`/`flow` state for a ticket you are only reviewing (the only write is the `reviews[]` entry in Step 6).

## Required disciplines (Superpowers substrate)

This skill is the **domain** layer of code review — it maps an MR set against a ticket's
tracker ACs. The generic review discipline is delegated to Superpowers skills; do not re-derive it here.
Load and follow each at the point marked below:

- **REQUIRED: superpowers:requesting-code-review** — the generic rigor of a review: severity triage (Critical/blocker vs Important vs Minor), no "skip because it's simple", a concrete fix per finding, and checking against the requirements rather than just the diff. Apply it as you produce the findings in Step 5; the domain layer on top is *which* requirements (the tracker ACs, cross-MR coverage) and *which* conventions (Step 5c) the review checks.
- **REQUIRED: superpowers:receiving-code-review** — when Step 5b reconciles against **prior reviewers' comments**: evaluate each technically, never echo or duplicate it performatively, and push back with reasoning where a prior comment is wrong for this codebase rather than parroting it. The reviewer here is also a *receiver* of the existing comment thread.
- **REQUIRED: superpowers:verification-before-completion** — evidence before any "AC covered" / "approve" verdict. A coverage mark or an approval is backed by the specific diff hunk (file + line) that satisfies it, not by the MR title or the author's description; if a diff couldn't be read, the AC is unverified, never silently "covered" (see the Coverage & gaps rule above).

Domain-specific mechanics these do **not** cover stay inline at their steps: the MR-vs-AC mapping and cross-MR coverage logic, the connector-first/token-second diff-fetch mechanics, the reviewer-role (read-only, no lifecycle-drive) rule, the known-non-findings (the shared-submodule convention), the conventions checklist, and the `reviews[]` JSON write.

---

> **Coverage & gaps.** This reads the MR (metadata, **diffs**, **review notes**) per MR, plus the ticket context gathered in Step 4 — any can fail (token missing, MR 404/403, a truncated/huge diff, a notes-count mismatch). Attempt each; on failure state EXACTLY what couldn't be read and the fix (set the Git host token, confirm MR access, fetch diffs per file or page a large diff) — never review a partial diff silently. The ticket-context acquisition in Step 4 carries **understand-ticket's own** Coverage & gaps rules; apply them there rather than restating them.

---

## Step 0 — Standards freshness check

Run once at entry (review is never invoked mid-lifecycle, so refreshing here is safe):

```bash
bash "$WORKSPACE_ROOT/.claude/scripts/update-standards.sh"
```
If it reports `BEHIND|<n>|<branch>`, offer to pull (`update-standards.sh --pull`) so you review with the latest skills, then continue. `UPTODATE` / `DIRTY` / `NOMARKER` → continue.

---

## Step 1 — Parse input and determine mode

`$target` is **either** an MR URL **or** a ticket id. Detect which:

- **MR mode** — `$target` matches `/-/merge_requests/<n>` → review that one MR. Parse:
  - `PROJECT_PATH` = path between the host and `/-/merge_requests` (e.g. `org/repo-a`)
  - `MR_IID` = number after `/merge_requests/`
  - `PROJECT_ENCODED` = `PROJECT_PATH` with `/` → `%2F`
  - `TICKET` = extract from the MR's `source_branch` in Step 2a. Pattern `/(PROJ-\d+)/i`.
  - The **MR set** is just this one MR.
- **Ticket mode** — `$target` matches `/^PROJ-\d+$/i` (or a tracker browse URL) → `TICKET` is that id; discover the MR set in Step 1b.

The rest of the skill runs **per MR** in the set for Steps 2–3 and 5–6; Step 4 (ticket context) runs **once** for the ticket.

---

## Step 1b — Discover the ticket's MRs (ticket mode only)

Skip in MR mode. In ticket mode, find every **open** MR for `TICKET` across repos:

1. **Git host MR search (primary — this is the reliable one).** Search opened MRs carrying the ticket id in branch/title:
   ```
   <Git host MCP search>
     scope:  merge_requests
     search: <TICKET>            # e.g. PROJ-247
     state:  opened
   ```
   Keep results whose `source_branch` **or** `title` contains the id with a word boundary (`/\b<TICKET>\b/i` — so `PROJ-247` does not match `PROJ-2470`). This returns MRs across **all** repos (e.g. `org/repo-a !4386` **and** `org/shared !693`), which is exactly the cross-repo set a review needs.
2. **Tracker dev panel (supplementary, often empty).** The tracker's MCP *can* surface linked MRs, but in practice it frequently returns `[]` for MRs (the dev-panel link isn't a remote issue link) — so treat it as a cross-check only, never the sole source. Keep any entry whose URL contains `/-/merge_requests/` and union it with the search results, deduped by MR URL.

For each discovered MR, record `PROJECT_PATH`, `MR_IID`, `PROJECT_ENCODED` (derive them from each result's `web_url` / `references.full`). If **no** MRs are found, say so plainly (`No open MRs found for <TICKET>.`) and stop — there is nothing to review. List the MR set before proceeding so the user sees the full scope (e.g. `Reviewing 2 MRs for PROJ-247: repo-a !4386, shared !693`).

---

## Step 2 — Fetch MR metadata, diffs, and existing comments

Run Steps 2–3 **for each MR in the set** (one MR in MR mode; all discovered MRs in ticket mode).

Three fetches. **Connector first, token second:** use the Git host MCP tool as the primary for each; fall back to the REST call (needs `~/.claude/git-token`) only if the tool is unavailable, fails, or returns thinner data than the fields listed.

### 2a — Metadata (also extracts source branch for ticket ID)

Primary:
```
<Git host MCP get_merge_request>
  id: <PROJECT_PATH>
  merge_request_iid: <MR_IID>
```
Record: `title`, `author`, `source_branch`, `target_branch`, `state`, `user_notes_count`, `labels`, `description`.

REST fallback:
```bash
GIT_TOKEN=$(cat ~/.claude/git-token)
MR_META=$(curl -sf "https://<git-host>/api/v4/projects/<PROJECT_ENCODED>/merge_requests/<MR_IID>" \
  -H "PRIVATE-TOKEN: $GIT_TOKEN")
echo "$MR_META" | node -e "
const chunks=[];process.stdin.on('data',c=>chunks.push(c));process.stdin.on('end',()=>{
  const d=JSON.parse(Buffer.concat(chunks));
  console.log('title:', d.title);
  console.log('author:', d.author.name);
  console.log('source:', d.source_branch);
  console.log('target:', d.target_branch);
  console.log('state:', d.state);
  console.log('user_notes_count:', d.user_notes_count);
  console.log('labels:', JSON.stringify(d.labels));
  console.log('description:', (d.description||'').substring(0,500));
});"
```

Extract ticket ID from `source_branch` (e.g. `feature/PROJ-135_Goal_export_mapping` → `PROJ-135`). Pattern: `/(PROJ-\d+)/i`.

### 2b — Diffs

Primary:
```
<Git host MCP get_merge_request_diffs>
  id: <PROJECT_PATH>
  merge_request_iid: <MR_IID>
```
One entry per file: `new_path`, `new_file`/`deleted_file` flags, `diff`. Files with an empty `diff` → Step 3.

REST fallback:
```bash
GIT_TOKEN=$(cat ~/.claude/git-token)
MR_DIFFS=$(curl -sf "https://<git-host>/api/v4/projects/<PROJECT_ENCODED>/merge_requests/<MR_IID>/diffs?per_page=50" \
  -H "PRIVATE-TOKEN: $GIT_TOKEN")
echo "$MR_DIFFS" | node -e "
const chunks=[];process.stdin.on('data',c=>chunks.push(c));process.stdin.on('end',()=>{
  const files=JSON.parse(Buffer.concat(chunks));
  files.forEach((f,i)=>{
    const flag=f.new_file?'[new]':f.deleted_file?'[deleted]':'';
    console.log('\n--- FILE '+(i+1)+': '+f.new_path+' '+flag+' ---');
    if(f.diff) console.log(f.diff); else console.log('[diff empty — fetch separately]');
  });
});"
```

### 2c — Existing reviewer comments

Primary:
```
<Git host MCP get_workitem_notes>
  project_path: <PROJECT_PATH>
  iid: <MR_IID>
```
Filter out `system` notes; record per comment: author, `type` (`DiffNote` = inline), `resolvable`, `resolved`, `position.new_path`/`new_line`, body. If the response lacks `resolvable`/`position`, fall back.

REST fallback:
```bash
GIT_TOKEN=$(cat ~/.claude/git-token)
MR_NOTES=$(curl -sf "https://<git-host>/api/v4/projects/<PROJECT_ENCODED>/merge_requests/<MR_IID>/notes?per_page=100&sort=asc" \
  -H "PRIVATE-TOKEN: $GIT_TOKEN")
echo "$MR_NOTES" | node -e "
const chunks=[];process.stdin.on('data',c=>chunks.push(c));process.stdin.on('end',()=>{
  const notes=JSON.parse(Buffer.concat(chunks));
  const human=notes.filter(n=>!n.system);
  if(!human.length){ console.log('(no comments)'); return; }
  human.forEach((n,i)=>{
    console.log('\n=== COMMENT '+(i+1)+' ['+n.author.name+'] type='+n.type+' resolvable='+n.resolvable+' resolved='+n.resolved+' ===');
    if(n.position) console.log('  file:', n.position.new_path, 'line:', n.position.new_line);
    console.log(n.body);
  });
});"
```

---

## Step 3 — Fetch files with empty diffs

For any file showing `[diff empty — fetch separately]`, fetch raw content from the source branch. (No connector tool exists for raw file content, so REST is the primary here — a legitimate token use.) Batch in one loop:

```bash
GIT_TOKEN=$(cat ~/.claude/git-token)
for FILE_PATH in "path/to/File1.ext" "path/to/File2.ext"; do
  FILE_ENCODED=$(node -e "process.stdout.write(encodeURIComponent('$FILE_PATH'))")
  echo "=== $FILE_PATH ==="
  curl -sf "https://<git-host>/api/v4/projects/<PROJECT_ENCODED>/repository/files/${FILE_ENCODED}/raw?ref=<source_branch>" \
    -H "PRIVATE-TOKEN: $GIT_TOKEN"
  echo ""
done
```

Only fetch files actually needed to understand the change.

---

## Step 4 — Load ticket context (run once for the ticket)

A good review checks the change against the **business/product spec**, not just the code — so gather the same rich context understand-ticket does, by **reusing that skill's acquisition logic** rather than duplicating it here. Run this once for `TICKET`, before analysing any MR.

### 4a — Gather full ticket context via understand-ticket's acquisition

Follow **understand-ticket's Steps 3–6** to acquire the context (it owns the canonical "how"; do not restate it here):
- **Step 3** — tracker fetch incl. the **custom field where ACs live** (the `description` alone often misses them; this is exactly why review must use understand-ticket's fetch, not a lighter one), remote links, epic.
- **Step 3b/3c/3d** — wiki pages, design mockups, attachments.
- **Step 6** — dependency contracts (e.g. the sibling `shared` MR's symbols).

Use understand-ticket's **acquisition only** — NOT its interactive gate, WIP/flow checkpoints, or state-write. Review does not drive the ticket through lifecycle phases; it only needs the gathered context (ACs, epic constraints, dependencies, specs). Treat the tracker ACs as the authoritative source for coverage, even when a JSON exists on disk.

> **Reuse vs. re-run.** If `<ticket>.json` already exists (the implementer ran understand-ticket), READ it and use it as the context — it already holds ACs, epic, dependencies, and the spec findings; do not re-run the full acquisition. Still re-fetch the tracker ticket (ACs can change after a plan is saved) and reconcile. When no JSON exists (the usual case for someone else's MR), do the acquisition yourself per the steps above — but never write a `phase`/`flow` state file for it.

### 4b — Extra context when the JSON exists (`Read $WORKSPACE_ROOT/.claude/tickets/<ticket>.json`)

When the file is present, extract the implementation context that enriches the review:
- `plan.changes` — what the plan said would change (use to spot scope drift)
- `plan.repos` — which repos are in scope (cross-check against the discovered MR set)
- `plan.ac_coverage` — how the plan mapped ACs to changes
- `plan.acs_out_of_scope` — ACs the dev explicitly deferred at the plan gate; don't flag these as missing
- `reviews` — prior review entries (avoid duplicating already-raised findings)

**Multi-repo check:** if the ticket spans more than one repo (from `plan.repos` or the discovered MR set), an AC may be satisfied by a *different* repo's MR — handle this in the cross-MR coverage check (Step 5a), not by flagging it missing here.

**Prior reviews check:** if `reviews` is present, list which MRs were already reviewed and skip findings already raised there.

### 4c — Tracker unavailable

If the tracker call fails and no JSON exists, proceed with diff-only review. State clearly at the top of the output: _"No ticket context found for <ticket> — review based on diff only, AC coverage not verified."_

If the tracker call fails but the JSON exists, use the JSON's `acs` / `goal` fields for AC coverage and note that the data may be stale.

---

## Step 5 — Analyse and output the review

### 5a — AC coverage check (when ticket context is available)

For each AC, determine: **covered / partial / missing** based on what the diffs show. Every `covered` mark is **REQUIRED: superpowers:verification-before-completion** — back it with the specific diff hunk (file + line) that satisfies the AC, never the MR title or the author's description; if the diff that would prove it couldn't be read (Coverage & gaps), the AC is *unverified*, not silently covered.

```
AC 1: "<full text>"  → ✅ covered           (repo-a !4386 FooService.ext — <what satisfies it>)
AC 2: "<full text>"  → ⚠ partial           (logic present, but no guard for empty estimateId)
AC 3: "<full text>"  → ❌ missing           (no evidence in any MR)
AC 4: "<full text>"  → ✅ covered elsewhere (shared !221 — outside this repo's MR)
```

**Cross-MR coverage (ticket mode).** Map each AC against the **whole MR set**, not one MR in isolation. An AC satisfied by a *different* repo's MR in the set is **covered elsewhere**, not missing — attribute it to that MR. Only ACs unsatisfied by *every* MR in the set are gaps.

Missing or partial ACs are 🔴 blockers **unless** they are covered by another MR in the set, belong to a repo with no MR yet (call it out as not-yet-delivered, not a defect in the MR under review), or are listed in `plan.acs_out_of_scope` (intentionally out of scope). In MR mode (single MR), an AC owned by a different repo is "out of this MR's scope", not a gap.

### 5b — Code review findings

**Check existing comments first.** List what prior reviewers already flagged, and reconcile against it as a *receiver* of that thread — **REQUIRED: superpowers:receiving-code-review**: evaluate each prior comment technically, don't echo it as gospel, and only carry forward the ones still valid for this codebase. Only raise issues NOT already covered — no duplicates.

Group new findings by severity (this is the severity ladder for **REQUIRED: superpowers:requesting-code-review** — and per that discipline, every finding carries a concrete fix and nothing is waved through as "too simple to flag"):
- 🔴 **Bug / Blocker** — must fix before merge
- 🟡 **Should fix** — correctness, security, performance, convention gap
- ⚪ **Minor / style**

For each finding: file, line if applicable, what is wrong, concrete fix.

> **Known non-findings + the conventions checklist live in [review-checklists.md](review-checklists.md)** — read it before grouping findings. It holds the things that *look* like blockers but are documented, expected workflow (chiefly the never-bump-a-shared-submodule-in-a-consumer-MR convention) so you don't raise them, and the convention checklist (5c) to flag genuine violations against.

### 5c — Conventions checklist

The convention checklist is in **[review-checklists.md](review-checklists.md)** (loaded in 5b). Flag any violation it lists.

### 5d — Output structure

**Ticket context** — one line: `PROJ-XXX — <title> | AC count: N | MRs: repo-a !4386, shared !221`

**AC Coverage**
(table as in 5a — only when context available). In ticket mode this is computed **once across the whole MR set** (cross-MR), not per MR.

Then, **per MR** in the set (a single section in MR mode):

> **`<repo> !<iid>`**
>
> **Issues already raised by reviewers** — brief list, so the author has the full picture in one place.
>
> **New findings** — 🔴 / 🟡 / ⚪ findings not yet commented.
>
> **Strengths** (skip if nothing notable)
>
> **Verdict** — approve / needs work for this MR + its top blocker.

**Summary** — overall verdict across the ticket: which MRs approve, which need work, and the single top blocker (or "no blockers"). In ticket mode, call out any AC not covered by *any* MR in the set.

---

## Step 6 — Update ticket JSON

After producing the review, add a `reviews` entry **per MR reviewed** to `$WORKSPACE_ROOT/.claude/tickets/<ticket>.json` — one in MR mode, one for each MR in the set in ticket mode (append them all in a single save). This is the only state `/review` writes — never a `phase`/`flow` field (Step 4a).

> **Persist via the helper — never the Write/Edit tool.** Read the current `<ticket>.json` (Read
> tool), build the full updated object, write it to a temp file with the Write tool at
> `$WORKSPACE_ROOT/<ticket>.state.json`, then run the plain command
> `bash "$WORKSPACE_ROOT/.claude/scripts/save-state.sh" <ticket> "$WORKSPACE_ROOT/<ticket>.state.json"` — the
> helper validates the JSON, writes `.claude/tickets/<ticket>.json`, stamps timestamps, and deletes
> the temp. Do NOT use a heredoc / `<` redirect / `&&` chain (they make the command compound and
> prompt) and do NOT Write/Edit `.claude/tickets/*.json` directly (its dot-dir path prompts on Windows).

**If the file exists:** read it, append to the `reviews` array, then save the whole document. Preserve all other fields.

**If the file does not exist:** create it with a minimal structure containing just the review entry:

```json
{
  "ticket": "<ticket>",
  "reviews": [...]
}
```

Either way, the review entry shape is:

```json
{
  "mr_url": "<full MR URL>",
  "mr_iid": <iid>,
  "repo": "<repo name>",
  "reviewed_at": "<ISO timestamp>",
  "verdict": "needs_work | approved",
  "blocker_count": <N>,
  "open_comments": <unresolved comment count from Step 2c>,
  "summary": "<one sentence>"
}
```

Never skip this step — the JSON must always be written so future `/review` runs can see prior review history.
