# Repo setup: containerized Claude Code + always-latest tooling

This repo is set up so that **Claude Code, impeccable (design), and OpenSpec (spec-driven
workflow) all run inside a Docker dev container**, and the two tools **track their latest
published versions automatically**.

## How it runs — Claude Code is containerized

The `.devcontainer/devcontainer.json` installs the **Claude Code CLI inside the container**
via the official feature:

```jsonc
"features": { "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {} }
```

When you **Reopen in Container** and run `claude` in the container's integrated terminal,
Claude Code runs **inside the container** — every command it executes runs in the container,
and your edits appear in the bind-mounted repo on your host. Do all repo development from
inside the container.

## What's committed (the setup travels with the repo)

| Path | What it is |
|------|-----------|
| `.claude/skills/impeccable/` | Impeccable design skill + detector rules (runs from committed scripts) |
| `.claude/settings.local.json` | Impeccable design-detector hooks (portable, project-relative) |
| `.claude/skills/openspec-*/`, `.claude/commands/opsx/` | OpenSpec skills + `/opsx:*` commands |
| `openspec/` | OpenSpec specs, changes, and `config.yaml` |
| `package.json` + `package-lock.json` | OpenSpec CLI as a repo-local dependency + the `update:tools` script |
| `.devcontainer/devcontainer.json` | Dev container: installs Claude Code, runs `npm install`, auto-updates the tools on start |

## Version policy — always latest

Versions are **not pinned for the long term**; the setup pulls the newest versions:

- **On every container start**, `postStartCommand` runs `npm run update:tools`, which:
  1. `npm install @fission-ai/openspec@latest` — updates the OpenSpec CLI,
  2. `openspec update` — refreshes the generated `/opsx` files to match, and
  3. `npx --yes impeccable@latest update` — updates the impeccable skill to latest.
- It's a **no-op when everything is already current**, so it only changes files when there's
  a genuine update to adopt. Commit those changes to record the bump.
- **impeccable's CLI is inherently always-latest** because it runs via `npx impeccable@latest`.

> ⚠️ **npm date-cutoff on this machine.** This workspace's npm won't install packages
> published after ~2026-08-16, so `@latest` resolves to **OpenSpec 1.9.0** here even though
> **1.10.0 exists**. A normal machine without that cutoff will auto-update to 1.10.0 and
> beyond. Nothing to fix — it's an environment policy, not a repo setting.

> **Trade-off:** tracking latest means two machines built at different times may run
> different tool versions (freshness over strict lockstep). `package-lock.json` still records
> the exact versions each commit used, so any single checkout is reproducible.

## Recommended path: clone + dev container

1. Install **Docker Desktop**, **VS Code**, and the **Dev Containers** extension.
2. Clone this repo and open it in VS Code.
3. Command Palette → **Dev Containers: Reopen in Container**.
4. First build installs the **Claude Code CLI** and runs `npm install`; **each start** then
   auto-updates impeccable + OpenSpec to latest. `node_modules/.bin` is on the container
   `PATH`, so the bare `openspec` the `/opsx` skills call resolves to the repo-local CLI.
5. Run `claude` in a container terminal and sign in once — auth persists across rebuilds.

## Update the tools manually (any time)

```bash
npm run update:tools
```

Runs the same three steps as the container's auto-update. Use it on the host, or in the
container between restarts.

## Native alternative (no dev container)

1. Install **Node.js 18+** and **Claude Code**.
2. Clone the repo and run `npm install`.
3. The `/opsx` skills call a bare `openspec`. Either add `./node_modules/.bin` to your `PATH`
   (recommended), or run via `npm run openspec -- <args>` / `npx openspec <args>`.
4. Keep tools current with `npm run update:tools`.

## First-time git push (from the original machine)

```bash
git add -A
git commit -m "Add containerized Claude Code + auto-updating impeccable/OpenSpec setup"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```

Then on any new machine: `git clone <your-repo-url>` → **Reopen in Container**.
