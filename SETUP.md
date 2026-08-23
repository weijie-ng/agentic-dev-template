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
| `.claude/settings.json` | Project env + status line + `enabledPlugins` (the Claude Code plugin set this repo expects) |
| `.claude/settings.local.json` | Impeccable design-detector hooks (portable, project-relative) |
| `.claude/skills/openspec-*/`, `.claude/commands/opsx/` | OpenSpec skills + `/opsx:*` commands |
| `openspec/` | OpenSpec specs, changes, and `config.yaml` |
| `package.json` + `package-lock.json` | OpenSpec CLI as a repo-local dependency + the `update:tools` script |
| `.devcontainer/devcontainer.json` | Dev container: installs Claude Code, runs `npm install`, auto-updates the tools on start |
| `.mcp.json` | Chrome DevTools MCP server (`chrome-devtools`), configured headless + sandbox-less for the container |
| `.devcontainer/install-chrome.sh` | Installs Google Chrome (+ its OS libraries); run from `postCreateCommand` |

## Version policy — latest, but with a 7-day delay

Versions are **not pinned long-term**; the setup pulls the newest versions that are **at
least 7 days old**. That delay mirrors the host environment's package-age policy and avoids
adopting a same-day release before it has settled.

- **On each container (re)build**, `postCreateCommand` runs `npm run update:tools`, which runs
  `scripts/update-tools.mjs`. (It runs on rebuild rather than every start so container startup
  stays fast and quiet; run it yourself any time with `npm run update:tools`.) That script:
  1. computes `before = now − 7 days` and sets `npm_config_before` for its child processes
     (so npm/npx only resolve versions published on or before that cutoff),
  2. `npm install @fission-ai/openspec@latest` — newest OpenSpec CLI ≥ 7 days old,
  3. `openspec update` — refreshes the generated `/opsx` files to match, and
  4. `npx --yes impeccable@latest update` — newest impeccable skill ≥ 7 days old.
- It's a **no-op when everything is already current**, so it only changes files when there's
  a genuine update to adopt. Commit those changes to record the bump.
- The `before` cutoff is scoped to the script's child processes only — it does **not** modify
  any global or user `~/.npmrc`.

> **How the delay is enforced:** npm honors the `before` setting via the `npm_config_before`
> environment variable, constraining version resolution to releases published on/before that
> timestamp. Verified: with `before=2026-07-15`, `@latest` resolves to `1.6.0`; with the live
> cutoff it resolves to `1.9.0`. The window rolls forward automatically as time passes.

> **On the original (host) machine**, npm *also* enforces its own ~7-day registry cutoff, so
> `@latest` there is capped at **OpenSpec 1.9.0** (1.10.0 exists but is younger than 7 days).
> The container now applies the same 7-day rule itself, so both environments behave the same.

> **Trade-off:** tracking latest means two machines updated at different times may run
> slightly different tool versions (freshness over strict lockstep). `package-lock.json` still
> records the exact versions each commit used, so any single checkout is reproducible.

## Recommended path: clone + dev container

1. Install **Docker Desktop**, **VS Code**, and the **Dev Containers** extension.
2. Clone this repo and open it in VS Code.
3. Command Palette → **Dev Containers: Reopen in Container**.
4. Each build **chowns the `~/.claude` volume to the `node` user** (so credentials and
   transcripts can be written), installs the **Claude Code CLI**, runs `npm install`, and
   auto-updates impeccable + OpenSpec (7-day delay). `node_modules/.bin`
   is on the container `PATH`, so the bare `openspec` the `/opsx` skills call resolves to the
   repo-local CLI.
5. Run `claude` in a container terminal and sign in once — auth persists across rebuilds.

### Troubleshooting: login isn't remembered / `EACCES` transcript writes

Both symptoms mean the `node` user can't write to the `~/.claude` volume (it's root-owned
until chowned). If you hit this in an **already-running** container (built before this fix),
run once in the container terminal, then sign in again:

```bash
sudo chown -R node:node /home/node/.claude
```

