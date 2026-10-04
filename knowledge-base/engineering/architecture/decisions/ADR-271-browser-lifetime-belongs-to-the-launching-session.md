---
title: Browser lifetime belongs to the launching session
status: adopting
date: 2026-10-04
supersedes: none
issue: none
related: [9281, 8156, 7980, 7947]
related_adrs: [ADR-213, ADR-093]
tags: [playwright, mcp, hooks, browser, process-lifetime, claude-code]
brand_survival_threshold: aggregate pattern
---

# ADR-271: Browser lifetime belongs to the launching session

## Status

**Adopting — 2026-10-04.** Flips to `accepted` when the live check in "Proven and not proven" passes after a full Claude Code
restart with the fixed plugin loaded. The merge of the PR that carries this ADR does not by itself establish that check, so the
decision is recorded `adopting`, not `accepted` (the ADR-270 precedent).

## Context

The Playwright MCP browser disappeared by itself within tens of seconds of launch. The next tool call returned
`browserBackend.callTool: Target page, context or browser has been closed` until `browser_close` forced a fresh backend. The
working theory in the request was the server's ping heartbeat (`PLAYWRIGHT_MCP_PING_TIMEOUT_MS`). It is refuted below. The
cause is a plugin `Stop` hook.

### What a `Stop` hook is, and what this one did

`plugins/soleur/hooks/hooks.json` registered `browser-cleanup-hook.sh` on the `Stop` event. `Stop` fires when the assistant
finishes a turn, not when the session exits; the 2026-04-03 learning that created the hook assumed the opposite, and that
assumption is the root error. The script runs `pgrep -f 'chrome.*--remote-debugging-pipe'` with no owner or session filter and
sends SIGTERM to every match. It can only signal processes of the invoking user, so the blast radius is every Playwright Chrome
of that user on the machine, across every concurrent session. SIGTERM makes Chrome exit gracefully (exit 0, no core dump), which
is why the window and the process vanish together and the failure looks like "idle" rather than a kill.

Re-derived on 2026-10-04 with these commands (the read-only checks that would falsify each statement):

- Registration: `git show fa8bc5961f:plugins/soleur/hooks/hooks.json | jq -c '.hooks.Stop[].hooks[].command'` listed three commands
  (`stop-hook.sh`, `browser-cleanup-hook.sh`, `unkept-promise-hook.sh`) before the fix.
- It is the only registered command that signals processes by pattern: `grep -nE '\bkill\b|pkill|killall|pgrep'
  plugins/soleur/hooks/*.sh plugins/soleur/hooks/lib/*` matched executable code only in `browser-cleanup-hook.sh`; the project
  and user `settings.json` files register no `Stop` or `SessionEnd` hook (`jq` over both). This searched the plugin tree as well as
  the settings files; an earlier pass in the session searched only the settings files and missed the plugin hook entirely.
- The loaded plugin copy carries it: `~/.claude/plugins/installed_plugins.json` lists `soleur@soleur` at user scope with an
  `installPath` under `~/.claude/plugins/cache/soleur/soleur/`, and that copy's `hooks.json` registers the same hook.
- Correlation: 15 "Target page, context or browser has been closed" results are in that day's MCP log (`grep -c` gives 30 matching
  lines, two per failure). The session transcripts carry `Browser cleanup: killed N orphaned Playwright Chrome process(es)`
  lines, stored as `hook_success` attachments with `hookEvent` `Stop` (the string also appears in quoted text, which is not an event):
  18 events on 2026-10-04, from 5 sessions. For each failure, the window runs from the
  previous successful tool completion to the failure's own timestamp. **14 of 15 failures have at least one hook kill, from any
  session, inside their window.** The 15th failed 3 s into a call, and its nearest kill is stamped 26 ms after the failure
  (transcript attachments are written after the hook runs, so that ordering is not resolvable); it is counted as not matching.
  The method is in the learning.

### The refuted theory

