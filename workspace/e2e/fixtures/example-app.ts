import { APIRequestContext, expect, request } from '@playwright/test';
import type { Page } from '@playwright/test';
import { test as base, env, query, required } from './auth';

/**
 * ============================================================================
 * EXAMPLE — replace with your app's specifics.
 * ============================================================================
 * This is a TEMPLATE domain module, not a working fixture. It shows the reusable
 * PATTERNS for a feature area's e2e helpers; every selector, URL path, route, table
 * name, and column key below is a PLACEHOLDER. Swap them for your app's real ones.
 *
 * Import this ALONGSIDE the core (`fixtures/auth`) for a ticket whose ACs need the UI;
 * it re-exports the core surface so a spec can import everything from here.
 *
 * It demonstrates four reusable patterns:
 *   1. Point the UI at your LOCAL backend (the one rule that makes a UI test real).
 *   2. A page-object-style UI reader for backend-DERIVED values.
 *   3. An authoritative API cross-check of those values.
 *   4. Disposable test data: set up a throwaway record, then soft-delete it in teardown.
 * It also shows an optional callback-key fixture (an external data source's inbound call).
 *
 * ----------------------------------------------------------------------------
 * 🔴 PATTERN 1 — THE ONE RULE that makes a UI test real: point the UI at your LOCAL API.
 * ----------------------------------------------------------------------------
 * A deployed UI bundle resolves its data host from a built-in env map; that default points at
 * the DEPLOYED backend (no unmerged code), and a dev-server flag often does NOT redirect it. You
 * MUST override the UI's data host → your local API (e.g. a debug-only edit to the env map, or a
 * proxy) or the UI reads ALL data from the deployed backend and your working-tree change is never
 * exercised (a backend-populated value can render BLANK while the API returns it). See your
 * start-stack docs. This module is target-agnostic: `E2E_UI_URL` + `E2E_UI_PATH` decide WHERE the
 * UI is served (dev server, or the app host in Docker) — whichever you pick must point at your
 * local API.
 */

/** UI base URL — the dev server (default) or your app host (set E2E_UI_URL). */
export const uiUrl = (): string => (process.env.E2E_UI_URL ?? 'http://localhost:3000').replace(/\/$/, '');

/**
 * Path to a record, appended to `uiUrl()`. Default targets a dev server (`/{recordId}/{versionId}`);
 * override with `E2E_UI_PATH` to target the app host (environment-prefixed), e.g.
 * `/{environment}/App/{recordId}/{versionId}`. Substitutes `{environment}` (from .env), `{recordId}`, `{versionId}`.
 */
export function recordPath(recordId: number | string, versionId: number | string): string {
  return (process.env.E2E_UI_PATH ?? '/{recordId}/{versionId}')
    .replace('{environment}', env.environment)
    .replace('{recordId}', String(recordId))
    .replace('{versionId}', String(versionId));
}

/**
 * EXAMPLE — build whatever auth payload your UI expects. Here it is a base64 `?auth=` URL param
 * carrying the login + impersonated token + per-ticket feature flags. `token` should be the
 * impersonated token (the ticket's login identity, via acquireToken()).
 */
export function authParam(token: string, featureFlags: Record<string, boolean> = {}): string {
  const payload = {
    env: process.env.E2E_UI_ENV ?? 'REMOTE', // PLACEHOLDER UI env-map key
    login: env.user,
    password: env.password,
    environment: env.environment,
    token,
    ...featureFlags,
  };
  return Buffer.from(JSON.stringify(payload)).toString('base64');
}

export type OpenRecordOpts = {
  recordId: number | string;
  versionId: number | string;
  token: string;
  /** Per-ticket feature flags for the auth param. */
  featureFlags?: Record<string, boolean>;
  /** A selector whose presence means the record rendered (PLACEHOLDER). */
  readySelector?: string;
  /** Reload attempts + per-attempt polls before giving up (sensible defaults; override per ticket). */
  attempts?: number;
  polls?: number;
  pollMs?: number;
};

/**
 * PATTERN 2 (open) — open a record in the UI and wait until it renders. Navigates with the auth
 * param and polls (with reloads) for the ready selector — surfacing a server-error body early.
 * Throws a clear, actionable error if it never renders.
 */
