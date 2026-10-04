---
title: "fix: Playwright MCP browser closes on its own"
type: fix
date: 2026-10-04
slug: playwright-mcp-browser-closing-on-its-own
branch: feat-one-shot-playwright-mcp-stability
issue: none
closes: none
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: Playwright MCP browser closes on its own

## Overview

The Playwright MCP browser disappears by itself within tens of seconds of launch, and the next tool
call fails with "Target page, context or browser has been closed" until `browser_close` forces a
fresh backend. The user reported this as unacceptable for Soleur users.

**The brief's working theory was wrong, and the real cause is outside the brief's file scope.**
Both facts are measured below, not asserted:

1. The ping-heartbeat theory (`PLAYWRIGHT_MCP_PING_TIMEOUT_MS`) cannot explain the symptom. In
   `@playwright/mcp@0.0.78` and `@0.0.83` the stdio transport calls `connect(..., false)`, so the
   heartbeat never starts on a stdio launch; it exists only on the streamable-HTTP session path.
   The observed failure shape also contradicts it: after `server.close()` a stdio server stops
   reading stdin, so a later call would hang, not return a tool-level "Target page ... closed".
2. The browser is killed by a **plugin Stop hook**. `plugins/soleur/hooks/hooks.json` registers
   `browser-cleanup-hook.sh` on `Stop`. `Stop` fires at the end of every assistant turn (not at
   session exit, as the 2026-04-03 learning assumed). The hook runs `pgrep -f
   'chrome.*--remote-debugging-pipe'` and sends SIGTERM to every match **on the whole host**, across
   all concurrent sessions. SIGTERM makes Chrome exit gracefully: exit 0, no coredump, window and
   process vanish together, and "idle" is simply "the turn ended". The brief's "no hook or script
   kills it" check missed the plugin's hooks.json.

The plan therefore fixes: (A) the Stop hook (root cause), (B) the project launch command's
cross-session `pkill -9` reaper and shared-profile contention, (C) the Chrome-absent launch failure
in the plugin registration, and (D) adds the ping-timeout setting the brief asked for, honestly
labelled as an inert latent-hazard guard, not the fix.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured) | Plan response |
|---|---|---|
| The server's heartbeat closes the browser after a ping timeout (cause of the 21s exit) | Heartbeat runs only on the HTTP session path: `coreBundle.js` `start()` calls `connect(factory, transport, Promise.resolve(), false)` for stdio in both 0.0.78 (line 70854) and 0.0.83; `connect(..., true)` is only at the HTTP session (70742). Our registrations are stdio. | Do NOT present the env var as the fix. Keep it as a documented latent-hazard guard (item D); PR states plainly it is inert today. |
| "No hook or script kills it" | `plugins/soleur/hooks/browser-cleanup-hook.sh` is registered on `Stop`; the session transcript records `Browser cleanup: killed 3 orphaned Playwright Chrome process(es)` at 18:04:08, 18:06:46, 18:14:44, 18:17:16, 18:21:30, 18:26:10, 18:28:00 UTC. Correlated against the MCP log, 14 of 15 "Target page ... closed" failures on 2026-10-04 have a hook kill (any session) between the preceding browser launch and the failure. The 15th (3s after launch) is a launch race. | Delete the hook (item A). |
| Chromium exit is "clean, exit 0" | Consistent with SIGTERM from the hook (Chrome handles SIGTERM gracefully), not with `pkill -9` (rc 137). | Hook is primary; the reaper's `-9` is a second, launch-time killer (item B). |
| plugins/soleur/.mcp.json fails without Google Chrome | Confirmed from source: no `--browser` flag -> `validateBrowserConfig` defaults `channel = "chrome"`; the registry throws "Chromium distribution 'chrome' is not found at /opt/google/chrome/chrome". `--browser chromium` maps to `chrome-for-testing` (bundled). | Conditional fallback in the proxy (item C). |
| Project `.mcp.json` pkill kills sibling sessions | Confirmed: three pattern `pkill -9 -f` over proxy, `bin/playwright-mcp` and `chrome.*$prof`, run at every server start and `/mcp` reconnect (the MCP log shows two "Sending SIGINT to MCP server process" reconnects in 15 minutes). | Replace with a kernel-lock slot lease (item B). |
| The proxy's child-env allowlist may strip the env var | There is no child-env allowlist: `subprocess.Popen(argv, ...)` is called without `env=`, so the child inherits the full environment. `refuse_argv_and_env` refuses a fixed list of sink variables; `PLAYWRIGHT_MCP_PING_TIMEOUT_MS` is not on it. | No proxy env change needed; add one suite row proving the variable survives to the child. |

## Research Insights

### Premise Validation

Cited by reference: file paths only (no issues). Checked on `origin/main`: `.mcp.json`,
`plugins/soleur/.mcp.json`, `.claude/playwright-mcp.config.json`, the proxy and its suite all exist.
Mechanism vs ADR corpus: ADR-213 (browser snapshot credential guard split) governs the proxy; it
does not decide browser lifetime or Stop-hook behaviour, and rejects none of this plan's mechanisms.
ADR-093 records that plugin hooks run in web Concierge sessions; issue #9281 (open) already flags
`browser-cleanup-hook.sh` as killing other sessions' Chrome on a shared host and classifies it
`deferred` in `plugin-stop-hooks-web-parity.test.ts`. The brief's heartbeat premise and its "no hook
kills it" premise were both stale/incorrect (see Reconciliation).