`@playwright/mcp` 0.0.78 and 0.0.83 start the heartbeat only on the streamable-HTTP session path. In `coreBundle.js` the stdio
branch of `start()` (`options.port === void 0`) calls `connect(serverBackendFactory, transport, Promise.resolve(), false)`; the
`runHeartbeat` argument is `true` only on the HTTP session path. Checked in both versions with
`grep -nE 'connect\(serverBackendFactory' ~/.npm/_npx/*/node_modules/playwright-core/lib/coreBundle.js`. Every registration in
this repository is stdio. The failure shape also contradicts a heartbeat close: after `server.close()` a stdio server stops
reading stdin, so a later call would hang rather than return a tool-level "Target page ... closed".

The published statement "the heartbeat is the likely cause" was made before this source read. It was wrong.

### Two secondary defects found on the way

- The project `.mcp.json` launch string ran a three-pattern `pkill -9 -f` (proxy, `bin/playwright-mcp`, `chrome.*$prof`) at every
  server start and every `/mcp` reconnect. That is a second pattern killer, and it is cross-session by construction. Its purpose
  (one live owner per profile, from the 2026-07-05 orphan-server learning) is kept; its means is replaced.
- `plugins/soleur/.mcp.json` passes no `--browser`, so Playwright defaults the channel to `chrome` and fails with "Chromium
  distribution 'chrome' is not found at /opt/google/chrome/chrome" on a host without Google Chrome. Reproduced live on this host;
  `--browser chromium` launches the bundled `chromium-1232` and `browser_navigate about:blank` succeeds.

## Decision

1. **No hook or launcher terminates browser processes by name or command-line pattern.** The `Stop` hook, its `hooks.json`
   entry, and its mirrors in the registry, ledger and parity test are deleted. A Guard-1 scan over every command in `hooks.json`
   (every event, the scripts they invoke) and both `.mcp.json` launch strings keeps it that way, with a live decoy as positive
   control.
2. **A browser's lifetime belongs to the process tree of the session that launched it.** Three mechanisms already on `main` end
   a browser when its launcher goes away: Chrome exits when its `--remote-debugging-pipe` closes, the proxy ends the child's
   whole process group on stdin EOF or a signal (`Proxy.teardown`), and Playwright's own watchdog closes browsers on stdin
   close. They are sufficient on their own, including when the proxy cannot run its teardown: the proxy was SIGKILLed after a
   successful headless `browser_navigate`, and every descendant (npm exec, node server, Chrome main and its renderer, zygote, gpu
   and utility processes) was gone within 0.04 s in each of three runs, Chrome first. The driver is the scratchpad probe named in
   the learning; it ran headless bundled Chromium on a temporary profile and touched only descendants of the proxy it spawned.
   Headed real Chrome was not probed. A hook that tries to add a backstop therefore buys nothing and, because `Stop` fires every
   turn, closes the user's own live browser each turn.
3. **For this repository's own registration only, profile ownership is a kernel `flock` lease, not a pattern kill.** The launch
   string sources `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh`, which claims slot 0 (the
   persistent `~/.cache/playwright-mcp-profile`) or slots 1..31 by a non-blocking `flock` held on fd 9 by the proxy for the
   server's lifetime; the kernel releases it on any exit, including SIGKILL. A slot whose `SingletonLock` names a live pid is
   skipped, never cleared; one naming a dead pid is cleared. Slot 0 alone waits up to 7 s so that a `/mcp` reconnect (whose old
   proxy holds the lock for up to its 5 s grace) lands back on the persistent profile and keeps its logins. No `flock`, an
   unsupported filesystem or 32 busy slots fall back to a unique `$base-$$` directory with a stderr note; nothing blocks and
   nothing is killed.
