#!/usr/bin/env node
// Update impeccable + the OpenSpec CLI to the NEWEST versions that are at least
// DELAY_DAYS old. This reproduces, inside the dev container, the host environment's
// "a package must be N days old before we install it" policy. Without this, npm in
// the container hits the live registry and would grab same-day releases.
//
// Mechanism: npm (and npx) honor the `before` setting via the `npm_config_before`
// environment variable — it constrains version resolution to versions published
// on or before that timestamp. We scope it to these child processes only, so no
// global or user ~/.npmrc is modified.
import { execSync } from 'node:child_process';

// Days a package must have been published before we install it. Override with the
// TOOL_UPDATE_DELAY_DAYS env var; defaults to 7 (mirrors the host's package-age policy).
const DELAY_DAYS = Number(process.env.TOOL_UPDATE_DELAY_DAYS) || 7;
const before = new Date(Date.now() - DELAY_DAYS * 24 * 60 * 60 * 1000).toISOString();

const env = { ...process.env, npm_config_before: before };
const run = (cmd) => execSync(cmd, { stdio: 'inherit', env });

console.log(`[update-tools] ${DELAY_DAYS}-day delay — installing versions published on/before ${before}`);

try {
  // 1. OpenSpec CLI (repo-local dependency). @latest + the `before` cutoff resolves
  //    to the newest version that is already at least DELAY_DAYS old.
  run('npm install @fission-ai/openspec@latest');
  // 2. Refresh OpenSpec's generated project files to match the installed CLI (no-op if current).
  run('openspec update');
  // 3. Update the impeccable skill (no-op if current).
  run('npx --yes impeccable@latest update');
  console.log('[update-tools] done.');
} catch (err) {
  console.error('[update-tools] update step failed:', err.message);
  process.exit(1);
}
