import { test as base, APIRequestContext, request, expect } from '@playwright/test';
import sql from 'mssql';

/**
 * Verification fixtures — domain-AGNOSTIC core. Every ticket uses these; nothing here is
 * tied to a specific feature area. Feature/domain helpers live in SIBLING modules (e.g.
 * `fixtures/example-app.ts`) that extend this `test` — a ticket imports the core plus only
 * the domain modules it needs, so an unrelated ticket never has to supply a domain's env vars.
 *
 * Auth model (token-header path):
 *  - Login identity:  your own ADMIN credentials (E2E_USER + E2E_PASSWORD), written once by
 *                     build-env.mjs to the gitignored workspace e2e/.env and reused for every ticket.
 *                     (E2E_TOKEN may hold a pre-acquired token instead, as an optional override.)
 *  - API requests:    header `token: <secureToken>`; the target environment resolves FROM the token.
 *                     Base token from the auth API POST users/getauthenticationtoken with a header naming
 *                     the target environment.
 *  - Impersonation:   applied PER TICKET on top of the base login — feature grants live on the
 *                     impersonated user, not your admin login. Set E2E_IMPERSONATE to the ticket's
 *                     login identity (requires an impersonation grant).
 *
 * Hard rules (see your verification design doc's safety rails):
 *  - DB WRITES (seed/sweep/DDL) require explicit per-command user approval. SELECTs don't.
 *  - Assert CONTRACTS on shared-environment data, never live record names (data drifts in days).
 *  - Creds live ONLY in the gitignored workspace e2e/.env — never hardcode, never commit.
 */

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name} — see e2e/.env.example`);
  return v;
}

// Required vars are lazy (getters) so `playwright test --list` works without a .env.
export const env = {
  apiUrl: process.env.E2E_API_URL ?? 'http://localhost:8080',
  authUrl: process.env.E2E_AUTH_URL ?? 'http://localhost:8081',
  get environment() { return required('E2E_ENVIRONMENT'); },
  user: process.env.E2E_USER,
  password: process.env.E2E_PASSWORD,
  token: process.env.E2E_TOKEN, // optional: pre-acquired token (skips the auth API login)
  get dbConnection() { return required('E2E_DB_CONNECTION'); },
  impersonate: process.env.E2E_IMPERSONATE,
};

// Re-exported so domain fixture modules can demand their own env vars the same way —
// present only when that domain's scenarios actually run.
export { required };

/**
 * Resolve the BASE token (your own admin login), before any per-ticket impersonation.
 * Default: a live login from E2E_USER + E2E_PASSWORD (written to the gitignored e2e/.env by
 * build-env.mjs, reused for every ticket). E2E_TOKEN, if set, is used as a pre-acquired override.
 */
async function baseToken(ctx: APIRequestContext): Promise<string> {
  if (env.token) return env.token;
  if (!env.user || !env.password) {
    throw new Error(
      'No auth in e2e/.env: run `node build-env.mjs <environment> <user>` to write E2E_USER + E2E_PASSWORD (or set E2E_TOKEN).',
    );
  }
  const res = await ctx.post(`${env.authUrl}/users/getauthenticationtoken`, {
    headers: { environment: env.environment },
    data: { userName: env.user, password: env.password },
  });
  if (!res.ok()) {
    throw new Error(`Auth API login failed: ${res.status()} ${await res.text()}`);
  }
  const body = await res.json();
  const token = body?.token ?? body?.authToken ?? body?.Token ?? body?.AuthToken;
  if (!token) throw new Error(`Auth API login: token not found in response: ${JSON.stringify(body).slice(0, 300)}`);
  return token;
}

export async function acquireToken(): Promise<string> {
  const ctx = await request.newContext({ ignoreHTTPSErrors: true });
  try {
    let token = await baseToken(ctx);
    // Impersonation is per-ticket and applies on TOP of the base token (whether that came from a
    // live E2E_USER/E2E_PASSWORD login or a pre-acquired E2E_TOKEN). Your own admin login is never
    // the effective user.
    if (env.impersonate) {
      const imp = await ctx.get(
        `${env.authUrl}/users/getauthenticationtoken?username=${encodeURIComponent(env.impersonate)}`,
        { headers: { token } },
      );
      if (!imp.ok()) {
        throw new Error(`Impersonation of '${env.impersonate}' failed: ${imp.status()} ${await imp.text()}`);
      }
      const impBody = await imp.json();
      token = impBody?.token ?? impBody?.authToken ?? impBody?.Token ?? impBody?.AuthToken;
      if (!token) throw new Error('Impersonation: token not found in response');
    }
    return token;
  } finally {
    await ctx.dispose();
  }
}

/** Target-environment DB access. READ-ONLY by default policy — writes need explicit user approval. */
let pool: sql.ConnectionPool | undefined;
export async function db(): Promise<sql.ConnectionPool> {
  if (!pool) pool = await new sql.ConnectionPool(env.dbConnection).connect();
  return pool;
}
export async function query<T = Record<string, unknown>>(q: string, params: Record<string, unknown> = {}): Promise<T[]> {
  const p = await db();
  const req = p.request();
  for (const [k, v] of Object.entries(params)) req.input(k, v as never);
  const result = await req.query(q);
  return result.recordset as T[];
}

type CoreFixtures = {
  /** Request context pre-authenticated with the token header (LOCAL API by default). */
  api: APIRequestContext;
  /**
   * Same auth, but against the DEPLOYED remote API (E2E_REMOTE_API_URL) when set — for regression
   * scenarios on MERGED code whose heavy queries time out from a local API over the network.
   * Working-tree behavior must always be tested via `api` — deployed remote runs merged code only.
   */
  remoteApi: APIRequestContext;
};

export const test = base.extend<CoreFixtures>({
  api: async ({}, use) => {
    const token = await acquireToken();
    const ctx = await request.newContext({
      baseURL: env.apiUrl,
      ignoreHTTPSErrors: true,
      extraHTTPHeaders: { token },
    });
    await use(ctx);
    await ctx.dispose();
  },
  remoteApi: async ({}, use) => {
    const token = await acquireToken();
    const ctx = await request.newContext({
      baseURL: process.env.E2E_REMOTE_API_URL ?? env.apiUrl,
      ignoreHTTPSErrors: true,
      extraHTTPHeaders: { token },
    });
    await use(ctx);
    await ctx.dispose();
  },
});

export { expect };

// Close the SQL pool when the worker exits so runs don't hang.
test.afterAll(async () => {
  if (pool) {
    await pool.close();
    pool = undefined;
  }
});
