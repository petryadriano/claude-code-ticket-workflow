# Source acquisition — read EVERYTHING, degrade gracefully, never silently skip

Reference for **understand-ticket Steps 3–6 (Fetch & resolve)**. Steps 3–6 gather context from many
sources (tracker fields, comments, attachments, the wiki, external mockups, dependencies). Apply the
principle below to **every** source, **every** run.

> **The honesty discipline behind this — never treat an unread source as covered, and only claim a
> source is "read/verified" with evidence — is delegated.** **REQUIRED: superpowers:verification-before-completion.**
> The exact-failure capture in rule 3 (read the precise HTTP code / "SPA shell" / "NOAUTH" before
> deciding a source is gated) is the instance of **REQUIRED: superpowers:systematic-debugging** —
> root-cause *why* a fetch failed before recording it as a gap. This file is only the domain-specific
> layer: the source classes and the guided-remediation playbook for each.

## ⛏ Acquisition principle

1. **Always attempt the best available method first** — even for sources that were gated last time.
   Auth/capability changes between tickets (a token gets configured, an external-tool access gets granted, a
   new MCP tool appears). A source that failed yesterday may succeed today, so **re-try it; do not
   pre-skip it** because "it's usually gated."
2. **Fall back in order**, best → worst: structured MCP tool → authenticated download (API token) →
   `WebFetch` → ask the user to paste/screenshot. Take the first that yields real content.
3. **Never silently treat an unread source as covered.** If every method fails, record the source,
   the **exact** failure (HTTP code / "SPA shell" / "auth bridge" / "NOAUTH"), the method(s) tried,
   and the precise human fallback — then carry it into the Step 7b.2 gap list.
4. **When a method newly succeeds, read the content fully** and fold it into the understanding (and
   drop it from the gap list). The goal is maximum real coverage, not a tidy excuse for skipping.
5. **If auth or config is the only thing standing between you and the content, GUIDE the user to
   fix it — don't just report it.** For every gated source, name the *exact* credential/permission/
   setting required, give copy-pasteable steps or a `!` command to enable it, wait for the user to
   do it, then **retry the fetch**. Manual paste/screenshots are the *last* resort, offered only
   after the user declines the setup. "Couldn't read it (auth)" is never an acceptable stopping
   point if a setup path exists — surface the path.

## Guided-remediation playbook

Gated source → what to set up; always retry after:

| Gated source | What unblocks it | How to guide the user |
|---|---|---|
| Tracker attachment binaries (403/NOAUTH) | Tracker API token | Step 3d: `setup-tracker-token.sh` via `!`, then `fetch-attachment.sh` |
| Wiki page (permission error) | View access on the space | Ask the user to confirm they can open the page; if so the MCP token already works — retry. If not, ask them to request space access or paste the page. |
| Design-tool / prototype / whiteboard mockup (SPA / auth bridge) | A shareable/public link or export | Ask the user to set the link to "anyone with link can view" and resend, or export the relevant frames to PNG and paste. Re-try `WebFetch` on any new link. |
| Cloud document/drive link | View access or a document-store MCP | If a document-store MCP tool is connected, use it; else ask the user to share the doc or paste its text. |
| A null field you *expected* populated | It may live in another custom field | Use the `*all` discovery pass; if still empty, ask the user where that info lives. |

This table is a starting set — when a **new** kind of gated source appears, infer the enabling
action the same way (identify the auth/permission/config, hand the user the concrete steps, retry).
