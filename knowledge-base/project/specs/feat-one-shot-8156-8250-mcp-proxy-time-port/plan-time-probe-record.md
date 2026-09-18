# Phase-0 probe record — plugin-root `.mcp.json` Playwright MCP registration (#8156)

Date: 2026-09-18 · Branch: `feat-one-shot-8156-8250-mcp-proxy-time-port`
Probe host: Linux (Omarchy), `claude` at declared floor **2.1.139** (mise-installed
side-by-side) and installed **2.1.273**. Scratch plugin: `/var/tmp/probe-8156/scratch-plugin`
(manifest + `.mcp.json` + copied `skills/agent-browser/scripts/*.py`), scratch project:
`/var/tmp/probe-8156/proj`, scratch `HOME=/var/tmp/probe-8156/home` with a user-scoped
`playwright` (`npx @playwright/mcp@0.0.78`) pre-registered via `claude mcp add -s user`.

Scratch manifest under test (probe equivalent of planned T1.2):

```json
{ "mcpServers": { "playwright": { "command": "python3",
  "args": ["${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py",
           "--", "npx", "@playwright/mcp@0.0.78"] } } }
```

## Results

| Item | Verdict | Evidence |
|---|---|---|
| (a) `mcp__plugin_soleur_playwright__*` tools register at floor `>=2.1.139` | PASS | `claude --plugin-dir <scratch> mcp list` on **2.1.139** prints `plugin:soleur:playwright: python3 /var/tmp/probe-8156/scratch-plugin/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py -- npx @playwright/mcp@0.0.78 - ✓ Connected`. Same on 2.1.273. `mcp-logs-*/` jsonl records `hasTools:true`, serverVersion `Playwright 1.62.0-alpha-1783623505000`, stdio connect in 678ms. Tool namespace `mcp__plugin_soleur_playwright__*` follows the `plugin:<name>:<server>` naming (`plugin:soleur:playwright`). |
| (b) `${CLAUDE_PLUGIN_ROOT}` expands in plugin `.mcp.json` command/args | PASS | The `mcp list` command line shows the variable already resolved to the absolute scratch path (`/var/tmp/probe-8156/scratch-plugin/skills/...`) on both tested versions. |
| (c) user-scoped `playwright` + plugin `playwright` coexist | PASS | Both listed and connected simultaneously — `plugin:soleur:playwright` and `playwright` — no silent override, distinct namespaces. |
| (d) macOS/BSD launch argv sanity | PASS (logical) | argv = `python3 <abs-script> -- npx @playwright/mcp@0.0.78` — no shell wrapper, no POSIX-shell syntax, no Linux-isms; `python3`/`npx` resolve via PATH identically on macOS. On macOS `XDG_CACHE_HOME` is normally unset → the T1.1 flag resolves `~/.cache/...` (its designed fallback). Not hardware-verified; recorded honestly. |
| (e) connect-failure playbook log dir | MEASURED | `~/.cache/claude-cli-nodejs/<cwd-slug>/mcp-logs-plugin-soleur-playwright/*.jsonl` (cwd slug = absolute project path with `/`→`-`). Note: the cache root follows the OS account home, not the `HOME` env var — logs landed in the real `~/.cache` during scratch-HOME runs. Server stderr lines (e.g. proxy refusal) appear as `Server stderr:` records in the jsonl. |
| (5) orphan-on-own-profile (user-impact Finding 1) | REFUTED on this platform | See below. |

## Item 5 — SIGKILL / orphan-reaping measurement

Setup: real TUI session (`script -qec "claude --plugin-dir <scratch>"`) with the plugin
server live; `playwright-mcp` child pid observed under the claude process group.

1. `kill -9 <claude pid>` → `playwright-mcp` child gone in **<0.7s** (stdio MCP servers
   exit on stdin EOF; Claude Code need not reap). Clean-exit path also verified in logs:
   `Sending SIGINT to MCP server process` → `MCP server process exited cleanly`.
2. Browser hold: drove `browser_navigate` over stdio directly against
   `npx @playwright/mcp@0.0.78 --user-data-dir=/var/tmp/probe-8156/profile
   --executable-path=/usr/bin/chromium --headless` → chromium pid holds profile
   `SingletonLock` (symlink `omarchy-<pid>`).
3. stdin EOF (the post-SIGKILL path) → playwright-mcp exits, **all chromium processes
   reaped**, but `SingletonLock`/`SingletonSocket`/`SingletonCookie` files remain stale.
4. Second launch on the same profile with a dead-pid `SingletonLock` → `browser_navigate`
   succeeds immediately; lock re-points to the new pid. **Stale locks are self-healing**
   (Chrome pid-liveness check) — no contention.
5. Deeper shape (OOM-reaper analog): `kill -9 <playwright-mcp node pid>` while Chrome
   holds the profile → chromium **still reaped** (playwright child-death signal), stale
   lock again harmless.

Conclusion: the orphan-on-own-profile failure mode does not occur end-to-end on
Linux/Chromium 152 — no live process survives to hold the profile, and stale lock files
are taken over on the next launch. Per the plan's conditional, the stale-profile symptom
is **not** added to the connect-failure playbook; the measured evidence lives here.

## Incidental observations

- The proxy's sibling drift guard fired during the probe (`refusing to start: sibling
  redact-a11y-snapshot.py is missing (drifted plugin install?)`) — CONNECTION_CLOSED with
  the refusal line visible in `Server stderr:` of the plugin mcp-log. Good diagnostic
  surface; the same log location is what the playbook documents.
- `plugin.json` keeps `engines.claude-code >=2.1.139` — **no bump required** (AC10:
  manifest unchanged).

## What this does not cover

- Tool-name enumeration inside a live session (`mcp__plugin_soleur_playwright__browser_*`)
  — inferred from the `plugin:soleur:playwright` registration + `hasTools:true`; the
  exact `mcp__plugin_<plugin>_<server>__<tool>` naming is the platform convention.
- macOS hardware run (item d is a shape check, not an execution).
