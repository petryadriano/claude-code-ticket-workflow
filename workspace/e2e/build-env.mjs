// build-env.mjs — assemble e2e/.env for THIS workspace: the baseline (URLs + target environment + DB
// connection, from your environment-metadata API + your cloud secrets store) PLUS your login creds. Run it
// ONCE per workspace; every ticket then reuses the result silently — your creds don't change, so you are
// never asked again.
//
// Credentials — ONE step, ONE file:
//  - Creds come from a gitignored e2e/.login file with two fields, USERNAME + PASSWORD, for a user with
//    ADMIN (or impersonation) access in the app. Run `node build-env.mjs <environment>` with no .login and it
//    SCAFFOLDS that template and exits (prints LOGIN_NEEDED, code 3) — the user fills both fields, saves,
//    and the command is re-run. The password never goes on argv or into the chat/transcript.
//  - On a successful build the creds are written to e2e/.env (gitignored — silent reuse for every ticket)
//    and e2e/.login is DELETED. e2e/.env is NEVER committed (only .env.example is).
//  - Per-ticket impersonation (E2E_IMPERSONATE, e.g. a restricted user) is applied at run time on top of this
//    login; set it per ticket. Secrets never hit stdout.
//
// Usage: node build-env.mjs <environmentName> [user] [--env=<cloudEnv>] [--with=<domain> ...]
//   - <environmentName> = the ticket's test_scope target environment. Creds come from e2e/.login (above); the
//     optional [user] positional + E2E_LOGIN_PASSWORD env are still honored for non-interactive automation.
//   - cloudEnv defaults to qa; override with --env=<cloudEnv>.
//   - Domain vars are opt-in per ticket: --with=example-domain adds E2E_EXAMPLE_CALLBACK_KEY (example-domain flow only).
// Assumes valid cloud credentials (it reads your config + secrets store + the environment-metadata API) —
// normally already set up. On an auth failure, refresh your cloud credentials; if the environment isn't found,
// check the name / your network access. Don't prescribe these upfront — they surface as errors only when
// actually missing.
//
// Gotcha this script absorbs: passwords inside the cloud connection-string secrets can be escaped (`}}` =
// literal `}`). Some SQL clients collapse the escape at parse time; others take it literally — so un-escape.
import { execFileSync } from 'node:child_process';
import { writeFileSync, readFileSync, existsSync, unlinkSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
const positionals = argv.filter((a) => !a.startsWith('--'));
const domains = argv.filter((a) => a.startsWith('--with=')).map((a) => a.slice(7));
const envFlag = argv.find((a) => a.startsWith('--env='))?.slice(6);
const environmentName = positionals[0];
const argUser = positionals[1];
const cloudEnv = envFlag || positionals[2] || 'qa';
if (!environmentName) {
  console.error('usage: node build-env.mjs <environmentName> [user] [--env=<cloudEnv>] [--with=<domain>]');
  console.error('  creds come from a gitignored e2e/.login file (USERNAME + PASSWORD); run with just <environment> to scaffold it.');
  process.exit(2);
}

// --- Credentials: one gitignored e2e/.login file (USERNAME + PASSWORD), scaffolded on first run. ---
// Paths resolve from the script location (import.meta.url), not cwd, so it works from any directory.
const loginUrl = new URL('./.login', import.meta.url);
const loginPath = fileURLToPath(loginUrl);
const LOGIN_TEMPLATE = [
  '# e2e login — credentials for a user with ADMIN (or impersonation) access in the app.',
  '# Fill in BOTH values below, SAVE this file, then tell the agent you are done.',
  '# Gitignored; deleted automatically once .env is built; never committed.',
  'USERNAME=',
  'PASSWORD=',
  '',
].join('\n');

let fileUser, filePass;
if (existsSync(loginUrl)) {
  for (const raw of readFileSync(loginUrl, 'utf8').split(/\r?\n/)) {
    const line = raw.replace(/\r$/, '');
    if (/^\s*#/.test(line)) {
      continue;
    }
    const mU = line.match(/^\s*USERNAME\s*=(.*)$/i);
    const mP = line.match(/^\s*PASSWORD\s*=(.*)$/i);
    if (mU) {
      fileUser = mU[1].trim();
    }
    if (mP) {
      filePass = mP[1];
    }
  }
}

const user = fileUser || argUser;
const password = filePass || process.env.E2E_LOGIN_PASSWORD;

// No usable creds yet → scaffold (or keep) the .login template and stop, so the user fills it in ONE step.
if (!user || !password) {
  if (!existsSync(loginUrl)) {
    writeFileSync(loginUrl, LOGIN_TEMPLATE);
    console.log('LOGIN_NEEDED: created %s — fill in USERNAME + PASSWORD (a user with admin/impersonation access in the app), save, then re-run this command.', loginPath);
  } else {
    console.log('LOGIN_NEEDED: %s is missing USERNAME and/or PASSWORD — fill both, save, then re-run this command.', loginPath);
  }
  process.exit(3);
}

// `cloud` stands in for your cloud provider's CLI (config/parameter reads + secrets store). Replace the
// argument shapes below with your provider's equivalents; the control flow is what matters.
const cloud = (args) => execFileSync('cloud', args, { encoding: 'utf8' }).trim();
const configParam = (name) =>
  cloud(['config', 'get-parameter', '--name', name, '--query', 'Parameter.Value', '--output', 'text']);
const secret = (id) =>
  JSON.parse(cloud(['secrets', 'get-secret-value', '--secret-id', id, '--query', 'SecretString', '--output', 'text']));

const metadataApiUrl = configParam(`/${cloudEnv}/general/EnvironmentMetadataUrl`);
const authApiUrl = configParam(`/${cloudEnv}/general/AuthApiUrl`).replace(/\/$/, '');
const remoteApiUrl = configParam(`/${cloudEnv}/general/ApiUrl`).replace(/\/$/, '');

const environment = await (await fetch(`${metadataApiUrl}/environment/GetByName?name=${encodeURIComponent(environmentName)}`)).json();
if (!environment?.DatabaseServerName) {
  console.error(`Environment '${environmentName}' not found via ${metadataApiUrl} (check your network access / spelling).`);
  process.exit(1);
}

const conn = secret(`${cloudEnv}/ConnectionStrings`);

const rawPwd = conn.DbContext.match(/password=([^;]*)/i)[1];
const dbConn = conn.DbContext
  .replace(rawPwd, rawPwd.replaceAll('}}', '}')) // un-escape doubled braces some SQL clients take literally
  .replace('{0}', environment.DatabaseServerName)
  .replace('{1}', environment.DatabaseName);

const lines = [
  `# generated by build-env.mjs for ${environmentName} (${cloudEnv}) — DO NOT COMMIT (gitignored)`,
  `E2E_API_URL=http://localhost:8080`,
  `E2E_REMOTE_API_URL=${remoteApiUrl}`,
  `E2E_AUTH_URL=${authApiUrl}`,
  `E2E_ENVIRONMENT=${environment.Name}`,
  `E2E_USER=${user}`,
  `E2E_PASSWORD=${password}`,
  `E2E_IMPERSONATE=`,
  `E2E_DB_CONNECTION=${dbConn}`,
];

// Domain-specific vars — written ONLY when --with=<domain> asks, so the baseline .env stays
// minimal for tickets that don't touch that area (e.g. an unrelated ticket gets no example-domain key).
if (domains.includes('example-domain')) {
  const common = secret(`${cloudEnv}/Common`);
  const ex = typeof common.ExampleIntegration === 'string' ? JSON.parse(common.ExampleIntegration) : common.ExampleIntegration;
  lines.push('', '# domain: example-domain (--with=example-domain)', `E2E_EXAMPLE_CALLBACK_KEY=${ex?.CallbackApiAccessKey ?? ''}`);
}

writeFileSync(new URL('./.env', import.meta.url), lines.join('\n') + '\n');

// Creds are now persisted in the gitignored .env — remove the short-lived .login drop file.
try {
  unlinkSync(loginUrl);
} catch {
  /* already gone — fine */
}

console.log('OK: .env written. environment=%s server=%s db=%s%s (adjust E2E_API_URL port + set E2E_IMPERSONATE per ticket)',
  environment.Name, environment.DatabaseServerName, environment.DatabaseName,
  domains.length ? ` domains=[${domains.join(',')}]` : '');
