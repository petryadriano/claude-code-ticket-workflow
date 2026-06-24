# Reading audit + coverage & gaps map

Reference for **understand-ticket Step 7b (Reading audit + unverified-content warning)**. Before
showing the summary, do **two** things — first a positive accounting of what was read, then an
explicit warning about anything that could not be read or verified. See [[warn-on-unverified]].

> **The honesty discipline behind this whole step — never imply a source is "read/verified" without
> evidence, surface gaps explicitly instead of letting silence hide them — is delegated.**
> **REQUIRED: superpowers:verification-before-completion.** This file is the domain-specific structure:
> the exact coverage-map columns, the reading-audit format, and the gap checklist for the tracker's sources.

## 7b.0 — Full source-coverage map (mandatory — every source, read or not)

Map **every** context source the ticket touches into one table, so what could *not* be read is
impossible to miss. One row per discrete source. Status is exactly one of **READ ✓**,
**PARTIAL ◐**, or **NOT READ ✗**. Enumerate at least these source *classes* and expand each to the
concrete items found:

- Tracker fields (core + ACs `customfield_ac`), and the `*all` custom-field discovery result
- Comments (main ticket) — count read / total
- Attachments (main ticket) — **one row each**, with the Step 3d outcome
- Inline images embedded in the description/comments (`![](blob:…media…)`) — one row each
- Worklogs (do their comment bodies carry context?)
- Wiki pages (Step 3b) — one row each
- External design/mockup links (Step 3c) — one row each
- Epic: fields / comments / attachments
- Each dependency (Step 6) — description + its comments
- Anything intentionally skipped (siblings, related issues, changelog) — list it as a *deliberate* `✗` with the reason

```
Source coverage map — PROJ-XXX
| Source                                   | Status   | Method              | If not read — why + fallback        |
|------------------------------------------|----------|---------------------|-------------------------------------|
| Ticket core fields + ACs                 | READ ✓   | getIssue            | —                                   |
| Custom-field discovery (*all)            | READ ✓   | getIssue *all       | —                                   |
| Ticket comments (N/N)                    | READ ✓   | getIssue            | —                                   |
| Attachment: <file.png>                   | NOT READ ✗ | fetch-attachment.sh | NOAUTH — configure token / paste    |
| Inline desc image <id>                   | NOT READ ✗ | —                   | media blob, auth-gated — paste      |
| Wiki: <title>                            | READ ✓   | getWikiPage         | —                                   |
| Mockup: <url>                            | NOT READ ✗ | WebFetch            | SPA/auth bridge — screenshots       |
| Epic <KEY>: desc/comments                | READ ✓   | getIssue            | —                                   |
| Dep <KEY>: contract                      | READ ✓   | getIssue            | —                                   |
| Dep <KEY>: comments (0/14)               | PARTIAL ◐ | —                   | read desc only — open if contract unclear |
| Epic siblings (not consumed)             | NOT READ ✗ | —                   | deliberate — out of scope           |
```

Close the map with a one-line tally: `Coverage: X READ ✓ · Y PARTIAL ◐ · Z NOT READ ✗.`

## 7b.1 — What was read

```
Reading audit:
  Main ticket  PROJ-XXX: <N> comments read, <M> attachments read
  Epic         PROJ-YYY: <N> comments read, <M> attachments read  (or "no epic")
  Dependency   PROJ-ZZZ: <N> comments read, <M> attachments read  (one line per dependency)
```

If any source returned zero comments AND you did not see an empty comment list in the API response, re-fetch before continuing — the data may have been truncated.

## 7b.2 — What could NOT be verified (mandatory)

Then compute the gap list. Show this section **even when empty** — silence hides things.

```
⚠ Unverified content (please confirm or share):
- <bullet per gap>
```

Check at minimum:

- **Attachments / images** — only the ones **Step 3d could not read** are gaps. For each still-unread
  attachment, give `filename · mimeType · author · date`, the **exact failure** (`NOAUTH` — no token
  configured / `HTTP_401` bad token / `HTTP_403` no access), the browse URL
  `https://<your-tracker-host>/browse/<ticket>`, and the fallback (configure a token to auto-read
  next time, or paste the image now). Attachments that Step 3d **did** read are not gaps — list them in
  the reading audit instead. (Background: an anonymous GET on both the tracker's API gateway and
  the tracker host is **403/401**; the MCP server exposes no attachment tool and `fetch` is
  issues/pages-only — which is exactly why Step 3d uses the API-token Basic-auth download.)
- **Acceptance Criteria** — for non-Spike issuetypes, if both the description and `customfield_ac` are empty, warn that no ACs were found anywhere.
- **Comment pagination** — if `comment.total > comment.comments.length`, warn that comments N..M were not retrieved.
- **Linked items / dependencies** — if any link could not be fetched (permission error, deleted target), warn with the key and the error.
- **Wiki pages** — these are **fetched in Step 3b**, so a linked page is normally *not* a gap. Only list one here if its `getWikiPage` call actually **failed** (permission/deleted) — name the page and the error. Never list a page here without having attempted the fetch.
- **External design / mockups** (Step 3c) — any design-tool / prototype / recording link that couldn't be rendered (SPA or auth-gated). For a UI ticket this is **high-impact** — name the link and ask for screenshots.
- **Custom fields expected but null** — if for the issuetype you'd expect AC / Dev Estimate / Story Points populated and they came back null, warn. Also surface anything found by the Step 3 `*all` discovery pass that you could not interpret.

If there are **no gaps**, state it explicitly: `All ticket content read and verified.`