Rebuilding the container applies the fix automatically (it's in `postCreateCommand`). If the
browser sign-in completes but the container never receives the callback, copy the code shown
in the browser and paste it at the `Paste code here if prompted` prompt.

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

## Chrome DevTools MCP server (browser automation)

`.mcp.json` registers the [`chrome-devtools`](https://github.com/ChromeDevTools/chrome-devtools-mcp)
MCP server (project scope, so it travels with the repo like the other tooling). It lets Claude
Code drive a real Chrome — navigate, inspect the DOM/network, run performance traces, screenshot.

It's configured for this headless Linux container:

- `--headless` — no display in the container.
- `--isolated` — a throwaway Chrome profile that's cleaned up on exit.
- `--chromeArg=--no-sandbox --chromeArg=--disable-setuid-sandbox` — **required here.** WSL2
  disables unprivileged user namespaces, so Chrome's sandbox can't start; without these flags
  Chrome aborts with *"No usable sandbox!"*.

On (re)build, `postCreateCommand` runs `.devcontainer/install-chrome.sh`, which installs
**Google Chrome and its OS libraries** (the slim base image ships neither). A *system* Chrome
is what the server needs: chrome-devtools-mcp resolves the browser by channel, and the default
`stable` channel looks for a system install at `/opt/google/chrome/chrome` — it does **not**
fall back to the Chrome for Testing that puppeteer caches. The script is idempotent, so you can
run it by hand any time: `bash .devcontainer/install-chrome.sh`.

> Trust prompt: because `.mcp.json` is project-scoped, Claude Code asks you to approve the
> server the first time you open the project in the container. Approve it once.

## Claude Code plugins (reproducible tooling)

The Claude Code plugins this repo uses are pinned in `.claude/settings.json` under
`enabledPlugins` (all from the official `claude-plugins-official` marketplace, which Claude
Code makes known to every user automatically). That declaration is what travels with the repo.

There's no install step to run: when you open the repo and start `claude`, Claude Code
provisions the enabled plugins from the marketplace on session start — it downloads any that are
missing into its plugin cache and loads them (the first launch may pause briefly while it
fetches them). `.claude/settings.json` is the single source of truth for the set.

**Reproducible vs. per-user:** the plugin *set* travels with the repo. Plugins that expose
authenticated HTTP MCP servers — `github`, `vercel`, `context7` — still need **each user to
sign in once** (run `/mcp` in Claude Code and authenticate; credentials are stored per-user in
`~/.claude`, never committed). `playwright` and `chrome-devtools` are local and need no sign-in.

## GitHub auth: keep credentials on the host and forward them

**No credentials are stored in the container** (best practice). Your host authenticates to
GitHub via **Git Credential Manager** over HTTPS; the dev container borrows that per push.
Nothing is installed or persisted in the container for auth.

### Method 1 — VS Code HTTPS credential forwarding (recommended, zero setup)

VS Code Dev Containers automatically forwards your host git credentials into the container's
integrated terminal. Because the host already uses Git Credential Manager and the remote is
HTTPS, this works out of the box:

1. Open the repo in the container (**Reopen in Container**).
2. In the **VS Code integrated terminal** (this is where the forwarding is active — Claude
   Code launched from that terminal inherits it), just run `git push` / `git pull`.

The host's GCM answers the credential request; no token ever lands in the container.

### Method 2 — SSH agent forwarding (editor-independent alternative)

Keeps the private key on the host and forwards the running `ssh-agent` into the container:

1. On the host, make sure the key you use for GitHub is loaded: `ssh-add -l` (add it to your
   GitHub account if it isn't already), and the OpenSSH agent service is running.
2. Point this repo at the SSH remote:
   ```bash
   git remote set-url origin git@github.com:weijie-ng/digital-garden.git
   ```
3. VS Code forwards the agent automatically; `git push` in the container uses it. Works in any
   container terminal, not just VS Code's.

### Fallback — push from the host

Develop/run in the container, and run `git push` / `git pull` from a host terminal (already
authed as `weijie-ng`). Nothing enters the container at all.

> The GitHub **MCP server** is separate from git auth: forwarding credentials for `git push`
> does not give an MCP server a token. If you need the GitHub MCP inside the container, pass a
> token to it via an env var; otherwise run those GitHub-API actions from the host.

## First-time git push (from the original machine)

```bash
git add -A
git commit -m "Add containerized Claude Code + auto-updating impeccable/OpenSpec setup"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```

Then on any new machine: `git clone <your-repo-url>` → **Reopen in Container**.
