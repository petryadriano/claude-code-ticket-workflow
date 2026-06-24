# Tracker / wiki / attachment fetch procedures

Reference for **understand-ticket Step 3 (Fetch from the tracker)**. The exact MCP calls, field rationale,
custom-field discovery, comment-pagination handling, wiki/mockup/attachment retrieval, and the
tool-result parsing rule. Use the **exact parameters** below — do not deviate.

> The MCP tool names below (`getIssue`, `getIssueRemoteIssueLinks`, `searchIssues`, `getWikiPage`,
> `fetch`) are the tracker's MCP server's tools — substitute your tracker's actual MCP tool names and
> the `cloudId` / workspace identifier it expects. Keep the call *shape*, parameters, and ordering as
> written.

> Apply the acquisition principle from **[source-acquisition.md](source-acquisition.md)** to every
> fetch here (attempt best method first, fall back in order, never silently skip, guide the user
> through any auth gate, retry). The honesty layer under it — only mark a source "read" with
> evidence — is **REQUIRED: superpowers:verification-before-completion**.

## Step 3 — Fetch from the tracker (all in parallel)

Fire all three calls in one message batch.

**Call 1 — Main ticket:**
```
mcp__tracker__getIssue
  cloudId:               "<your-tracker-cloud-id>"
  issueIdOrKey:          "<ticket>"
  responseContentFormat: "markdown"
  fields:                ["summary", "description", "issuetype", "status", "assignee",
                          "labels", "parent", "subtasks", "components", "fixVersions",
                          "comment", "attachment", "issuelinks", "priority",
                          "customfield_ac", "customfield_epiclink", "customfield_sprint"]
```

> **Why these fields:**
> - `customfield_ac` — Acceptance Criteria live here in this tracker instance (the `description` field does not hold them). Missing it means missing every AC. See [[reference-tracker-calls]].
> - `customfield_epiclink` (Epic Link) and `parent` — both point at the epic; use whichever is set.
> - `customfield_sprint` (Sprint), `subtasks`, `components` — downward/scheduling context the curated list used to drop. `subtasks` are child issues to read like dependencies; `components` can route repos.

