---
title: "Playwright's browser install stalls under Node 26 and completes under Bun"
date: 2026-11-09
category: integration-issues
tags: [playwright, node-26, bun, browser-install, yauzl, mcp, live-verify]
module: plugins/soleur/skills/agent-browser
---

# Learning: Playwright's browser install stalls under Node 26 and completes under Bun

## Problem

On a host running Node 26 (observed on 26.12.1 and 26.13.0), installing a Playwright browser hangs after the download is done. The progress bar reaches 100%, then the process sits at 0% CPU and never exits. What was observed on disk: the first large archive entry was never created, and `LICENSE` was truncated at 1.65 MB. The stall is in the zip extraction step (Playwright's bundled extractor, `yauzl`), not in the download.

This is the cause as observed, not root-caused upstream: the only evidence is the same install behaving differently under two runtimes.

The owner attributes the repeated "browser missing" reports (the MCP browser and the live-verify headless shell, across the earlier origin-TLS sessions) to this cause; that is the owner's finding in the session that produced this note, not something recorded on PR #12434, whose comments and review do not mention it. An install that never finished leaves the browser missing at the next launch.

CI is not affected: `web-platform-release.yml` uses Node 22.

## Solution

Run the same install under Bun, which completed in under 2 minutes:

- `bunx --bun playwright install <browser>`
- `bunx --bun @playwright/mcp@0.0.78 install-browser chromium` (the owner's brief also used the target `chrome-for-testing`; the pinned CLI maps `install-browser` to `install` and passes the target through, and only `chromium` is what the repo notes use)

The repo pins `@playwright/mcp@0.0.78` in `.mcp.json`. That version wants Chrome 151 (`chromium-1232`), not the revision that the newer `0.0.85` package would fetch, so keep the pinned form (see `2026-03-20-playwright-shared-cache-version-coupling.md`: revisions in the shared `~/.cache/ms-playwright` are exact-match).

A manual route also works when no Bun is available: download the archive, `unzip` it into `~/.cache/ms-playwright/<revision directory>`, and create an empty `INSTALLATION_COMPLETE` marker file in that directory so Playwright treats the install as finished.

Both repo places that tell a reader how to install a browser now carry a note to use `bunx --bun` on Node 26 (the qa preflight runs it from `apps/web-platform`, where `bunx` resolves the local `playwright`; the agent-browser note uses the pinned MCP form): `plugins/soleur/skills/agent-browser/SKILL.md` and `plugins/soleur/skills/qa/references/browser-preflight.md`.

## Key Insight

A "browser is missing" failure that comes back after a re-install is a signal to check that the install finished, not to try another browser flag. A silent hang at 100% download with 0% CPU is an extraction stall; compare the extracted directory against the archive before retrying the same command. When one runtime stalls and another finishes the identical command, switch runtime for that step and record the observation without claiming a cause.

## Session Errors

1. **A browser install under Node 26 stalled at 100% download with 0% CPU.** Recovery: re-ran the identical install under Bun, which finished in under 2 minutes. Prevention: the one-line notes in the two install guidance files above.
