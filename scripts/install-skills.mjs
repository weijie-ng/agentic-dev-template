#!/usr/bin/env node
// Pre-install the skills this repo relies on that ship via the Skills CLI
// (`npx skills add ...`), NOT as Claude Code plugins.
//
// Why this is separate from install-plugins.mjs: some tools are distributed as
// *skills*, not plugins. They have no `.claude-plugin/marketplace.json`, so
// `claude plugin marketplace add` rejects them and the Skills CLI
// (https://skills.sh) is their install path. Declaring them in
// .claude/settings.json -> enabledPlugins would only create a dangling plugin
// reference that never loads. no-ai-slop (github: petergyang/no-ai-slop) is one.
//
// Each skill is installed GLOBALLY (user scope) with --copy, so the real files
// land in $CLAUDE_CONFIG_DIR/skills (the ~/.claude volume the devcontainer
// persists) instead of being symlinked into an npx cache a rebuild wipes, and
// without dirtying the bind-mounted repo. A global skill loads in every session.
// This matches how install-plugins.mjs installs plugins at user scope: nothing
// third-party is committed to the repo; it is fetched at container-create.
//
// Idempotent: re-adding a skill overwrites it in place, so it is safe to re-run
// any time with `npm run setup:skills`. No Claude login needed (public clones).
import { execFileSync } from 'node:child_process';

// Skills to install. `package` is anything the Skills CLI `add` accepts
// (owner/repo, a URL, a registry name); `skill` is the skill name inside it.
const SKILLS = [
  { package: 'petergyang/no-ai-slop', skill: 'no-ai-slop' },
];

// The agent these skills install to. This template targets Claude Code.
const AGENT = process.env.SKILLS_AGENT || 'claude-code';

// `npx` resolves the Skills CLI without a global install; pin the tag so the
// command is reproducible. Network clone + copy; give it room past npx's fetch,
// matching the 300s the CLI-clone step in install-plugins.mjs allows.
const run = (pkg, skill) =>
  execFileSync(
    'npx',
    ['--yes', 'skills@latest', 'add', pkg, '--global', '--skill', skill, '--agent', AGENT, '--copy', '-y'],
    { stdio: 'inherit', timeout: 300_000 },
  );

if (SKILLS.length === 0) {
  console.log('[install-skills] no skills declared - nothing to do.');
  process.exit(0);
}

const failed = [];
for (const { package: pkg, skill } of SKILLS) {
  console.log(`[install-skills] skill: ${skill} (${pkg})`);
  try {
    run(pkg, skill);
  } catch (err) {
    failed.push(`${skill} (${pkg}): ${err.message}`);
  }
}

if (failed.length > 0) {
  // Non-fatal on purpose: a network hiccup during a container build should not
  // fail the build. Re-run cleanly with `npm run setup:skills`.
  console.error(`[install-skills] ${failed.length} skill(s) failed:`);
  for (const f of failed) console.error(`  - ${f}`);
  console.error('[install-skills] re-run with `npm run setup:skills` once the network is back.');
  process.exit(1);
}

console.log(`[install-skills] done - ${SKILLS.length} skill(s) present.`);