### Property List and Cut List (Mechanism Minimality Gate)

Properties the user needs:

- P1. An in-use browser survives turn boundaries and idle time.
- P2. A session's launch or reconnect never terminates another live session's browser or server.
- P3. Concurrent sessions each get a usable browser (no "profile already in use" failures).
- P4. A host without Google Chrome still gets a browser from the plugin registration.
- P5. No browser is orphaned after its session ends.

P5 is already bought by mechanisms on `origin/main`: Chrome exits when its `--remote-debugging-pipe`
closes; the proxy ends the child's whole process group on stdin EOF/signal (verified in
`Proxy.teardown`); Playwright's own watchdog closes browsers on stdin close
(`setupExitWatchdog`). The Stop hook buys nothing for P5 and violates P1 and P2.

Cut List:

| Mechanism | Property | What already covers it / why cut |
|---|---|---|
| Brief: env var as THE fix for the 21s exit | P1 | Not bought: inert on stdio (source-verified). Kept only as an explicitly-labelled guard (D). |
| Brief: "own the PID of this launch" kill tracking | P2/P5 | Proxy process-group teardown already owns the child tree; no PID bookkeeping needed. |
| Scoped (session-tree) Stop hook | P5 | Stop fires every turn, so even a session-scoped kill closes the user's own live browser each turn. Redundant with the P5 mechanisms. |
| SessionEnd replacement hook | P5 | Redundant with the same P5 mechanisms; one more thing to keep in parity ledgers. |
| Throwaway per-session profile dir | P3 | Loses persistent logins that credential-handoff flows depend on (learning 2026-05-12). Slot lease keeps slot 0 persistent. |
| `--isolated` | P3 | Wipes OAuth sessions on respawn (learning 2026-05-12). |
| Unconditional `--browser chromium` in the plugin | P4 | Regresses Chrome-present users without the bundled download, and drops real Chrome's working sandbox. Conditional selection chosen. |

### Institutional learnings applied

- `2026-07-05-playwright-mcp-orphan-server-profile-lock-contention.md` — the origin of the pkill reaper; one profile, many servers, `SingletonLock` tears pages down. Its goal (one live owner per profile) is kept; its means (pattern kill) is replaced.
- `2026-05-12-playwright-mcp-isolated-flag-wipes-oauth-sessions.md` and `2026-05-15-playwright-mcp-headed-and-persistent-profile.md` — persistence is a requirement.
- `2026-04-03-playwright-browser-cleanup-on-session-exit.md` — created the hook; its "Stop = session exit" premise is the root error. Gets a correction note.
- `2026-09-14-my-proxy-allowlisted-the-messages-it-relayed-and-relayed-them-verbatim.md` — the proxy rebuilds server requests; it answers a server `ping` with -32601 (see Latent hazard).
- Stop fires per turn: `2026-03-09-ralph-loop-crash-orphan-recovery.md` (stop hook firing every turn).

### Evidence log (reproducible, read-only)

- Source: `~/.npm/_npx/a5b920f00216d246/node_modules/playwright-core/lib/coreBundle.js` (0.0.78): `start()` ~70850; `startHeartbeat` 70976; sole `connect(..., true)` at 70742.
- Transcript: `~/.claude/projects/-data-git-repositories-jikig-ai-soleur/6b035ca0-*.jsonl` attachments carrying `Browser cleanup: killed N orphaned Playwright Chrome process(es)`.
- MCP log: `~/.cache/claude-cli-nodejs/-data-git-repositories-jikig-ai-soleur/mcp-logs-playwright/2026-10-04T11-40-48-071Z.jsonl`. Example: `browser_wait_for` succeeded 18:04:02, hook killed 3 processes 18:04:08.7, next call failed 18:04:26.
- Slot-lease prototype (scratch HOME, three overlapped `bash -c '. slot.sh; exec python3 ...'` launches): resolved `pwprof`, `pwprof-1`, `pwprof-2`; slot 0 was reusable after they exited; a `SingletonLock` naming a dead pid was cleared; one naming a live pid skipped the slot. fd 9 is held by the exec'd python process and not passed to its `subprocess.Popen` children (`close_fds` default).
- Launch args in the same log show the bundled `chromium-1232` with `--remote-debugging-pipe`, `--no-sandbox`, `--user-data-dir=/home/jean/.cache/playwright-mcp-profile`.

## Hypotheses

Network-outage checklist: not applicable (stdio over pipes; no network path). Ranked causes:

| # | Hypothesis | Verdict |
|---|---|---|
| H1 | Plugin Stop hook SIGTERMs every Playwright Chrome on the host at each turn end | **Confirmed** by transcript/MCP-log correlation (14/15); fixes in item A |
| H2 | Another session's launch runs `pkill -9` on the shared profile's Chrome | Real, secondary; item B |
| H3 | Ping heartbeat closes the server | **Refuted** for stdio (source + failure shape) |
| H4 | Profile `SingletonLock` contention between servers on one profile | Real contributor to 3-second launch failures; item B (slots) |
| H5 | Wayland/Vulkan GPU crash | Already mitigated by the X11 env prelude; same error string, different cause; out of scope |

