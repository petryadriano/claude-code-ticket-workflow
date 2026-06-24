import { defineConfig } from '@playwright/test';
import * as dotenv from 'dotenv';

dotenv.config({ path: `${__dirname}/.env` });

// Evidence-grade defaults: full trace always (reviewers replay what the agent saw),
// HTML + JSON reports, single worker (shared target-environment data — never parallelize).
// Browser/UI projects (baseURL + storageState) arrive with the UI pilot.
export default defineConfig({
  testDir: './tests',
  outputDir: './test-results',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  use: {
    trace: 'on',
    ignoreHTTPSErrors: true, // local dev certs
  },
  reporter: [
    ['list'],
    ['html', { outputFolder: './playwright-report', open: 'never' }],
    ['json', { outputFile: './report.json' }],
  ],
  workers: 1,
});
