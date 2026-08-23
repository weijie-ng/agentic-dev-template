#!/usr/bin/env bash
# Install Google Chrome (stable) so the `chrome-devtools` MCP server (../.mcp.json)
# can drive a real browser in this container.
#
# Why a *system* Chrome, not the cached Chrome for Testing: chrome-devtools-mcp
# (v1.7) resolves the browser by channel — for the default "stable" channel it looks
# for a system install at /opt/google/chrome/chrome. It does NOT fall back to the
# Chrome for Testing that puppeteer/impeccable download under ~/.cache/puppeteer, so
# we install the officially-supported Google Chrome at that stable, version-agnostic
# path. Installing the .deb also pulls in Chrome's runtime libraries (libnss3,
# libnspr4, libgbm1, ...), which the slim base image otherwise lacks — so this single
# step covers both the browser and its OS dependencies.
#
# Runs from devcontainer.json's postCreateCommand (on build/rebuild), and is
# idempotent, so it is also safe to run by hand at any time:
#   bash .devcontainer/install-chrome.sh
#
# WSL2 note: this container has unprivileged user namespaces disabled, so Chrome
# cannot use its sandbox. That is handled in .mcp.json via --chromeArg=--no-sandbox
# (not here) — this script only provides the browser.
set -euo pipefail

if [ -x /opt/google/chrome/chrome ]; then
  echo "[install-chrome] Google Chrome already installed ($(/opt/google/chrome/chrome --version 2>/dev/null | head -1)) — skipping."
  exit 0
fi

# Google publishes the Chrome .deb for amd64 only; on other arches, install a
# Chromium yourself and point .mcp.json at it via --executablePath.
arch="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
if [ "$arch" != "amd64" ]; then
  echo "[install-chrome] Architecture '$arch' is not amd64; Google Chrome's .deb is amd64-only."
  echo "[install-chrome] Install a Chromium/Chrome manually and add --executablePath=<path> to .mcp.json."
  exit 0
fi

echo "[install-chrome] Adding Google's apt repository…"
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
  | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
  | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null

echo "[install-chrome] Installing google-chrome-stable (browser + its OS libraries)…"
sudo apt-get update -qq
sudo apt-get install -y google-chrome-stable

echo "[install-chrome] done — $(/opt/google/chrome/chrome --version 2>/dev/null | head -1)"