## Problem Statement / Motivation

Browser skills (`qa`, `ux-audit`, `reproduce-bug`, credential handoff) run multi-call flows; a
browser that dies between calls makes each flow fail unpredictably. With roughly seven concurrent
sessions on the dev machine, any session finishing a turn closes everyone else's browser, and any
session starting or reconnecting kills everyone else's Chrome and server. For customers, the same
Stop hook ships in the plugin and kills any Playwright Chrome on their machine at every turn end,
and a Chrome-less host gets no browser at all.

## Proposed Solution

### A. Remove the Stop hook (root cause, P1/P2)

Delete `plugins/soleur/hooks/browser-cleanup-hook.sh`, its `Stop` entry in
`plugins/soleur/hooks/hooks.json`, and the registry rows that mirror it. P5 stays covered by the
proxy teardown, Chrome pipe-EOF exit and Playwright's stdin watchdog. Update the retired-rule
breadcrumb (the rule's enforcement moves to those mechanisms).

### B. Replace the project `.mcp.json` reaper with a slot lease (P2/P3)

New `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh`, sourced by the
launch string, that sets `prof`:

- Slot 0 is the persistent profile `$HOME/.cache/playwright-mcp-profile`; slots 1..31 are
  `$HOME/.cache/playwright-mcp-profile-<n>`.
- A slot is claimed by a non-blocking `flock` on a lock file in the slot directory held on fd 9.
  fd 9 survives `exec env ... python3 proxy` and is held by the proxy process for the server's
  lifetime; the kernel releases it on any exit, including SIGKILL. No pattern kill exists anywhere.
- After winning the flock, if `SingletonLock` exists and its owner pid is alive, treat the slot as
  busy and advance (a leftover or foreign Chrome owns the profile; never kill it, never remove its
  lock). If the owner is dead, `rm -f "$prof"/Singleton*` (stale files only).
- Slot 0 only: wait up to 7 seconds for the lock (`flock -w 7`) before advancing, because a `/mcp` reconnect's old proxy keeps its lock for up to `GRACE_S` (5.0s) after SIGINT and a reconnect must not land on an empty profile and lose the persistent logins. Slots 1+ are non-blocking. Cost: a launch that finds slot 0 held by a live parallel session starts 7 seconds later (well inside the 30s MCP connect timeout).
- The lock is tied to the proxy process, not to Chrome: a SIGKILLed proxy frees its slot while its process group may live on; the owner-alive `SingletonLock` check is what keeps that slot from being reused (Guard 2 has a row for "lock free, live Chrome owner").
- Sourced-script hygiene: the script uses `return`, never `exit`; no `set -e`/`set -u`; helper names carry a `_pwslot_` prefix and are unset before `exec`; fd 9 is opened in the surviving shell (never inside `$(...)`); the launch string is `. <script> || exit 1`, and asserts `[ -n "$prof" ]`.
- No `flock` binary, a filesystem without flock support, or all 32 slots busy: fall back to a unique `$base-$$` directory with a stderr
  note. Never block, never kill.

`.mcp.json` becomes: `. plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh; exec env -u WAYLAND_DISPLAY ... python3 <proxy> -- npx @playwright/mcp@0.0.78 --user-data-dir=$prof --config=...`
The existing Guard 2 anchors (`exec env`, `--user-data-dir=$prof`, `--config=...`, the pin in
`args[1]`) are preserved so the suite's pin derivation and mutants keep working.

### C. Chrome-absent fallback in the plugin registration (P4)

Add an opt-in boolean flag `--chromium-fallback` to the proxy (before `--`). When set, and the
server argv has no `--browser`, and `PLAYWRIGHT_MCP_BROWSER` is unset, and no Google Chrome
executable exists at the platform's known path (`/opt/google/chrome/chrome` on Linux,
`/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` on macOS), the proxy appends
`--browser chromium` (Playwright maps it to the bundled `chrome-for-testing`). On any other platform the check is a no-op (nothing appended), asserted by a suite row. Flag absent: child
argv is byte-identical to today (the invariant the proxy header already states). Test seam:
`PLAYWRIGHT_MCP_PROXY_CHROME_PATHS` (os.pathsep list) replaces the default path list, mirroring the
existing `PLAYWRIGHT_MCP_PROXY_GRACE_S` seam. No credential guarantee is touched: `--browser` is not
a sink flag and `--executable-path` stays refused.

Documented residual: the bundled-Chromium fallback runs without the Chromium sandbox on Linux
(Playwright default for `chrome-for-testing`), unlike real Chrome. First use on a host with no
bundled download prints Playwright's own instruction; `agent-browser/SKILL.md` records the
verified command `npx @playwright/mcp@0.0.78 install-browser chromium` (checked against
`install-browser --help` on the pinned package).

### D. The ping-timeout setting (per the brief), honestly labelled