export async function openRecord(page: Page, opts: OpenRecordOpts): Promise<Page> {
  const {
    recordId, versionId, token, featureFlags = {},
    readySelector = '[data-test="record-loaded"]', // PLACEHOLDER
    attempts = 4, polls = 14, pollMs = 3500,
  } = opts;

  const url = `${uiUrl()}${recordPath(recordId, versionId)}?auth=${authParam(token, featureFlags)}`;
  let loaded = false;
  for (let attempt = 1; attempt <= attempts && !loaded; attempt++) {
    if (attempt === 1) {
      await page.goto(url, { timeout: 90000, waitUntil: 'domcontentloaded' });
    } else {
      await page.reload({ timeout: 90000, waitUntil: 'domcontentloaded' });
    }
    for (let i = 0; i < polls && !loaded; i++) {
      await page.waitForTimeout(pollMs);
      if (await page.locator('text=Internal Server Error').count()) {
        break;
      }
      loaded = (await page.locator(readySelector).count()) > 0;
    }
  }
  if (!loaded) {
    throw new Error(
      `Record ${recordId}/${versionId} did not render ("${readySelector}"). Is the UI serving at ${uiUrl()} and pointed at your local API? (see your start-stack docs)`,
    );
  }
  return page;
}

/**
 * PATTERN 2 (read) — page-object-style reader for a backend-DERIVED grid value.
 *
 * EXAMPLE technique: header cells and the selected row's value cells share the exact left-x per
 * column, so values are matched to headers by left (±3px), keyed by the column LABEL. This reads
 * backend-derived values that render only in the selected/detail row. Runs entirely in the browser
 * context (no module-scope references) so it serializes for page.evaluate. Preconditions: the UI
 * points at the local API (Pattern 1), and the asserted columns are DISPLAYED in the current view.
 * Replace every selector below with your app's.
 */
export function readGrid(page: Page): Promise<{ headers: string[]; pairs: Record<string, string> }> {
  return page.evaluate(() => {
    // PLACEHOLDER selectors — replace with your app's grid markup.
    const wrap = document.querySelector('[data-test="grid-wrapper"]') ?? document.body;
    const headerCells = Array.from(wrap.querySelectorAll('[data-test="grid-header-cell"]'))
      .map((el) => ({ t: (el as HTMLElement).innerText?.trim() ?? '', left: Math.round(el.getBoundingClientRect().left) }))
      .filter((c) => c.t);
    const row = wrap.querySelector('[data-test="grid-selected-row"]');
    const valueCells = row
      ? Array.from(row.children).map((el) => ({ t: (el as HTMLElement).innerText?.trim() ?? '', left: Math.round(el.getBoundingClientRect().left) }))
      : [];
    const pairs: Record<string, string> = {};
    for (const h of headerCells) {
      const v = valueCells.find((vc) => Math.abs(vc.left - h.left) <= 3);
      if (!(h.t in pairs)) {
        pairs[h.t] = v ? v.t : '';
      }
    }
    return { headers: headerCells.map((h) => h.t), pairs };
  });
}

/** Parse a displayed cell ("$85.71", "1,234") to a number for tolerance assertions. */
export const num = (s: string | undefined): number => Number((s ?? '').replace(/[^0-9.\-]/g, ''));

/**
 * PATTERN 3 — authoritative API cross-check for UI values. Fetch the same derived values from the
 * API and compare against what the UI rendered. (Uses a fresh request context with the given token
 * so it works inside a UI spec.) PLACEHOLDER route + field names.
 */
export async function apiMeasures(
  token: string,
  recordUuid: string,
  versionUuid: string,
): Promise<Record<string, number | null>> {
  const ctx = await request.newContext({ baseURL: env.apiUrl, ignoreHTTPSErrors: true, extraHTTPHeaders: { token } });
  const items = (await (await ctx.get(`/measures/for/${recordUuid}/${versionUuid}`)).json()) as Array<Record<string, unknown>>;
  await ctx.dispose();
  const f = (items.find((x) => x.Measures ?? x.measures) ?? {}) as Record<string, unknown>;
  const m = (f.Measures ?? f.measures ?? {}) as Record<string, number>;
  return { valueA: m.ValueA ?? null, valueB: m.ValueB ?? null };
}

/**
 * ----------------------------------------------------------------------------
 * PATTERN 4 — disposable test data: set up a throwaway record, soft-delete it in teardown.
 * ----------------------------------------------------------------------------
 * Never mutate shared records. Instead clone/create a disposable one (via the UI or API), exercise
 * it, then soft-delete it (recycle bin) — never a hard/destructive purge. Tag throwaway records with
 * a stable name prefix so a crashed run's orphan is always identifiable and sweepable.
 */

type DisposableRecord = { recordId: number; versionId: number };

