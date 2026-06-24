# Automated-verification harness (e2e/)

Per-ticket evidence suites: the agent (or you) verifies a ticket by driving its real surfaces —
API, UI, and read-only DB assertions — and produces an evidence pack a human approves instead
of executing manual tests. See your team's automated-verification design doc for the full design.

## Setup

```bash
cd e2e
npm install
# (needs valid cloud credentials). Prompts your password; stores creds in the gitignored .env, reused every ticket:
node build-env.mjs <environmentName> <your-user>                          # baseline + creds
node build-env.mjs <environmentName> <your-user> --with=example-domain    # + example domain
# then set E2E_IMPERSONATE per ticket, adjust E2E_API_URL port
```

## Conventions (enforced — see design-doc safety rails)

- **Assertion-surface hierarchy:** UI first, API second, **DB read-only last resort** (flagged).
- **DB writes (seed/sweep/DDL) require explicit per-command user approval. Always.**
- **Contract-level assertions** on shared-environment data — never pin live record names (they drift).
- **Tags:** `@external` = real outbound side effects (e.g. a send to an external system) — excluded by default;
  `@destructive` = mutates shared data — excluded by default, per-scenario confirmation;
  `@remote-deployed` = runs via the `remoteApi` fixture against deployed remote (merged-code regressions ONLY
  — working-tree behavior must run against your local API).
- **Tests live in `tests/<ticket>/`** — verification artifacts first; graduation to a regression
  suite is a separate, later decision.
- Evidence per run: `playwright-report/` (HTML; per-test request/response + DB rows before/after
  via `testInfo.attach`) and traces. `node extract-evidence.mjs <unzipped-trace-dir> <label>`
  dumps a trace's attachments to stdout for inline review.

## Fixtures — core vs domain

**Core (`fixtures/auth.ts`) — domain-agnostic, every ticket imports it:** `api` (local API, base
`token` auth + optional impersonation) · `remoteApi` (deployed remote, same auth) · `query()`/`db()`
(target-environment DB; read-only by policy). Nothing feature-specific lives here.

**Domain modules — import ONLY when your ticket touches that area:** each extends the core `test`
and demands its own env vars only when used, so unrelated tickets never supply them.
- `fixtures/example-app.ts` → an EXAMPLE domain module showing the **UI** helpers for full-stack
  Playwright specs (open a record, read a derived grid value, cross-check the API) plus a
  disposable-test-data setup/teardown helper. It is target-agnostic: it drives whatever
  `E2E_UI_URL`/`E2E_UI_PATH` point at — the UI dev server (default `http://localhost:3000`) or the
  app host in Docker — pointed at your local API. Replace its selectors/paths with your app's.

A spec imports from the core, or from a domain module (which re-exports the core surface). Add a new
domain module when a feature area needs its own reusable helpers — don't grow the core.