Add `"env": {"PLAYWRIGHT_MCP_PING_TIMEOUT_MS": "0"}` to both registrations. It is **inert on stdio in
0.0.78/0.0.83** and does not fix the reported symptom. It is kept because of a real latent hazard:
the proxy answers any server-originated `ping` with JSON-RPC -32601 (`relay_server_message` relays
only `roots/list`), so any future `@playwright/mcp` that starts the heartbeat on stdio would have
`server.ping()` reject immediately and `server.close()` the browser. Value 0 disables it: `startHeartbeat` begins `const timeout = pingTimeout(); if (timeout <= 0) return;` (coreBundle.js, 0.0.78 line ~70977).
One lifetime-suite row asserts presence in both registrations (marked as a guard for future pin bumps) and one proxy row proves it reaches the child; there is no third copy; the PR and ADR say it is a guard, and the
pin-bump checklist gains "re-verify heartbeat is not started on stdio". Fixing the proxy's ping
handling is a separate change (tracked, see Deferrals).

## Technical Considerations

- Registration `env` precedent: `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` writes `env` into its `.mcp.json` overlay.
- `.mcp.json` changes load only on a full Claude Code restart, not on `/mcp` reconnect (existing note in `playwright-mcp.config.json`); hooks.json changes load on plugin reload/restart. Live confirmation must follow a restart.
- The old hook, if exercised in a RED demonstration, would kill every real Playwright Chrome on the host. All RED demonstrations MUST use a `pgrep` PATH shim that emits only the decoy pid (see Test Scenarios). Never run the old hook unshimmed.
- Mixed-version transition: a session still running the old launch string will `pkill -9` on its next reconnect and may kill a new-style session's Chrome once. One-time; note in the PR.
- Disk: numbered slots are bounded (32 directories, reused). The `$base-$$` fallback (no `flock`, e.g. stock macOS, or exhaustion) is NOT bounded: it creates one directory per launch and nothing reaps it; the project `.mcp.json` is a Linux dev-machine config, and the SKILL.md note documents manual removal of `playwright-mcp-profile-*` directories. A `SingletonLock` pointing at a recycled live pid makes a slot look busy, which is the safe direction.
- P5 rests on pipe-EOF, the proxy teardown and Playwright's stdin watchdog; `Proxy.teardown` does not run if the proxy is SIGKILLed, so Phase 5 includes a scratch probe (own temp profile, bundled Chromium, headless, never touching live sessions) that SIGKILLs a proxy and observes Chrome exit. It is a one-off probe whose result goes in the learning, not a CI row.
- cron-ux-audit writes its own `.mcp.json` overlay and does not use the reaper (grep of `cron-ux-audit.ts` finds no pkill).
- Not in scope: plugin registration profile contention (it never kills; a second session gets Playwright's clear "already in use" error), the Wayland/Vulkan mitigation, `.claude/playwright-mcp.config.json` (no change needed).

## Architecture Decision (ADR/C4)

### ADR

Create `knowledge-base/engineering/architecture/decisions/ADR-271-browser-lifetime-belongs-to-the-launching-session.md`
via `soleur:architecture` (ordinal provisional; ship re-verifies the next free number against
`origin/main`). Decision: no hook or launcher terminates browser processes by pattern; browser
lifetime is owned by the launching session's process tree (proxy teardown, Chrome pipe-EOF,
Playwright watchdog); profile ownership is a kernel flock lease; Chrome-absent fallback is
selected in the proxy; the ping env is a latent-hazard guard. Alternatives Considered: the Cut List
rows above plus "keep the hook but scope it to the session tree" and "global flock mutex around the
whole server". Status: accepted.

### C4 views

All three files `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` are
read at work time. Checked against the feature: external human actor (the operator/user: already
modelled, no change), external systems (`playwrightMcp` system, Chrome inside its description:
already modelled; no new vendor or webhook), containers/data stores (the browser profile is named
in `playwrightMcp`'s description; slot directories are the same store class), actor-to-surface
access relationships (unchanged). No element or edge is added. One element description is falsified
and is edited in this PR: `playwrightMcp` (model.c4 ~line 365) states "headed real Chrome (channel
chrome ...)" with "persistent profile ~/.cache/playwright-mcp-profile" and that the plugin
registration "ships NO config and no env forcing ... a launch-failure mode on hosts with no real
Chrome installed". Update it for: conditional bundled-Chromium fallback, slot-leased project
profile, the env guard. Regenerate `model.likec4.json`; run `c4-code-syntax`, `c4-render`,
`plugins/soleur/test/c4-count-parity.test.sh` and `c4-model-freshness.test.sh`.

### Sequencing

All in this PR; nothing deferred to a follow-up for the ADR or C4.

## Guard Contract

### Guard 1 — No registered hook or launch command terminates a browser it did not launch

**Property.** No command registered in `plugins/soleur/hooks/hooks.json` (any event) and no MCP
launch string in either `.mcp.json` terminates a browser, MCP-server or Chrome process selected by
name or command-line pattern.

