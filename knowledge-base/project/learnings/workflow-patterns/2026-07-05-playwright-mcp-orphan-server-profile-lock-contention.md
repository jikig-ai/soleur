---
title: "Playwright-MCP flakiness (`Target page/context/browser has been closed`) — orphaned servers contending for one shared profile"
date: 2026-07-05
tags: [playwright-mcp, browser-automation, agent-native, reliability, credential-handoff, soleur-web]
category: workflow-patterns
---

# Playwright-MCP `Target … has been closed` — a SECOND root cause: orphaned-server profile-lock contention

## Symptom

During a credential-handoff (GitHub PAT mint), Playwright MCP tore the page down on **every
1–2 tool calls** with `browserBackend.callTool: Target page, context or browser has been
closed`. `browser_navigate` always succeeded; the *next* call (snapshot/evaluate/click) failed.
Freeing memory did not help.

## This is a DIFFERENT cause from the known Wayland/Vulkan crash

`.claude/playwright-mcp.config.json` already documents + mitigates a Wayland/Vulkan GPU crash
that produces the **same error string** (`--disable-gpu --ozone-platform=x11`, learning
`2026-06-17-playwright-mcp-wayland-vulkan-launch-crash.md`). That mitigation was working. The
same string has (at least) two independent causes — do not assume the config already covers it.

## Actual root cause (evidence-based, not memory)

- `free -h`: 13 GiB available, no OOM. The `OOM killer disabled/enabled` kernel lines are
  **suspend/resume artifacts**, not kill events — there was no `Killed process … chrome`.
- `ps`: **15 `playwright-mcp` server processes alive**, the oldest **>28h old**, ALL launched
  with the same `--user-data-dir=$HOME/.cache/playwright-mcp-profile` and config `isolated:
  false`. Two separate Chrome trees were running against that one profile.
- Chrome enforces a **single-instance `SingletonLock` per profile**. Multiple MCP servers
  contending for one profile → whenever a tool call lands on a server whose Chrome is not the
  current lock-holder (or a newer server steals the profile), the active page's context is torn
  down → the observed error.
- **Why it accumulated:** every session restart / `Reconnected to playwright` spawns a NEW
  server but never reaps the old one. Over a day+, 15 piled up, all clawing at one profile.

## Fix applied (`.mcp.json`)

Wrapped the launch in a reaper that, before starting, kills any prior `playwright-mcp` server +
Chrome **bound to this profile** and clears stale `Singleton*` locks, then `exec`s the real
server — guaranteeing **one instance per profile** while preserving the persistent-login
profile the credential-handoff workflow needs. Also switched the hardcoded `/home/jean` to
`$HOME` (the literal path was wrong for any other operator).

```
"command": "bash",
"args": ["-c", "prof=$HOME/.cache/playwright-mcp-profile; pkill -9 -f \"[b]in/playwright-mcp .*$prof\" …; pkill -9 -f \"[c]hrome.*$prof\" …; rm -f \"$prof\"/Singleton* …; exec npx @playwright/mcp@latest --user-data-dir=$prof --config=.claude/playwright-mcp.config.json"]
```

Note the `[b]in` / `[c]hrome` **bracket trick** — `pkill -f` scans its own caller's command
line, so an un-bracketed pattern self-matches and SIGKILLs the shell mid-command (this bit us
twice during the live cleanup: the sweep truncated at 15→2 before the pattern was bracketed).

## The Soleur-web lesson (why this matters beyond one laptop)

A **shared, fixed, non-isolated browser profile is the wrong model for agent-driven browsers**
that reconnect/restart — it produces this flakiness at any scale, and the web/Concierge product
runs agent-driven browsers for tenants. Two clean variants, pick by requirement:

- **`isolated: true` / ephemeral per-session `--user-data-dir`** — no shared lock to contend;
  cost is login does not persist across sessions. **Right for stateless tenant automation.**
- **Reap-on-launch (this fix)** — single instance per profile, persistent login preserved.
  **Right for the persistent-login credential-handoff workflow.** Trade-off: only one Playwright
  session per profile at a time (concurrent sessions need the isolated variant).

## Operational note

Immediate recovery when it is already happening: `pkill -9 -f '[b]in/playwright-mcp'` +
`pkill -9 -f '[c]hrome.*playwright-mcp-profile'` + `rm -f <profile>/Singleton*`, then reconnect
once → a single clean instance. Chrome children that survive SIGKILL are defunct/`D`-state and
hold no lock once the profile locks are gone.