/** Stable name prefix for disposable e2e records — so a crashed run's orphan is identifiable + sweepable. */
export const E2E_DISPOSABLE_PREFIX = 'e2e-disposable-';

/**
 * EXAMPLE — create a disposable record (here by cloning a source via the API) and resolve its ids
 * from the DB by the unique name. Replace the route + table/column names with your app's. Name your
 * record `${E2E_DISPOSABLE_PREFIX}<ticket>-<timestamp>`.
 */
export async function setupDisposableRecord(
  token: string,
  opts: { srcRecordId: number | string; newName: string },
): Promise<DisposableRecord> {
  const ctx = await request.newContext({ baseURL: env.apiUrl, ignoreHTTPSErrors: true, extraHTTPHeaders: { token } });
  // PLACEHOLDER route — your "clone/create" endpoint.
  await ctx.post(`/records/clone/${opts.srcRecordId}`, { data: { name: opts.newName } });
  await ctx.dispose();

  // Resolve the real numeric ids by the unique name (robust against async persistence).
  let recordId = 0, versionId = 0;
  for (let i = 0; i < 30; i++) {
    // PLACEHOLDER table/columns.
    const rows = await query<{ RecordId: number; VersionId: number }>(
      'SELECT TOP 1 RecordId, VersionId FROM dbo.Records WHERE Name = @n ORDER BY RecordId DESC', { n: opts.newName });
    if (rows[0]?.RecordId) { recordId = rows[0].RecordId; versionId = rows[0].VersionId; break; }
    await sleep(2000);
  }
  if (!recordId) {
    throw new Error(`setupDisposableRecord: "${opts.newName}" was not persisted (no row in dbo.Records).`);
  }
  return { recordId, versionId };
}

/** Page-independent sleep — the page may be navigating, which breaks page.waitForTimeout. */
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * EXAMPLE — soft-delete (recycle) a disposable record via the API. Use in teardown. PLACEHOLDER route.
 * Soft-delete only (recycle bin) — never the environment-wide empty-recycle-bin.
 */
export async function recycleRecord(token: string, recordId: number | string): Promise<number> {
  const ctx = await request.newContext({ baseURL: env.apiUrl, ignoreHTTPSErrors: true, extraHTTPHeaders: { token } });
  const r = await ctx.get(`/records/recycle/${recordId}/true`);
  await ctx.dispose();
  return r.status();
}

/**
 * Defensive cleanup: recycle any ACTIVE disposable records left by crashed runs (matched by the e2e
 * name prefix, not yet deleted). Call at the START of a disposable-record spec (clean slate) and/or
 * as a standalone cleanup. Soft-delete only. Returns counts. PLACEHOLDER table/columns.
 */
export async function sweepDisposableRecords(token: string, namePrefix: string = E2E_DISPOSABLE_PREFIX): Promise<{ found: number; recycled: number }> {
  const orphans = await query<{ RecordId: number }>(
    'SELECT RecordId FROM dbo.Records WHERE Name LIKE @p AND DateDeleted IS NULL', { p: namePrefix + '%' });
  let recycled = 0;
  for (const o of orphans) {
    if ((await recycleRecord(token, o.RecordId)) === 200) { recycled++; }
  }
  return { found: orphans.length, recycled };
}

/**
 * ----------------------------------------------------------------------------
 * OPTIONAL fixture — an external data source's inbound callback (no user auth).
 * ----------------------------------------------------------------------------
 * EXAMPLE: an external system calls one of your endpoints with its own access key (no user/
 * environment context — the endpoint resolves the environment from a URL `?environment=` segment).
 * Demand its env var (E2E_EXAMPLE_CALLBACK_KEY) ONLY when these fixtures are actually used, so an
 * unrelated ticket importing the core never has to provide it.
 */
type ExampleAppFixtures = {
  /** Request context carrying the external callback access key (no user auth). */
  externalCallback: APIRequestContext;
};

export const test = base.extend<ExampleAppFixtures>({
  externalCallback: async ({}, use) => {
    const ctx = await request.newContext({
      baseURL: env.apiUrl,
      ignoreHTTPSErrors: true,
      extraHTTPHeaders: { 'X-Api-Access-Key': required('E2E_EXAMPLE_CALLBACK_KEY') }, // PLACEHOLDER header
    });
    await use(ctx);
    await ctx.dispose();
  },
});

// Re-export the core surface so a spec imports everything from this one module.
export { expect, env, query, db, acquireToken, required } from './auth';