**Assembly.** Chokepoints: every `command` under every event key of `hooks.json` (not only `Stop`),
the script file each one invokes (resolved through `bash "..."` wrappers and `${CLAUDE_PLUGIN_ROOT}`),
the `args` of `.mcp.json` and `plugins/soleur/.mcp.json`, and the sourced slot script. Population is
derived by parsing the files at test time, never listed by hand; the suite asserts the derived
script count is >= the floor it measured at authoring time and that the scanner flags a planted
fixture (positive proof the scan ran). Members drift (a new hook, a new event); the chokepoint is
"every command string the harness will execute".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the old `browser-cleanup-hook.sh` and its `Stop` registration (from git) | RED |
| 2 | Register a pattern-killing script under a different event (`SessionStart`) | RED |
| 3 | Add a second killing hook after a compliant first in the same event array | RED |
| 4 | Put `pkill -9 -f "[c]hrome.*$prof"` back into the `.mcp.json` launch string | RED |
| 5 | Empty `hooks.json` command population (scanner would examine nothing) | RED (vacuity floor) |
| 6 | Harness: replace the decoy `pgrep` shim with one that prints nothing (the old hook then kills nothing) | RED (the positive-control row must fail, proving the decoy is a real target) |

Must-PASS non-canonical inputs: a hook that kills only a pid it spawned itself (`kill "$!"`) passes;
a hook using `pkill` on a non-browser name passes. **Anchor:** n/a, the guard compares no stored
value; it scans the live tree and executes the decoy.

### Guard 2 — A launch claims a slot no live launch holds, and kills nothing

**Property.** Two concurrently live launches under one `$HOME` never resolve the same `--user-data-dir`,
and a launch terminates no process.

**Assembly.** Every path that sets `prof`: the flock win, the owner-alive skip, the no-`flock`
fallback, the 32-slot exhaustion fallback, plus the single `exec` line in the `.mcp.json` string that
consumes `$prof`. Chokepoint: the sourced slot script is the only place `prof` is assigned.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `flock -n` (always slot 0) | RED (two launches share a dir) |
| 2 | Re-add a `pkill` of a decoy `chrome --user-data-dir=<slot0>` process | RED (decoy dies) |
| 3 | Treat a live-owner `SingletonLock` as stale (remove it) | RED (lock file gone / decoy owner's lock removed) |
| 4 | A third concurrent launch collides after two compliant ones | RED (assert 3 distinct dirs) |
| 5 | Dispatch: slot script not sourced (string reduced to the old literal) | RED (`prof` empty / no slot lock created) |
| 7 | A free lock but a live-owner `SingletonLock` (proxy SIGKILLed, Chrome alive) reuses the slot | RED |
| 6 | Harness: run the two launches sequentially instead of overlapped | RED (overlap proof row fails: both launches must be alive simultaneously, observed via their lock files) |

Must-PASS non-canonical inputs: a reconnect (old holder exits within 5s) reacquires slot 0 rather than slot 1; stale `SingletonLock` with a dead owner is cleared and slot 0 reused;
`flock` absent from PATH yields a unique `$base-$$` dir. **Anchor:** n/a (kernel lock, no stored value).

## Implementation Phases

### Phase 0 — RED first (`cq-write-failing-tests-before`)

1. Create `plugins/soleur/skills/agent-browser/test/playwright-mcp-lifetime.test.sh` (new small suite, wired like its sibling `*.test.sh`). Rows that must be RED on the current tree: no killing Stop hook; both registrations carry the env; no `pkill` in `.mcp.json`; two overlapped launches get distinct profiles; decoy survives a launch; plugin registration carries `--chromium-fallback`.
2. RED demonstration of the hook defect uses a scratch `PATH` with a `pgrep` shim that prints only the decoy pid, and the old hook text from `git show HEAD:plugins/soleur/hooks/browser-cleanup-hook.sh`.

### Phase 1 — Root cause (item A)

Delete the hook script and `Stop` entry; remove the `.claude/hooks/devin-dispositions.tsv` row;
remove the `"browser-cleanup-hook.sh"` entry (and its comment) from `REGISTRY` in
`apps/web-platform/test/plugin-stop-hooks-web-parity.test.ts`; update the
`scripts/retired-rule-ids.txt` breadcrumb to the ADR. Run `devin-matcher-parity.test.sh`, the parity
test, `lint-rule-ids.py`.

### Phase 2 — Slot lease (item B)

Add the slot script; rewrite the `.mcp.json` launch string; replace the two `reaper:` rows in the
proxy suite's Guard 2 with rows asserting the new string (no `pkill`, sources the slot script, with
the positive proof that `exec env` and the proxy are still present); add the slot behaviour rows to
the new suite.

### Phase 3 — Proxy flag and registrations (items C, D)

Implement `--chromium-fallback` in `parse_argv`/`Proxy.__init__`; update the module docstring;
extend `g3_shape` and its mutants for the new argv (the `env` key is asserted once, in the lifetime suite); add proxy rows: flag absent
leaves argv unchanged, flag + Chrome absent appends `--browser chromium` once, flag + Chrome present
appends nothing, flag + explicit `--browser`/`PLAYWRIGHT_MCP_BROWSER` appends nothing, the ping env
reaches the child (stub logs the variable). Bump `EXPECTED_MUTANTS`, `EXPECTED_RED_ROWS` and
`MIN_ASSERTIONS` to the new measured counts in the same edit. Add `env` to both JSON registrations.

