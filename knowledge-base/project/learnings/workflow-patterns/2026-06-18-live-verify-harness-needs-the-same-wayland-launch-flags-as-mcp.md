---
title: "The live-verify harness needs the same Wayland Chrome launch flags as the MCP browser — buildLaunchOptions passed none"
date: 2026-06-18
category: workflow-patterns
module: apps/web-platform/scripts/live-verify
tags: [playwright, wayland, chromium, gpu, vulkan, live-verify, launch-flags, bd-prochot]
related: 2026-06-17-playwright-mcp-wayland-vulkan-launch-crash.md
---

# Learning: a Wayland GPU-crash fix applied to one Chrome launch site must be swept to every Chrome launch site

## Problem

The live-verify harness (`apps/web-platform/scripts/live-verify/run.ts`), run locally with
the system-browser override (`LIVE_VERIFY_BROWSER_PATH=/usr/bin/google-chrome`, #5485),
crashed mid-run on every attempt: `RESULT: CANT-RUN:<stage>: Target page, context or browser
has been closed` — different stage each time (waitForURL, fill). This is the **same**
Wayland/Vulkan GPU-process crash that [[2026-06-17-playwright-mcp-wayland-vulkan-launch-crash]]
fixed for the **MCP browser** the day before. That fix (commit fdc4a0895) added
`["--ozone-platform=x11", "--disable-gpu"]` to `.claude/playwright-mcp.config.json`, but the
live-verify harness has its own launch site (`buildLaunchOptions`) that passed **no args at
all** — so it never received the fix.

## Solution

Mirror the proven flags on the harness's override branches only:

```ts
const WAYLAND_STABILIZATION_ARGS = ["--ozone-platform=x11", "--disable-gpu"];
if (opts.executablePath) return { executablePath: opts.executablePath, args: WAYLAND_STABILIZATION_ARGS };
if (opts.channel)        return { channel: opts.channel,               args: WAYLAND_STABILIZATION_ARGS };
return {};  // no override → CI bundled-chromium path stays {} byte-identical
```

`--disable-gpu` is the load-bearing flag for the **headless** harness (it removes the
Vulkan/SwiftShader GPU process that crashes). `--ozone-platform=x11` is inert while headless
but kept for parity + headed local-debug use. Gating on override-presence keeps ubuntu-latest
CI (which has no X server for `--ozone-platform=x11`) byte-identical and unaffected.

## Key Insight

A host-environment fix (launch flags, sandbox toggles, env shims) applied to ONE process-spawn
site is not done until it is swept to EVERY spawn site of the same binary. `grep` the codebase
for all `chromium.launch(` / `browser.launchOptions` / `executablePath` sites when fixing a
browser-launch crash — the same Wayland host crashes them all, but each has its own options
object. The MCP config and the harness are independent launch sites; fixing one left the other
exposed for a day.

**Orthogonal hardware caveat:** after the crash fix, the harness still hit `CANT-RUN:forURL:
Timeout` locally — but that is the host's **BD_PROCHOT 400MHz CPU throttle** (see CC-memory
`reference_xps9320_bd_prochot_throttle`), not the fix: at 400MHz the app can't
hydrate→send→persist→navigate within the harness's 30s budget. The authoritative live PASS is
the CI `#5488` job (un-throttled ubuntu chromium). Distinguish the GPU crash (browser dies
mid-call) from the throttle timeout (browser alive, nav exceeds budget) before chasing the
wrong cause.

## Session Errors

- **Trailer-parse ship gate failed on a `Verified:` commit-body line** — a prose line starting
  `Verified: <text>` matched the gate's `^[A-Z][A-Za-z-]+:` trailer-candidate regex, but
  `git interpret-trailers` did not recognize it (prose, not a real trailer). Recovery:
  `git reset --soft <merge-base>` + recommit without the trailer-ambiguous line (`git rebase -i`
  is unavailable in this env). **Prevention:** never start a commit-body line with `Word:`
  unless it is an actual trailer (`Co-Authored-By:`, `Closes`-in-body excepted); use "Confirmed
  that…" / "Verified that…" prose instead of "Verified: …".
- **Squashing to fix the trailer line absorbed the `review:` commit**, dropping the ship
  review-evidence Signal 2. Recovery: added an `--allow-empty` `review:` marker commit (squashes
  away on merge). **Prevention:** when `reset --soft`-squashing a branch that carried a `review:`
  commit, re-add a `review:` marker so the ship gate still sees the evidence.

## Tags
category: workflow-patterns
module: apps/web-platform/scripts/live-verify
