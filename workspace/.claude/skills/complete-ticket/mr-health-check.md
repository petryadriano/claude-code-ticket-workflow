# MR health check

Reference for **complete-ticket — phase `shipped`**. When a bare `/complete-ticket` runs on a ticket
whose MRs are already open, this is what runs instead of jumping to `/improve-skills`. Run it
automatically — no user confirmation needed before starting.

> **The honesty discipline behind this whole section is delegated.** **REQUIRED:
> superpowers:verification-before-completion** — a clean health check may only be claimed from lookups
> that actually returned; this file is the product-specific layer (the lookups, the classification, and
> the routing rules) on top of it.

> **Coverage & gaps:** every MR lookup below that fails (not found, conflicts, unfetchable notes) must be surfaced explicitly with a route to the fix (`/resolve-conflicts`, `/address-review`, or ask the user) — never report a clean health check when a lookup actually failed. Preserve that property when editing this file.

**Fallback if `plan.repos` or `plan.branch` are missing from the state file** (e.g. ticket was pushed without the full skill lifecycle): run `detect-wip.sh` and infer branch + repos from currently checked-out branches. If still not found, search for the ticket's MRs (works even when nothing is checked out locally) — connector first: the Git host's MCP search tool with `query: "<ticket>"`, `scope: merge_requests`. Only if that returns nothing usable, fall back to the REST group endpoint with the token in `$HOME/.claude/git-token`:
```bash
GIT_TOKEN="$(cat "$HOME/.claude/git-token")"
curl -sf "https://<git-host>/api/v4/groups/<group-path>/merge_requests?state=opened&search=<ticket>&per_page=50" \
  -H "PRIVATE-TOKEN: $GIT_TOKEN"
```
Each result gives `project_id`, `iid`, `source_branch`, `target_branch`, `has_conflicts`, `web_url` — map `project_id`/path to the local repo. Only if that returns nothing, ask the user which repos have open MRs before continuing.

## Step A — Find the MR(s)

Run all git remote lookups in a single bash command and all Git host searches in parallel:

```bash
# Get all project paths in one pass
for repo in <plan.repos>; do
  echo "$repo|$(git -C "$WORKSPACE_ROOT/$repo" remote get-url origin 2>/dev/null | sed 's|https://<git-host>/||;s|\.git$||')"
done
```

Then call the Git host's MCP search tool for **all repos simultaneously** (one call per repo, all in the same tool-call batch):
```
<git-host MCP search tool>
  query: "<plan.branch>"
  scope: merge_requests
```
> **Param/server names vary by environment.** One Git host MCP search tool takes `query`; an alternate takes `search` + `project_id` (calling that one with `query` fails: `query is invalid, search is missing`). Use whichever Git host MCP server this session actually exposes, with its own param name.

Collect every result where `source_branch == plan.branch`. Record per repo: `iid`, `state` (opened/merged/closed), `has_conflicts`, `web_url`, `project_path`.

If search returns nothing for a repo: note it as "MR not found" — the branch may not have been pushed yet, or the MR was not created.

## Step B — Fetch discussion state

**Skip this step entirely for any repo where `has_conflicts == true`** — those route to Rule 1 regardless of comment count; fetching notes for them wastes a round-trip.

For each remaining repo whose MR is still `opened`, fetch notes **in parallel** (all in the same tool-call batch):
```
<git-host MCP notes tool>
  project_path: <project_path>
  iid: <mr_iid>
```

Count notes where `resolvable == true` AND `resolved == false`. This is the **unresolved comment count**.

If the notes tool returns no useful data: fall back to the Git host's get-merge-request tool and check `blocking_discussions_resolved` or `user_notes_count` fields if present.

> **Destructive-MR audit — do not skip on a quiet MR.** "0 unresolved comments" means *no one objected*, not *the change is safe*. For any MR that is destructive — a database script, or any one-time `DELETE` / `UPDATE` / backfill — read the actual script regardless of comment count: map raw magic numbers to their enum names and confirm the logic matches the code side of the ticket. When a ticket spans a code repo **and** the database, diff the value-sets between them (the SQL frequently mirrors an enum / source-type set the code just changed) before classifying the MR as "under review." A quiet, reviewer-approved cleanup script is exactly how a data-loss delete reaches production.

## Step C — Route based on findings

Classify each MR into one of these states:

| MR state | Criteria |
|---|---|
| **merged** | `state == "merged"` |
| **closed** | `state == "closed"` |
| **conflicts** | `state == "opened"` AND `has_conflicts == true` |
| **change requests** | `state == "opened"` AND unresolved comments > 0 |
| **under review** | `state == "opened"` AND no conflicts AND unresolved comments == 0 |

Show the health dashboard (always, even when clean):

```
PROJ-XXX MR status:

  api     !42 → <state label>  [e.g. "open — 3 unresolved comments"]
  web     !17 → <state label>  [e.g. "open — has conflicts"]
  database     → MR not found
```

Then apply the routing rules below — **in priority order**. If a repo needs conflicts resolved, that always comes before addressing review comments.

**Rule 1 — Any MR has conflicts:**
```
⚠ Conflicts detected. Resolve them before addressing review comments.

Run: /resolve-conflicts PROJ-XXX
```
Stop. Do not proceed to address-review or improve-skills.

**Rule 2 — No conflicts, but unresolved comments exist:**
```
Review feedback waiting.

Run: /address-review PROJ-XXX
```
Stop. Do not proceed to improve-skills.

**Rule 3 — No conflicts, no unresolved comments, all MRs open (under review):**
```
MR(s) are open and under review — no feedback yet.
```
Ask: _"Run /improve-skills to reflect while waiting for review?"_ Wait for reply. On yes → invoke `improve-skills`. On no → stop.

**Rule 4 — All MRs are merged (or ticket has no open MRs):**
```
✓ All MRs merged. Ticket is done.
```
Ask: _"Run /improve-skills to reflect and improve the workflow?"_ Wait for reply. On yes → invoke `improve-skills`.

**Rule 5 — Mixed (some merged, some still open with issues):**
Apply Rules 1–3 to the remaining open MRs. Mention that `<repo>` is already merged.

**Rule 6 — MR not found for one or more repos:**
```
⚠ No open MR found for <repo>. The branch may not have been pushed yet, or the MR was closed.
```
Still apply rules to any MRs that were found. If no MRs were found at all → stop and ask the user to confirm the MR status manually.