> **Custom-field discovery (don't assume the curated list is complete).** The curated list above
> can still miss a project-specific field (design link, QA notes, dev estimate, a second AC field).
> Once per ticket, do **one** discovery fetch with `fields: ["*all"]`, parse it with `node`/PowerShell
> (it will likely save to a tool-result file — that's fine), and scan for any **non-null `customfield_*`**
> not already covered. If one holds real context (a URL, a spec, a note), read it and fold it into the
> understanding. List any you intentionally ignore so the omission is visible.

**Call 2 — Remote links (wiki pages, MRs, external deps):**
```
mcp__tracker__getIssueRemoteIssueLinks
  cloudId:      "<your-tracker-cloud-id>"
  issueIdOrKey: "<ticket>"
```

**Call 3 — Epic/parent** (only if `parent.key` exists — skip entirely if no parent):
```
mcp__tracker__getIssue
  cloudId:               "<your-tracker-cloud-id>"
  issueIdOrKey:          "<parent.key>"
  responseContentFormat: "markdown"
  fields:                ["summary", "description", "comment", "attachment", "issuelinks",
                          "status", "labels"]
```

**Comment pagination check:** after receiving the main ticket response, check if `comment.total > comment.comments.length`. If so, the comment list was truncated — log a warning and note that only the first N of M comments were returned. In that case, re-fetch using the tracker's query language to get later comments:
```
mcp__tracker__searchIssues
  cloudId:               "<your-tracker-cloud-id>"
  query:                 "issue = <ticket> ORDER BY comment ASC"
  responseContentFormat: "markdown"
  fields:                ["comment"]
  maxResults:            1
```

**After fetching, immediately read and record:**
- Every comment on the main ticket — author, date, full text. Do not summarise or skip any.
- Every attachment — name, type, and full description of content (for images: describe every visible element; for documents: note filename and what they specify).

Decisions, scope changes, and AC refinements are often in the **last few comments**, not the description. Missing a comment means missing context that will cause wrong implementation.

## Step 3b — Fetch linked wiki pages (do this — they are readable)

Wiki pages **can** be read directly — unlike attachment binaries — so do not leave them as an
"unverified" gap. After the batch above, scan **three** places for wiki links and fetch each one:

1. **Remote links** (Call 2) — entries whose URL contains `/wiki/`.
2. **The main ticket `description`** — inline links and `smartlink` nodes pointing at `.../wiki/spaces/.../pages/<id>/...`.
3. **The epic `description` + comments** (Call 3) — the spec page is most often linked from the epic, not the child ticket.

For each unique wiki URL, extract the page id and fetch the body:

```
mcp__tracker__getWikiPage
  cloudId:       "<your-tracker-cloud-id>"
  pageId:        "<id>"          # the numeric id in /wiki/spaces/<SPACE>/pages/<id>/<slug>,
                                 # OR the tiny-link code from /wiki/x/<code> URLs
  contentFormat: "markdown"
```

- **pageId extraction:** from `https://…/wiki/spaces/<SPACE>/pages/3716284420/Title` the id is `3716284420`. For `…/wiki/x/Fc1bBw` pass the tiny code `Fc1bBw` as `pageId`.
- Read the page body in full — these pages routinely hold the **field/validation contract** (required fields, error codes, KPI/cost mappings) that the ACs only allude to. Treat anything load-bearing as part of the spec.
- If a page genuinely can't be fetched (permission error / deleted), THEN it becomes a Step 7b gap — but only after you tried.
- Record per page: "Read wiki page '<title>' (id <id>)." in the reading audit.

## Step 3c — External design / mockup links

Scan the ticket + epic for **external** links that carry design intent — design tools, prototype apps,
screen recordings, whiteboards, cloud docs/drives, etc. For a **UI ticket the interactive mockup is the primary visual
spec**, so it must not pass unexamined:

- Try `WebFetch` on the URL. For a static doc this may work.
- **Set expectations honestly:** most design tools / prototype apps / whiteboards are JavaScript SPAs — `WebFetch` returns an empty
  app shell, not the rendered design, and many are auth/token-gated. When the fetch yields nothing
  usable, **say so** and ask the user to share screenshots of the relevant screens (or walk you
  through them). Do not silently treat an unreadable mockup as "covered."
- Record the outcome (`read` / `SPA — not renderable` / `auth-gated`) and carry any unreadable mockup
  into the Step 7b.2 gap list.

## Step 3d — Read attachments (attempt the authenticated download, then Read the bytes)

Attachment **metadata** comes back in the `attachment` field (filename, mimeType, id, author, date).
Attachment **binaries** are auth-gated — but "auth-gated" is not "give up." Per the acquisition
principle, **attempt the download first**; only ask the user if every method fails.

For **each** attachment whose content matters (images/mockups/specs — i.e. nearly all), in order:

1. **Authenticated download** via the helper (uses an API token; the token is read from env/file and
   never printed). Save into the ticket's tmp dir, then **Read the file** so the image is actually seen:
   ```bash
   bash "$WORKSPACE_ROOT/.claude/scripts/fetch-attachment.sh" <attachmentId> "$WORKSPACE_ROOT/.claude/tickets/.att/<ticket>/<filename>"
   ```
   - `OK|<path>` → **Read `<path>`** with the Read tool (it renders images / reads PDFs). Describe every
     visible UI element, label, and value. Mark the attachment **read** and drop it from the gap list.
   - `NOAUTH|…` → no token configured yet → **run the one-time setup, then retry the download.** Walk
     the user through it (this enables auto-reading of attachments for *every* future ticket):
     1. Create a token in your tracker's account security / API-tokens settings.
     2. Store + validate it. The user runs this **themselves via the `!` prefix** so the secret stays
        in their shell, not in a tool call (the script writes `~/.tracker-creds` `chmod 600` and
        never echoes the token):
        ```
        !  TRACKER_EMAIL=<you@example.com> TRACKER_API_TOKEN=<token> bash "$WORKSPACE_ROOT/.claude/scripts/setup-tracker-token.sh"
        ```
        - `OK|<name>|<host>` → token works → **re-run `fetch-attachment.sh`** for every attachment, then Read each.
        - `BADAUTH|<code>|…` → tell the user the validation code and have them recheck the token, then rerun.
     3. If the user declines setup, fall back to step 2 (paste).
   - `HTTP_<code>|…` → creds present but refused (401 bad/expired token, 403 no access to that issue).
     Report the code, then fall back to step 2.
2. **Ask the user** (fallback only): list `filename · mimeType · author · date`, give the browse URL
   `https://<your-tracker-host>/browse/<ticket>`, and ask them to **paste the image** (or
   `! start "<browse-url>"`). If they paste it, Read it and drop it from the gap list.

> The `.att/` download dir is scratch — it lives under `.claude/tickets/`, which is outside any git
> repo. Do not commit downloaded binaries.

## Parsing tool-result JSON — use `node` or PowerShell, not `jq`

When a large MCP response (e.g. a tracker issue) is saved to a tool-result file and you need to pull
fields out of it, parse it with `node -e` or PowerShell `ConvertFrom-Json` — both are always present.
**`jq` is not installed** in Git Bash on Windows dev machines and fails with `command not found`.

**Parse to stdout — never write into `.claude/**` from inline node.** The parse exists to bring
fields into context, so print them. Do **not** `fs.writeFileSync`/`mkdir -p` into `.claude/…`
(e.g. saving a parsed epic description under `.att/`) — a dot-dir write target visible in a Bash
command trips Claude Code's sensitive-file guard and prompts, the exact prompt the bash helpers
exist to avoid. Durable content has designated homes: structured facts → state file via
`save-state.sh`; decisions → `append-journal.sh`; attachment binaries → `fetch-attachment.sh`
(the only writer of `.att/`). Parsed tracker text needs no file at all — it lives in context.