### Phase 4 — Docs and records

ADR-271; learning
`knowledge-base/project/learnings/bug-fixes/2026-10-04-stop-hook-killed-live-playwright-chrome-heartbeat-theory-refuted.md`
(root cause, the refuted theory and why the source read settles it, the correlation method, Stop
fires per turn); a dated correction note in
`knowledge-base/project/learnings/workflow-issues/2026-04-03-playwright-browser-cleanup-on-session-exit.md`;
`agent-browser/SKILL.md` §"Troubleshooting: Playwright MCP backend closed between calls" and the
Chrome-absent guidance; C4 edit and regeneration.

### Phase 5 — Verify

Run the proxy suite, the new suite, `bash plugins/soleur/test/c4-count-parity.test.sh`, the parity
and Devin tests, `python3 scripts/lint-guard-contract.py`. Then the live check below.

## Files to Edit

- `.mcp.json` — launch string (slot script, no pkill) + `env`
- `plugins/soleur/.mcp.json` — `--chromium-fallback` + `env`
- `plugins/soleur/hooks/hooks.json` — drop the browser-cleanup `Stop` entry
- `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py` — `--chromium-fallback`
- `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` — Guard 2 reaper rows, `g3_shape`, fallback/env rows, counts
- `plugins/soleur/skills/agent-browser/test/fixtures/fake-playwright-mcp.py` — log the ping env variable to stderr
- `plugins/soleur/skills/agent-browser/SKILL.md` — playbook updates
- `.claude/hooks/devin-dispositions.tsv` — remove the hook row
- `apps/web-platform/test/plugin-stop-hooks-web-parity.test.ts` — remove the registry entry
- `scripts/retired-rule-ids.txt` — breadcrumb
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `model.likec4.json` — `playwrightMcp` description
- `knowledge-base/project/learnings/workflow-issues/2026-04-03-playwright-browser-cleanup-on-session-exit.md` — correction note
- `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md` — dated one-line note that the Stop hook it lists as running in web sessions is removed

## Files to Delete

- `plugins/soleur/hooks/browser-cleanup-hook.sh`

## Files to Create

- `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh`
- `plugins/soleur/skills/agent-browser/test/playwright-mcp-lifetime.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-271-browser-lifetime-belongs-to-the-launching-session.md`
- `knowledge-base/project/learnings/bug-fixes/2026-10-04-stop-hook-killed-live-playwright-chrome-heartbeat-theory-refuted.md`

Glob/path verification (`git ls-files`) of every path above is an AC. `.claude/playwright-mcp.config.json` is deliberately not edited.

## Open Code-Review Overlap

Run at work time: `gh issue list --label code-review --state open --json number,title,body` then match
each Files-to-Edit path. Known related open issue found by research: **#9281** (the Stop hook this
plan deletes). Disposition: Fold in the behaviour (the hook is removed); do NOT use a closing
keyword, per the brief. The PR body says "Ref #9281" and notes the hook is removed.

## Deferrals

- Proxy answers server-originated `ping` with -32601 (latent; guarded by the env in item D). File one tracking issue at ship time: what, why deferred, re-evaluation criteria (any `@playwright/mcp` bump that starts the heartbeat on stdio), milestone from `knowledge-base/product/roadmap.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** browser skills still die mid-flow (the status quo), or, worse, the browser fails to start at all (a slot-script or fallback bug), so `qa`, `ux-audit` and credential handoff stop working.
- **If this leaks, the user's workflow is exposed via:** no new egress or credential path. The residual is that the Chrome-absent fallback runs bundled Chromium without the Chromium sandbox on Linux; the redaction proxy's guarantees are untouched and its full suite is a gate.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the failure is a recurring reliability defect across many users rather than a single-user data incident, and the credential-redaction path is unchanged, so not `single-user incident`.

## Observability

```yaml
liveness_signal:
  what: "Playwright tool calls keep succeeding across turn boundaries; no 'Target page, context or browser has been closed' after a successful browser_navigate in Claude Code's persisted MCP log"
  cadence: "per session"
  alert_target: "none - local developer tool with no pager; the failure is user-visible in-session as a tool error"
  configured_in: "plugins/soleur/skills/agent-browser/test/playwright-mcp-lifetime.test.sh (regression) and ~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/*.jsonl (evidence)"
error_reporting:
  destination: "Claude Code MCP log directory above (proxy and server stderr are persisted there)"
  fail_loud: "proxy stderr line 'playwright-mcp-redact-proxy: refusing to start: <reason>'; slot script stderr line naming the fallback slot"
failure_modes:
  - mode: "a hook or launcher terminates a live browser"
    detection: "lifetime suite Guard 1 rows (scan + live decoy) fail in CI"
    alert_route: "CI red on the PR"
  - mode: "two live launches share a profile"
    detection: "lifetime suite Guard 2 overlap rows fail in CI"
    alert_route: "CI red on the PR"
  - mode: "Chrome-absent host gets no browser"
    detection: "proxy suite fallback rows; at runtime Playwright's 'Chromium distribution not found' text in the MCP log"
    alert_route: "CI red; user sees the tool error with the install hint"