4. **The plugin registration gets a conditional bundled-Chromium fallback, in the proxy.** The proxy gains an opt-in boolean flag
   `--chromium-fallback` (before `--`). With it set, no `--browser` in the server argv, `PLAYWRIGHT_MCP_BROWSER` unset and no
   Google Chrome executable at the platform path, the proxy appends `--browser chromium`, which Playwright maps to the bundled
   `chrome-for-testing`. Elsewhere the check is a no-op. Flag absent, the child argv is byte-identical to before. No credential
   guarantee moves: `--browser` is not a sink flag and `--executable-path` stays refused (ADR-213 addendum, 2026-10-04).
5. **`PLAYWRIGHT_MCP_PING_TIMEOUT_MS=0` is added to both registrations as an inert latent-hazard guard, and is not the fix.** It
   does nothing on stdio in 0.0.78 or 0.0.83. It is kept because the proxy answers any server-originated `ping` with JSON-RPC
   -32601 (`relay_server_message` relays only `roots/list`), so a future `@playwright/mcp` that starts the heartbeat on stdio would
   have `server.ping()` fail at once and `server.close()` the browser. Value 0 returns before the heartbeat starts
   (`startHeartbeat` begins `const timeout = pingTimeout(); if (timeout <= 0) return;`, present in both versions). The pin-bump
   checklist gains "re-verify the heartbeat is not started on stdio". Making the proxy answer `ping` is a separate, tracked change.

## Proven and not proven

**Proven** (commands above):

- The `Stop` hook SIGTERMs every Playwright Chrome of the invoking user at the end of every turn.
- 14 of 15 observed failures on 2026-10-04 have a hook kill, from any session, inside their window.
- The heartbeat cannot be the cause on stdio in 0.0.78 or 0.0.83, because the stdio transport passes `runHeartbeat=false`.
- With the proxy SIGKILLed, no browser descendant outlives it (headless bundled Chromium, three runs, 0.04 s).
- Without `--browser chromium`, the plugin registration cannot launch a browser on a host with no Google Chrome.

**Not proven:**

- **Live idle survival after the fix.** It needs a full Claude Code restart, not a `/mcp` reconnect (a reconnect reuses the cached
  `.mcp.json` command and does not reload hooks), then a navigation followed by more than 60 s idle across at least three
  assistant turns, in this session and in one parallel session, then a successful snapshot, and `grep -c "Browser cleanup:
  killed"` on the new transcript equal to 0. Until that passes, this ADR stays `adopting`.
- **That the machine's loaded plugin copy has the hook removed.** `~/.claude/plugins/cache/soleur/soleur/<version>/hooks.json` is
  a copy that still registers the hook on this machine until the plugin is updated or a session loads the checkout instead
  (`--plugin-dir`). Which copy a given session loads was not determined; the live check above must confirm the transcript shows no
  hook kill, not assume the merge removed it.
- That the fix removes every browser-closing cause. A hook in a user's global configuration, a Wayland or Vulkan GPU crash (same
  error string, different cause; mitigated separately in `.claude/playwright-mcp.config.json`) or a launch race still produces the
  same message. The learning documents the correlation method for finding another killer.

## Alternatives Considered

- **Keep the hook, scope it to the session's own process tree.** Rejected. `Stop` fires every turn, so even a session-scoped
  kill closes that session's live browser at each turn end. The three mechanisms in Decision 2 already cover the orphan case.
- **Replace it with a `SessionEnd` hook.** Rejected. It adds a hook for a duty the same three mechanisms already perform, and
  one more row for the web-parity and Devin ledgers to keep.
- **Brief: set the ping timeout as the fix.** Rejected as a fix; kept only as the guard in Decision 5.
- **Brief: track the PID this launch owns and kill only that.** Rejected. The proxy's process-group teardown already owns the
  child tree; PID bookkeeping adds state for nothing.
- **A throwaway per-session profile directory.** Rejected. It loses persistent logins that credential-handoff flows depend on
  (2026-05-12 learning). Slot 0 stays persistent.
