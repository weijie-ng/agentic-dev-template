#!/usr/bin/env node
// Pre-install every plugin this repo pins in .claude/settings.json → enabledPlugins.
//
// Why this exists: `enabledPlugins` only says "turn these on". It does NOT guarantee
// the plugin is on disk. On a fresh clone (or a fresh ~/.claude volume) Claude Code
// clones the marketplace and fetches the plugins in the BACKGROUND while the session
// is already starting — so an early session, or a /reload-plugins that fires mid-fetch,
// loads only the plugins that happen to have landed and reports the rest as errors.
// The larger plugins (superpowers, vercel) lose that race most often.
//
// Running this at container-create time makes the fetch happen BEFORE Claude Code ever
// starts, so the first session sees all plugins present. It is idempotent: an
// already-installed plugin is a no-op, so it is safe to re-run any time.
//
// No Claude login is needed — marketplaces are plain public git clones.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const settingsPath = join(repoRoot, '.claude', 'settings.json');

// `claude` is installed by the devcontainer feature; allow an override for other setups.
const CLI = process.env.CLAUDE_CLI || 'claude';

// Marketplace clones and plugin downloads hit the network; the CLI's own clone timeout
// is 120s, so give each call room beyond that rather than killing it mid-clone.
const run = (args) =>
  execFileSync(CLI, args, { stdio: 'inherit', timeout: 300_000, cwd: repoRoot });

let settings;
try {
  // Claude Code allows // comments in settings.json; this repo's file has them.
  const raw = readFileSync(settingsPath, 'utf8').replace(/^\s*\/\/.*$/gm, '');
  settings = JSON.parse(raw);
} catch (err) {
  console.error(`[install-plugins] cannot read ${settingsPath}: ${err.message}`);
  process.exit(1);
}

// A marketplace must be known before its plugins can be installed. The built-in
// `claude-plugins-official` is known by default, but a fresh config has not CLONED it
// yet — `marketplace add` is what pulls it down, and is a no-op once present.
const marketplaces = settings.extraKnownMarketplaces ?? {};
const plugins = Object.entries(settings.enabledPlugins ?? {})
  .filter(([, enabled]) => enabled)
  .map(([id]) => id);

if (plugins.length === 0) {
  console.log('[install-plugins] no enabled plugins declared — nothing to do.');
  process.exit(0);
}

const failed = [];

for (const [name, entry] of Object.entries(marketplaces)) {
  // `marketplace add` takes the SOURCE (repo/url/path), not the marketplace name.
  const src = entry?.source ?? {};
  const source = src.repo ?? src.url ?? src.path;
  if (!source) {
    console.warn(`[install-plugins] skipping marketplace "${name}": unrecognized source`);
    continue;
  }
  console.log(`[install-plugins] marketplace: ${name} (${source})`);
  try {
    run(['plugin', 'marketplace', 'add', source, '--scope', 'user']);
  } catch (err) {
    failed.push(`marketplace ${name}: ${err.message}`);
  }
}

for (const id of plugins) {
  try {
    // -y accepts marketplace-declared install commands without a prompt, which is
    // required here because postCreate has no TTY.
    run(['plugin', 'install', id, '--scope', 'user', '-y']);
  } catch (err) {
    failed.push(`plugin ${id}: ${err.message}`);
  }
}

if (failed.length > 0) {
  // Non-fatal on purpose: a network hiccup during a container build should not fail the
  // build. Claude Code will still try to fetch what is missing, and `npm run
  // setup:plugins` re-runs this cleanly.
  console.error(`[install-plugins] ${failed.length} step(s) failed:`);
  for (const f of failed) console.error(`  - ${f}`);
  console.error('[install-plugins] re-run with `npm run setup:plugins` once the network is back.');
  process.exit(1);
}

console.log(`[install-plugins] done — ${plugins.length} plugin(s) present.`);