logs:
  where: "~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/"
  retention: "Claude Code's own log rotation"
discoverability_test:
  command: bash plugins/soleur/skills/agent-browser/test/playwright-mcp-lifetime.test.sh
  expected_output: 0 failed
```

The lifetime suite is designed to finish in under 15 seconds (small fixtures, `sleep` decoys, no browser).

## Encryption Posture

Skipped: no persistent store or cross-component connection is introduced. Slot directories are more
instances of the existing Chrome profile store on the user's own disk (see the Phase 2.8-era
posture in the 2026-09-18 plan); the registration change adds no connection.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (inline) plus plan-review panel and deepen-plan agents
**Assessment:** Hook semantics, launcher locking, a security-adjacent proxy edit and an ADR. No
product, marketing, legal or finance surface; CLO attestation of 2026-09-14 covers the redaction
guarantees, which are unchanged. No UI surface (no files under components/ or app/), so no Product/UX gate.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix the Playwright MCP browser closing on its own" | Item A (root cause), Phase 1 | mapped |
| 2 | "add a regression test that asserts the setting is present in both registrations" [brief] | Item D; Phase 3; lifetime suite rows | mapped |
| 3 | "state plainly in the PR that live confirmation needs a /mcp reconnect plus >60s idle survival" [brief] | Acceptance Criteria (PR text) and Live confirmation; the plan adds that a full restart, not `/mcp`, is needed for `.mcp.json` and the hook removal | mapped |
| 4 | "add a fallback to bundled Chromium" [brief] | Item C | mapped |
| 5 | "Make the cleanup per-session (own the PID/profile of this launch) instead of per-profile, or give each session its own profile dir." [brief] | Item B (slot lease) | mapped |
| 6 | "Keep the redact-proxy credential guarantees intact: run its existing test suite." [brief] | Phase 3 and AC (suite green) | mapped |
| 7 | "with the why recorded where the repo records such things (ADR or learning, per the repo's conventions)" [brief] | Phase 4 (ADR-271, learning) | mapped |
| 8 | "Ref the user's report; no issue closes." [brief] | Open Code-Review Overlap, PR text | mapped |
| 9 | "If the ping-timeout env var is stripped by the proxy's child-env allowlist, fix that." [brief] | Reconciliation row (no allowlist exists); proxy suite env row | mapped |
| 10 | "Do not touch the main checkout or other sessions' worktrees. Do not dispatch any workflow; make no production writes." [brief] | Technical Considerations (shimmed RED runs); no workflow dispatch anywhere | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Item A: delete the Stop hook and mirrors | "Fix the Playwright MCP browser closing on its own" | asked (the cause of ask 1 is outside the brief's listed files; justified in Overview) |
| Registry/ledger/parity edits (tsv, parity test, retired-rule breadcrumb) | — | inferred — justification: removing the hook without them reddens `devin-matcher-parity.test.sh`, `plugin-stop-hooks-web-parity.test.ts` and `lint-rule-ids.py` |
| Item B slot script + launch string | "Make the cleanup per-session (own the PID/profile of this launch) instead of per-profile" | asked |
| Item C proxy flag | "add a fallback to bundled Chromium" | asked (proxy is the only place a conditional can live; the unconditional alternative is in the Cut List) |
| Item D env in both registrations | "Add the new setting to both registrations" | asked |
| ADR-271 and learning | "ADR or learning, per the repo's conventions" | asked |
| C4 `playwrightMcp` description edit and regeneration | — | inferred — justification: the description states facts this change falsifies and `c4-model-freshness` pins the regenerated JSON |
| `fake-playwright-mcp.py` env logging | "If the ping-timeout env var is stripped by the proxy's child-env allowlist, fix that." | asked (needed to prove the variable reaches the child) |
| 2026-04-03 learning correction note | — | inferred — justification: that learning's "Stop = session exit" premise is the root error and would mislead the next reader |
| SKILL.md playbook update | "state plainly ..." | inferred — justification: the documented connect-failure playbook names the Chrome-absent mode this change alters |
| Deferral issue for the proxy ping handling | — | inferred — justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for a deferred latent defect |

### Split Assessment

- Subsystems touched: 6 — `.claude`, `.mcp.json`, `apps/web-platform`, `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: 18 | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The root count exceeds the threshold only because removing the hook must move atomically with three one-line registry/ledger edits (`.claude`, `apps/web-platform`, `scripts`) or the parity tests go red between PRs; the brief asked for all of it as one fix. If review finds the proxy flag (item C) contentious, the clean seam is to cut item C to its own PR.

## Acceptance Criteria