- **`--isolated`.** Rejected. It wipes OAuth sessions on respawn (2026-05-12 learning).
- **A global `flock` mutex around the whole server.** Rejected. It serialises all sessions' browsers to avoid a collision the
  per-slot lease already avoids.
- **Unconditional `--browser chromium` in the plugin registration.** Rejected. It regresses Chrome-present hosts that have no
  bundled download and drops real Chrome's working sandbox.
- **Wrap the plugin registration in a `bash -c` launcher so it gets the slot lease too.** Rejected: the ADR-213 2026-09-18
  addendum rejected a `bash -c` launch in the plugin manifest as an unauditable shell string. So concurrent sessions on the plugin registration still get Playwright's own "profile already in use" error, which
  names the problem and kills nothing; the lease is scoped to this repository's `.mcp.json` accordingly.

## Consequences

- A turn ending no longer closes any Playwright browser. The same removal ends a host-level process kill in web Concierge sessions
  (ADR-093 amendment 2026-10-04), which is the concern issue #9281 raised; that issue is referenced, not closed.
- A browser is no longer reaped at turn end, so a browser the agent never closes lives as long as its session. Chrome's exit on
  pipe close, the proxy teardown and the watchdog bound that to the session. `agent-browser/SKILL.md` keeps the
  `browser_close` guidance.
- A launch that finds slot 0 held by a live parallel session starts 7 s later, well inside the 30 s MCP connect timeout.
- The lock is tied to the proxy, not to Chrome: a SIGKILLed proxy frees its slot while Chrome may live on. The owner-alive
  `SingletonLock` check is what keeps that slot from being reused (a Guard-2 row covers "lock free, live Chrome owner").
- The numbered slots are bounded (32 directories, reused). The `$base-$$` fallback is not: it creates one directory per launch
  and nothing reaps it. `agent-browser/SKILL.md` documents manual removal of `playwright-mcp-profile-*` directories.
- The fallback browser runs without the Chromium sandbox on Linux: in `coreBundle.js` `chromiumSandbox` is set to
  `channel !== "chromium" && channel !== "chrome-for-testing"`, so it is false for `chrome-for-testing`. Real Chrome keeps its
  sandbox. First use on a host with no bundled download prints Playwright's own instruction; the verified command is
  `npx @playwright/mcp@0.0.78 install-browser chromium` (run with `--dry-run` on 2026-10-04: rc 0, resolves "playwright chromium
  v1232").
- Mixed-version rollout: a session still on the old launch string will `pkill -9` on its next reconnect and may kill a
  new-style session's Chrome once. One-time.
- The `.mcp.json` edits load only on a full Claude Code restart.

## Cost Impacts

None. No vendor, subscription or paid resource. Bundled Chromium is already a Playwright download.

## NFR Impacts

None of the NFR-register rows changes tier; the register has no local-tooling reliability row.

## Principle Alignment

- AP-011 (ADRs for architecture decisions): Aligned. This records the lifetime ownership rule and the decision to retire a hook.

## C4 impact

The three `.c4` files under `knowledge-base/engineering/architecture/diagrams/` were read in full (`model.c4` 899 lines, `views.c4`
113 lines, `spec.c4` 54 lines).

- External actors: none new (the operator is already modelled).
- External systems: `playwrightMcp` is already modelled. No new vendor, webhook or system.
- Data stores: none added; slot directories are more instances of the browser profile store already named in `playwrightMcp`.
- Access relationships: unchanged. No element or edge is added.
- Falsified description, edited in this change: `playwrightMcp` said the plugin registration "ships NO config and no env forcing,
  so it runs the upstream defaults: headed, channel chrome — a launch-failure mode on hosts with no real Chrome installed" and
  named a single persistent profile. It now states the conditional bundled-Chromium fallback, the slot-leased project profile and
  the inert ping env guard. `snapshotGuard` and its edge text gain one clause for the opt-in `--chromium-fallback` argv
  behaviour. `model.likec4.json` is regenerated with `bash plugins/soleur/scripts/render-c4-model.sh`.