- [ ] AC1: `git grep -n "browser-cleanup" -- plugins/soleur/hooks .claude/hooks apps/web-platform/test` returns zero lines; `plugins/soleur/hooks/browser-cleanup-hook.sh` is absent; `hooks.json` still parses and keeps `stop-hook.sh` and `unkept-promise-hook.sh`.
- [ ] AC2: `.mcp.json` playwright `args[1]` contains no `pkill`/`killall`, sources `playwright-mcp-profile-slot.sh`, still has `exec env`, `--user-data-dir=$prof`, `--config=.claude/playwright-mcp.config.json` and exactly one `@playwright/mcp@0.0.78`; both registrations carry `"env": {"PLAYWRIGHT_MCP_PING_TIMEOUT_MS": "0"}`; the plugin registration carries `--chromium-fallback`.
- [ ] AC3: Two launches of the `.mcp.json` string under one scratch `$HOME`, overlapped, resolve distinct `--user-data-dir`s; a decoy process whose argv is `chrome --user-data-dir=<slot0>` survives a third launch; a stale `SingletonLock` (dead owner) is cleared; a live-owner lock is left in place and the slot skipped.
- [ ] AC4: Proxy: with `--chromium-fallback` and `PLAYWRIGHT_MCP_PROXY_CHROME_PATHS` pointing at nothing, child argv gains `--browser chromium` once; with a present path, nothing; with the flag absent, argv is byte-identical to before; `PLAYWRIGHT_MCP_PING_TIMEOUT_MS=0` reaches the child.
- [ ] AC5: The new suite is RED on the pre-change tree for each Phase 0 row (observed with the shimmed `pgrep`, never against real browsers) and GREEN after; its mutation rows (Guard 1 #1-#6, Guard 2 #1-#6) each go RED.
- [ ] AC6: `bash plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` is green with the bumped `EXPECTED_MUTANTS`/`EXPECTED_RED_ROWS`/`MIN_ASSERTIONS`; `redact-a11y-snapshot.test.sh` green; `devin-matcher-parity.test.sh`, `plugin-stop-hooks-web-parity.test.ts`, `lint-rule-ids.py`, `c4-count-parity.test.sh`, `c4-model-freshness.test.sh`, `c4-code-syntax`/`c4-render` and `python3 scripts/lint-guard-contract.py` green.
- [ ] AC7: ADR-271, the learning and the 2026-04-03 correction note exist; the ADR names the refuted heartbeat theory and the env var as an inert guard.
- [ ] AC8: PR body states: what is proven (hook cause via 14/15 transcript-to-MCP-log correlation plus the regression suite), what is NOT proven (live idle survival), that the env var is inert today, that live confirmation needs a full Claude Code restart (a `/mcp` reconnect reuses the cached `.mcp.json` command and does not reload the removed hook) then more than 60 seconds idle across several turn boundaries, and "Ref #9281" with no closing keyword.

## Test Scenarios

- Given the real tree, when the Guard 1 scanner reads every command in `hooks.json` plus the scripts they invoke and both `.mcp.json` launch strings, then it finds no pattern-kill of a browser/MCP process and reports a population at or above its floor. Positive control: the old hook text restored from git, executed once under the `pgrep` shim against a decoy `chrome --remote-debugging-pipe` process, DOES kill the decoy and the scanner flags it. Unrelated Stop hooks are never executed.
- Given the old hook text restored from git and registered under any event, when the suite scans, then it goes RED (Guard 1 #1, #2).
- Given two overlapped `bash -c "$(jq -r ...args[1] .mcp.json)"` launches with a PATH `npx` shim, then each `--user-data-dir` differs and neither launch signalled any process.
- Given no `flock` on PATH, then the launch uses a `$base-$$` directory and still starts.
- Given a Chrome-less host (seam), plugin argv gets `--browser chromium`; Chrome present, it does not.
- Live (after merge, user-run): restart Claude Code, navigate once, wait over 60 seconds idle across at least three assistant turns in this and one parallel session, then take a snapshot; and `grep -c "Browser cleanup: killed"` on the new session transcript is 0.

## Success Metrics

Zero "Target page, context or browser has been closed" results following a successful call in a
session's MCP log across a day of parallel use; zero hook-kill lines in transcripts.

## Dependencies & Risks

- R1: The hook is not the only killer in someone's environment (user-global hooks). Mitigation: the learning documents the correlation method for finding any other.
- R2: `flock` is util-linux; absent on stock macOS. The project `.mcp.json` is already Linux-specific (X11 env, pkill); fallback to `$base-$$` keeps it working.
- R3: Editing a security-reviewed proxy. Mitigation: opt-in flag, no sink changes, full 77-mutant suite plus new rows; cut-to-own-PR seam.
- R4: Mixed-version one-time kill during rollout (see Technical Considerations).
- R5: The fallback browser lacks the Chromium sandbox on Linux (documented residual).

## References & Research

- ADR-213, ADR-093; issues #9281, #8156, #7980; learnings listed under Research Insights.
- `plugins/soleur/hooks/hooks.json`, `plugins/soleur/hooks/browser-cleanup-hook.sh`, `.mcp.json`, `plugins/soleur/.mcp.json`.
- Plan that introduced the plugin registration: `knowledge-base/project/plans/2026-09-18-feat-proxy-wrapped-playwright-mcp-default-plan.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled.
- The suite derives the pin from `.mcp.json` `args[1]` by regex; any restructuring of that string must keep exactly one `@playwright/mcp@<version>` there.
- Never run the old hook unshimmed on a machine with live sessions.
- `.mcp.json` edits do not take effect on `/mcp` reconnect; say so in the PR.
