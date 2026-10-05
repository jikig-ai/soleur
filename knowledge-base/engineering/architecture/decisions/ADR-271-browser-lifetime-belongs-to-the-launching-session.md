---
title: Browser lifetime belongs to the launching session
status: accepted
date: 2026-10-04
supersedes: none
issue: none
related: [9281, 8156, 7980, 7947]
related_adrs: [ADR-213, ADR-093, ADR-080]
tags: [playwright, mcp, hooks, browser, process-lifetime, claude-code]
brand_survival_threshold: aggregate pattern
---

# ADR-271: Browser lifetime belongs to the launching session

## Status

**Accepted — 2026-10-05**, for the lifetime fix (Decisions 1, 2, 4, 5). Recorded `adopting` on 2026-10-04 (the ADR-270 precedent)
because the live idle-survival check had not run. It ran twice on 2026-10-05, on the plugin registration, and passed ("Proven").
The operator decided that recipe step 4 (a second live process while the first browser is open) is not part of the acceptance
check, because it tests the slot lease and needs a host with Google Chrome (record: https://github.com/jikig-ai/soleur/issues/9281#issuecomment-5995806095).
Still open under "Not proven", and tracked on #9281, which stays open: that lease behaviour live, idle survival on the project
registration (headed Chrome), headed Chrome after a proxy SIGKILL, and the unwrapped cron-ux-audit server.

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
- It is the only registered command that signals processes by pattern. `git grep -n -a -E '\bkill\b|pkill|killall|pgrep'
  fa8bc5961f -- 'plugins/soleur/hooks/*.sh' 'plugins/soleur/hooks/lib/*'` matches executable code in two files:
  `browser-cleanup-hook.sh` (`pgrep -f ...` then `kill "$pid"`) and `stop-hook.sh` (a `kill -0 "$OWNER_PID"` liveness probe, which
  sends no signal); every other hit is a comment. The project and user `settings.json` files register no `Stop` or `SessionEnd`
  hook (`jq` over both). This searched the plugin tree as well as the settings files; an earlier pass in the session searched only
  the settings files and missed the plugin hook entirely.
- The loaded plugin copy carries it: `~/.claude/plugins/installed_plugins.json` lists `soleur@soleur` at user scope with an
  `installPath` under `~/.claude/plugins/cache/soleur/soleur/`, and `jq -c '.hooks.Stop[].hooks[].command'
  <installPath>/hooks/hooks.json` on that copy still printed `browser-cleanup-hook.sh` on 2026-10-04 (version `4dbd1affe8eb`,
  `lastUpdated` 2026-09-17).
- Correlation: 15 "Target page, context or browser has been closed" results are in that day's MCP log (`grep -a -c` of that
  phrase on the day's `mcp-logs-playwright` file gives 30 matching lines, two per failure). The session transcripts carry
  `Browser cleanup: killed N orphaned Playwright Chrome process(es)` lines, stored as `hook_success` attachments with `hookEvent`
  `Stop` (the string also appears in quoted text, which is not an event): 18 events on 2026-10-04, from 5 sessions, at the time of
  the analysis. The count is a point in time, and the installed copy keeps firing: the same filter run during the review found 26
  from 5 sessions (`jq` over the project's transcripts, `startswith("2026-10-04")` on `.timestamp`). For each failure, the window
  runs from the previous successful tool completion to the failure's own timestamp. **14 of 15 failures have at least one hook
  kill, from any session, inside their window.** The 15th failed 3 s into a call, and its nearest kill is stamped 26 ms after the
  failure (transcript attachments are written after the hook runs, so that ordering is not resolvable); it is counted as not
  matching. The method is in the learning.

### The refuted theory

`@playwright/mcp` 0.0.78 and 0.0.83 start the heartbeat only on the streamable-HTTP session path. In `coreBundle.js` the stdio
branch of `start()` (`options.port === void 0`) calls `connect(serverBackendFactory, transport, Promise.resolve(), false)`; the
`runHeartbeat` argument is `true` only on the HTTP session path. Checked in both versions with
`grep -nE 'connect\(serverBackendFactory' ~/.npm/_npx/*/node_modules/playwright-core/lib/coreBundle.js`. Every registration in
this repository is stdio. That grep is the refutation. A second argument, by inference and not exercised: the failure shape also
looks wrong for a heartbeat close, because after `server.close()` a stdio server would be expected to stop reading stdin, so a
later call would hang rather than return a tool-level "Target page ... closed". Nothing here ran that against the pinned server;
the decision does not rest on it.

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
   (every event, the scripts they invoke), the project `.claude/settings.json` hook commands and both `.mcp.json` launch strings
   keeps it that way, with a live decoy as positive control. The scan proves a text-and-shim property of this tree's registries;
   other plugins, older checkouts, the installed plugin copy and tools the shim does not cover are outside it.
2. **A browser's lifetime belongs to the process tree of the session that launched it.** Three mechanisms end a browser when its
   launcher goes away, and they do not all apply in every case:
   - Chrome exits when its `--remote-debugging-pipe` closes (upstream behaviour).
   - The pinned server's own exit watchdog (`setupExitWatchdog`: stdin `close`, SIGINT or SIGTERM, then it closes every browser it
     opened) runs when its stdin closes.
   - The proxy ends the child's process group on stdin EOF or a signal (`Proxy.teardown`). That is `killpg` by a LIVE proxy,
     and it covers the `npx` and node group only: Playwright spawns Chrome `detached` (`detached: process.platform !== "win32"` in
     `coreBundle.js`), so Chrome is not in that group. ADR-213's older wording that a SIGKILLed server's Chrome is "reaped by the
     same group teardown" describes this mechanism, which is a different one from the SIGKILL case below.
   When the proxy itself is SIGKILLed its `Proxy.teardown` cannot run, so only the server's stdin watchdog and Chrome's
   pipe-EOF exit apply. That case was measured for headless bundled Chromium: the proxy was SIGKILLed after a successful
   `browser_navigate about:blank`, and every descendant (npm exec, node server, Chrome main and its renderer, zygote, gpu and
   utility processes) was gone within 0.04 s in each of three runs, Chrome first. The procedure is in the learning's "No browser
   outlives its launcher" section; the driver was not kept, so the figure cannot be re-run from the records. **Headed real Chrome
   (the project registration) was not measured and relies on the upstream pipe-EOF behaviour, unmeasured.** Two older learnings
   (2026-04-03 orphaned `--remote-debugging-pipe` Chrome processes, 2026-07-05 `playwright-mcp` servers alive for more than 28 h)
   record orphans from before the proxy existed; this ADR does not claim they cannot recur on an unwrapped registration. A hook that
   tries to add a backstop buys nothing measured and, because `Stop` fires every turn, closes the user's own live browser each
   turn.
3. **For this repository's own registration only, profile ownership is a kernel `flock` lease, not a pattern kill.** The launch
   string sources `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh`, which claims slot 0 (the
   persistent `~/.cache/playwright-mcp-profile`) or slots 1..31 (`-<n>`) by a `flock` held on fd 9 by the proxy for the server's
   lifetime; the kernel releases it on any exit, including SIGKILL, and the proxy's children do not inherit it. The premise is
   narrower than the script's first draft said: the pinned server's `isProfileLocked` check throws "Browser is already in use for
   <dir>" BEFORE it launches anything, so a second server on a locked directory never tears the first one down. The lease exists
   because (a) the reaper it replaces killed siblings and removed `Singleton*`, the one operation that really lets two Chromes
   share a profile, and (b) a concurrent session needs a usable browser instead of that error. The rules, all in the script:
   - After winning the lock the launcher's `$PPID` is written to `<slot>/.pwslot.owner` (mode 600). Slot 0 waits (default 7 s,
     `PW_PROFILE_SLOT0_WAIT_S`, validated as a non-negative number) ONLY when the recorded owner is this session's launcher (a `/mcp`
     reconnect keeps it) or cannot be read. A different session's hold advances to the next slot at once; slots 1+ never wait.
     So slot 0 is not "non-blocking": it may block up to the budget, and only for a same-session or unknown owner.
   - A `SingletonLock` that names a live Chrome means a leftover or foreign Chrome owns the profile: the slot is skipped, never
     cleared (slot 0 gets the same wait-then-recheck). The probe fails toward busy and needs no `ps`: `/proc/<pid>` or `kill -0`
     (EPERM counts as alive); a live pid counts as a Chrome owner only when its comm is chrome-like (`chrom*`, `headless_shell`, or a Chromium derivative whose name
     STARTS with `msedge`, `brave`, `vivaldi` or `opera`, so a recycled pid named `operator` is not a browser) or unreadable, otherwise the
     pid was recycled and the stale lock is cleared; a lock naming ANOTHER HOST is never removed (so a renamed host or a copied
     home leaves slot 0 skipped until `rm <slot-0 dir>/Singleton*` is run by hand, see `agent-browser/SKILL.md`). A `SingletonLock`
     whose pid is not a positive integer (non-numeric, zero, or out of range) names no owner and counts as stale, which is the
     one exception to "fails toward busy"; Chrome never writes such a value.
   - Every slot-0 skip prints one stderr line (in the MCP log) saying the persistent profile's logins are not available in this
     session. A slot >= 1 that cannot be used (mkdir, lock file, open or an `flock` error) continues the search.
   - No usable `flock` (stock macOS has none; busybox `flock` lacks `-E`): slot 0 is claimed WITHOUT a lease when its
     `SingletonLock` is absent or provably stale, so the first session keeps the persistent profile once its Chrome exists;
     otherwise the unique fallback. A second session that starts before the first one's browser exists (Playwright starts the
     browser lazily, so there is no `SingletonLock` yet) also gets slot 0 and Playwright's "already in use" error. 32 busy slots
     also use the unique fallback.
   - The unique fallback is `<base>-p<pid>` (`$base-p$$`: a non-numeric infix so it never aliases slot N), created by the script
     with mode 700, with a stderr note naming the cause. The script never kills anything.
   - Teardown timing: the old proxy's teardown is usually well under 5 s and up to about 15 s in the worst case
     (`STDIN_CLOSE_WAIT_S` 0.2 s, then up to `GRACE_S` 5 s after SIGTERM, up to 5 s after SIGKILL, then up to 5 s for the child
     wait; derived from `Proxy.teardown`, `grep -n -E 'STDIN_CLOSE_WAIT_S|GRACE_S'` on the proxy). The 7 s default is a heuristic;
     a miss lands the reconnect on slot 1 with the stderr note, not on an error.
4. **The plugin registration gets a conditional bundled-Chromium fallback, in the proxy.** The proxy gains an opt-in boolean flag
   `--chromium-fallback` (before `--`). With it set, no `--browser` in the server argv, `PLAYWRIGHT_MCP_BROWSER` unset and no
   Google Chrome executable at the platform path, the proxy appends `--browser chromium --sandbox`. Playwright maps `chromium` to
   the bundled `chrome-for-testing`, whose Linux default is `chromiumSandbox: false`; `--sandbox` overrides that default, so the
   fallback browser keeps the Chromium sandbox like real Chrome. Elsewhere the check is a no-op. Flag absent, the child argv is
   byte-identical to before. No refusal moves: `--no-sandbox`, `PLAYWRIGHT_MCP_SANDBOX` and config `chromiumSandbox:false` stay
   refused, `--executable-path` stays refused, and a caller-supplied `--sandbox` stays allowed (it can only enable the sandbox).
   An explicit `--config` / `PLAYWRIGHT_MCP_CONFIG` browser choice is overridden by the CLI `--browser chromium` on a Chrome-less
   host. The CTO's binding ruling on this decision is Option 2 (sandbox kept on); see Alternatives for what was rejected.
5. **`PLAYWRIGHT_MCP_PING_TIMEOUT_MS=0` is added to both registrations as an inert latent-hazard guard, and is not the fix.** It
   does nothing on stdio in 0.0.78 or 0.0.83. It was an operator request and is kept, labelled as a guard. It is kept because the
   proxy answers any server-originated `ping` with JSON-RPC -32601 (`relay_server_message` relays only `roots/list`), so a future
   `@playwright/mcp` that starts the heartbeat on stdio would have `server.ping()` fail at once and `server.close()` the browser.
   Value 0 returns before the heartbeat starts (`startHeartbeat` begins `const timeout = pingTimeout(); if (timeout <= 0) return;`,
   present in both versions). The pin-bump checklist below carries the re-verification. Making the proxy answer `ping` is a
   separate, tracked change.

## Proven and not proven

**Proven** (commands above):

- The `Stop` hook SIGTERMs every Playwright Chrome of the invoking user at the end of every turn.
- 14 of 15 observed failures on 2026-10-04 have a hook kill, from any session, inside their window.
- The heartbeat cannot be the cause on stdio in 0.0.78 or 0.0.83, because the stdio transport passes `runHeartbeat=false`.
- With the proxy SIGKILLed, no browser descendant outlived it for headless bundled Chromium (three runs, 0.04 s). Headed real
  Chrome and the unwrapped 0.0.75 server of cron-ux-audit were not measured.
- Concurrent launches do not share a slot, for 12 launches on this host. Two review seats found that launches started in the same
  instant could both take slot 0, because the `flock` capability probe locked one shared inode (`/dev/null`) and read a lost
  race (rc 75) as "no usable flock". The probe now reads 75 as proof `-E` works. The lifetime suite has a row that releases 12
  lease scripts together under one HOME and asserts 12 distinct profiles and zero "no usable flock" notes, and a mutant that
  restores the strict probe goes red (`grep -n 'BAR_N=' plugins/soleur/skills/agent-browser/test/playwright-mcp-lifetime.test.sh`).
  The 20- and 34-launch figures in the review are manual seat measurements, not suite rows, and the proof is for util-linux
  `flock` only.
- Without `--browser chromium`, the plugin registration cannot launch a browser on a host with no Google Chrome (reproduced on
  this host only).
- The fallback's `--sandbox` reaches the pinned config: resolving `{browser:'chromium'}` gives `chromiumSandbox false` and
  `{browser:'chromium', sandbox:true}` gives `true` (2026-10-04, the CTO probe of `resolveCLIConfigForMCP` against 0.0.78; the
  source anchors, `validateBrowserConfig` and `configFromCLIOptions`, were re-read for this record).
- **The plugin registration's browser survives turn ends and idle gaps with the `Stop` hook removed (2026-10-05, two runs, one host).**
  `claude` 2.1.289 `-p --plugin-dir <worktree>/plugins/soleur` (`4fea153121`) with `--input-format stream-json --output-format
  stream-json --include-hook-events --verbose`, `PLAYWRIGHT_MCP_HEADLESS=1`, `--allowedTools mcp__plugin_soleur_playwright__*`,
  stdin held open on a FIFO, three turns. The `init` event names the loaded plugin (`soleur@inline`, the worktree path), so the
  loaded copy was asserted and not assumed. **Run 2 carries the acceptance.** Turn 1 navigated to a `data:` page whose title is a
  unique marker. Turn 2's snapshot completed 80 s after turn 1's `Stop` and turn 3's 26 s after turn 2's (transcript timestamps; only the
  first gap exceeds the recipe's 60 s). Both snapshots returned the marker page, not `about:blank`, and no "Target page, context or
  browser has been closed". The transcript's three `stop_hook_summary` records (13:44:44Z, 13:46:06Z, 13:46:34Z) each carry
  `hookCount: 2` and the commands `stop-hook.sh` and `unkept-promise-hook.sh`, none named `browser-cleanup`; the stream carried six
  `Stop` `hook_started` events. A separate `pstree -p <claude pid>` sampler (every 5 s, 13:45:25Z to 13:46:55Z) saw one Chrome main
  process, pid 1471574 started 13:44:43Z, under the child throughout, which spans the second and third `Stop`; it was already
  alive when sampling began, about 40 s after the first `Stop`, so it survived that one too. **Run 1** used the same recipe with
  `about:blank` and 75 s and 20 s gaps and agreed (six `Stop` events, three results, no error), but it had no marker and no pid
  sampler, which is why run 2 exists. Limits: one host and one pass; no positive control, because the pre-fix copy
  `4dbd1affe8eb` (still on disk, orphaned) has a plugin registration without `--chromium-fallback` and cannot launch here, so
  "the removed hook would make three" is read from that copy's `hooks.json` and not from a stream; the sampler started after the
  first `Stop`; the project registration was not exercised (below).
- **Slot allocation across two real sessions (observed, not a lease proof).** While run 2 ran, the interactive session held slot 0
  (`.pwslot.owner` names its pid, written 13:24:59Z) and the child's project-registration slot script took slot 1 (names the
  child's pid, written 13:44:39Z, before its first navigate). No browser was launched from either project registration, so this
  shows Decision 3's "a different session's hold advances to the next slot at once" and not that a first browser keeps answering
  when a second launches.

**Not proven:**

- **Idle survival on the project registration, and the lease under a live parallel session (recipe step 4).** The run above used
  `--allowedTools mcp__plugin_soleur_playwright__*`, so the project registration's browser (headed, `channel: chrome`, slot lease)
  never launched: this host has no Google Chrome at `/opt/google/chrome/chrome`, and an earlier run with both registrations allowed
  failed both launches ("Chromium distribution 'chrome' is not found" on the project one; "Browser is already in use" on the
  plugin one, because the launching interactive session's own browser held that profile). That run was INCONCLUSIVE, and its
  output was not kept. Removing the hook is plugin-level, so it plausibly covers both registrations, but that is an inference.
  Step 4 itself (the first browser still answering while a second process starts) was not run; a Chrome-less variant is possible
  on the plugin registration, where the second process should get "Browser is already in use" while the first still answers.
  The operator took step 4 out of the acceptance check (Status). #9281 stays open for it.
  Recipe, kept so a pin bump or a hook change can re-run it (the driver script was not kept):
  1. From a checkout carrying the change, start ONE headless process that stays alive across turns:
     `claude -p --plugin-dir <checkout>/plugins/soleur --input-format stream-json --output-format stream-json
     --include-hook-events --verbose`. Keep its stdin open (a FIFO) and send three user turns as stream-json lines: a
     `browser_navigate` to a `data:` page with a unique title, then more than 60 s later a `browser_snapshot`, then a third. Separate
     `-p` calls do not work: each ends its MCP server. On a display-less host export `PLAYWRIGHT_MCP_HEADLESS=1`. A launch error on
     the first `browser_navigate` makes the run INCONCLUSIVE, never a pass.
  2. Assert which hooks loaded, do not assume it: the `init` event names the loaded `soleur` path. Pass only if the transcript
     (`~/.claude/projects/<slug>/<session>.jsonl`) carries one `stop_hook_summary` per turn, none of whose `hookInfos[].command`
     values names `browser-cleanup`, and each `hookCount` equals the `Stop` commands the loaded `hooks.json` registers
     (`jq '[.hooks.Stop[].hooks[]]|length' <plugin>/hooks/hooks.json`; 2 here, and a user-global `Stop` hook raises it):
     `jq -c 'select(.subtype=="stop_hook_summary")|{hookCount,cmds:[.hookInfos[].command]}' <transcript>`. A `browser-cleanup`
     command means the installed copy won; the run says nothing about the fix, so update and retry.
     A stream `Stop` event carries no `command` field (observed 2026-10-05, claude 2.1.289; one real `--include-hook-events` line:
     `{"type":"system","subtype":"hook_started","hook_id":"a3635fb3-7d9a-46fc-a7fe-0c7f79b19ae8","hook_name":"Stop","hook_event":"Stop","uuid":"b1e4ef41-5546-47d6-8139-16789d338fb3","session_id":"d2add08c-c834-418f-a084-7f8c2ca3fede"}`;
     the `hook_response` adds `outcome` and `exit_code`), so the stream can only be counted, never asked which hook ran.
  3. Survival, not only absence of the hook: every snapshot must return the marker page (a relaunched browser reports
     `about:blank`), and one Chrome main process, found under the child with `pstree -p <claude pid>` (not a `-f` pattern search of
     the process list, which matches its own command line here), must have a start time before the first `Stop` and still be
     present after the last. The older `attachment`-based filter, `jq -c 'select(.attachment.hookEvent=="Stop" and
     (.attachment.command|tostring|test("browser-cleanup")))' <transcript> | wc -l`, is supplementary only. It sees only hooks that
     printed, so it printed 0 on both runs whether or not the removed hook had been loaded (the child transcript has no `Stop`
     attachment at all), and it is not equal to the kill-text filter: over this project's transcripts it printed 169, and 155 with
     `and (.attachment.stderr|tostring|test("Browser cleanup: killed"))` added, the difference being `hook_non_blocking_error`
     rows (exit 127, script missing) from a session whose registry still names the removed script (2026-10-05, a point-in-time
     count). A bare `grep -c` of the kill sentence is not the check: the sentence also appears in quoted text such as this ADR.
  The user's own interactive session still needs a restart by the USER (an agent cannot restart its own host); a `/mcp`
  reconnect reuses the cached `.mcp.json` command and does not reload hooks.
- **That a user's loaded plugin copy has the hook removed.** On this host the installed copy was `4dbd1affe8eb` (registers
  `browser-cleanup-hook.sh`) on 2026-10-04, and `claude plugin update soleur@soleur` took it to `4fea15312139` (two `Stop`
  commands) at 2026-10-05T13:21Z; `4dbd1affe8eb` is orphaned on disk. The fix reaches another user only after the plugin carrying
  this change is released and installed, then a restart by that user; the installed version is a git sha, so an update before the
  release carries nothing. Not measured: any other user's machine.
- **Headed real Chrome after a proxy SIGKILL, and the unwrapped cron-ux-audit server.** See Decision 2 and Consequences.
- That the fix removes every browser-closing cause. A hook in a user's global configuration, a Wayland or Vulkan GPU crash (same
  error string, different cause; mitigated separately in `.claude/playwright-mcp.config.json`) or a launch race still produces the
  same message. The learning documents the correlation method for finding another killer.
- That a Chrome-less host can run the sandboxed fallback. On a host without unprivileged user namespaces the first browser call
  fails closed (Consequences). That path was not exercised: this host's `unshare -Ur true` succeeds.

## Alternatives Considered

- **Keep the hook, scope it to the session's own process tree.** Rejected. `Stop` fires every turn, so even a session-scoped
  kill closes that session's live browser at each turn end. The mechanisms in Decision 2 already cover the orphan case.
- **Replace it with a `SessionEnd` hook.** Rejected. It adds a hook for a duty the same mechanisms already perform, and
  one more row for the web-parity and Devin ledgers to keep.
- **Brief: set the ping timeout as the fix.** Rejected as a fix; kept only as the guard in Decision 5.
- **Brief: track the PID this launch owns and kill only that.** Rejected. The proxy's process-group teardown already owns the
  server tree; PID bookkeeping adds state for nothing.
- **A throwaway per-session profile directory.** Rejected. It loses persistent logins that credential-handoff flows depend on
  (2026-05-12 learning). Slot 0 stays persistent.
- **`--isolated`.** Rejected. It wipes OAuth sessions on respawn (2026-05-12 learning). It also cannot be combined with the
  proxy's injected user-data-dir: the pinned server throws "Browser userDataDir is not supported in isolated mode."
- **A global `flock` mutex around the whole server.** Rejected. It serialises all sessions' browsers to avoid a collision the
  per-slot lease already avoids.
- **Unconditional `--browser chromium` in the plugin registration.** Rejected. It regresses Chrome-present hosts that have no
  bundled download and drops real Chrome's working sandbox.
- **Wrap the plugin registration in a `bash -c` launcher so it gets the slot lease too.** Rejected: the ADR-213 2026-09-18
  addendum rejected a `bash -c` launch in the plugin manifest as an unauditable shell string. The consequence is stated in
  Consequences: the plugin registration has no lease.
- **Put the lease inside the proxy (Python `fcntl.flock`) so both registrations get it.** Not chosen in this change, and the
  alternative that would cover both registrations: the proxy already resolves `--user-data-dir-name` and owns the child's
  lifetime, there is no `bash -c` string in a manifest, and it removes the no-`flock` host gap. It is a larger change to the
  credential-guard proxy than this PR, whose scope is the lifetime fix; it is recorded here as the follow-up that closes the
  plugin registration's limitation, to be tracked as an issue when the PR ships.
- **Keep the fallback as shipped (unsandboxed) and only disclose the missing sandbox (log line, first-tool-result notice).**
  Rejected. The browser holds a persistent profile with logged-in vendor sessions and opens arbitrary pages; a disclosure the user
  never reads does not reduce a renderer compromise, and the brand-survival threshold for that outcome is single-user-incident.
  One argv token removes the exposure.
- **An opt-in env to enable the sandbox-less fallback.** Rejected. It makes the unsafe browser reachable by one environment
  variable on an unsafe-by-default host class, adds a new switch the proxy would have to audit, and the operator is non-technical.
  Failing closed with a clear remedy is the safer default and needs no switch.
- **Drop `--chromium-fallback` from the shipped registration.** Rejected. It also removes the sandboxed bundled browser from
  every Chrome-less Linux host where user namespaces work, which is the common case, and leaves the original "Chromium
  distribution chrome is not found" failure in the plugin everyone receives.
- **A vetted `--config` carrying `browser.launchOptions.chromiumSandbox:true`.** Rejected in favour of `--sandbox`: same effect,
  but a config path to resolve and vet, and it interacts with the existing `--config` refusals.

## Consequences

- Once the plugin carrying this change is installed, a turn ending no longer closes any Playwright browser. Until then, on a
  host whose installed copy still registers the hook, the per-turn kill continues (Decision 2 and the live check above). The same
  removal ends a host-level process kill in web Concierge sessions once an image carries the new plugin (ADR-093 amendment
  2026-10-04; delivery follows ADR-080's image rebuild), which is the concern issue #9281 raised; that issue is referenced, not
  closed.
- A browser is no longer reaped at turn end, so a browser the agent never closes lives as long as its session. The mechanisms in
  Decision 2 bound that to the session. Nothing reaps it at turn end, so agents call `browser_close` when a flow finishes;
  `agent-browser/SKILL.md` and `qa/SKILL.md` carry that duty, and the retired rule's breadcrumb points there.
- **Mixed-version rollout is not one-time.** An old launch string's `pkill -9 -f` patterns are unanchored prefix matches
  (`[c]hrome.*$prof` matches `...playwright-mcp-profile`, `...-3` and `...-p4242`, but not `soleur-playwright-mcp-profile`; the
  proxy and server patterns have the same prefix form). On EVERY start and `/mcp` reconnect an old-style session can kill the
  proxy, server and Chrome of ANY slot of a new-style session, until that old session is restarted. On this host 99 of 103
  worktrees still carry the old string: `for w in $(git worktree list --porcelain | sed -n 's/^worktree //p'); do grep -aq pkill
  "$w/.mcp.json" && echo old; done | wc -l` printed 99, and the worktree count was 103 (2026-10-04, this branch's own checkout
  among the four that do not). The repository cannot change a launch string a worktree already loaded.
- A launch that finds slot 0 held by THIS session's previous launcher (a reconnect) starts up to 7 s later, within the 30 s MCP
  connect timeout. A launch that finds slot 0 held by another live session takes slot 1 at once, with a stderr note and without
  the persistent logins.
- The lock is tied to the proxy, not to Chrome: a SIGKILLed proxy frees its slot while Chrome may live on. The owner-alive
  `SingletonLock` check is what keeps that slot from being reused (a Guard-2 row covers "lock free, live Chrome owner").
- **The plugin registration has no lease.** A second concurrent session on the plugin profile
  (`soleur-playwright-mcp-profile`) gets Playwright's "Browser is already in use for <dir>, use --isolated to run multiple
  instances of the same browser" for the first session's whole lifetime: before this change the `Stop` hook happened to free the
  profile at every turn end, now nothing does. Nothing is killed. `--isolated` does not apply: the proxy always injects a
  user-data-dir and the pinned server rejects the combination, and this ADR rejects `--isolated` anyway. The remedy is to close the
  other session's browser (`browser_close`) or end that session. The lease-inside-the-proxy alternative above would cover both
  registrations.
- The numbered slots are bounded (32 directories, reused). The `<base>-p<pid>` fallback is not: the script creates one directory
  per fallback launch (mode 700) and nothing reaps it. Slot and fallback directories are additional at-rest credential stores,
  not "no new credential path": any login done in one persists there until the directory is removed, removal is manual, and only
  the `-p<pid>` fallbacks are safe to remove (numbered slots hold the persistent logins). `agent-browser/SKILL.md` carries the
  removal test.
- The fallback browser runs WITH the Chromium sandbox. In `coreBundle.js` `validateBrowserConfig` defaults `chromiumSandbox` to
  `channel !== "chromium" && channel !== "chrome-for-testing"` (false for the fallback) only when it is undefined; `--sandbox` sets
  it true through `configFromCLIOptions`, and the launcher adds `--no-sandbox` only when it is not true. The cost is a launch
  failure, not a weaker browser: on a host without unprivileged user namespaces (Ubuntu 23.10+/24.04 AppArmor restriction,
  `max_user_namespaces=0`, default-seccomp containers) or as root, the first browser call fails with Chromium's sandbox error
  (Playwright's own text suggests `chromiumSandbox: false`, which the proxy refuses in every spelling), and the proxy never
  offers a way past it. That host had no browser before this change either. The remedy is to install Google Chrome, which needs
  host privilege; the unprivileged-userns sysctl is not recommended. First use on a host with no bundled download prints
  Playwright's own instruction, which names the UNPINNED `npx @playwright/mcp install-browser`; the verified, pinned command is
  `npx @playwright/mcp@0.0.78 install-browser chromium` (`--dry-run` 2026-10-04: rc 0, resolves "playwright chromium v1232").
- The `.mcp.json` edits load only on a full Claude Code restart.
- **cron-ux-audit lifetime.** The web platform's only Chromes are the per-fire `cron-ux-audit` ones: an UNWRAPPED
  `@playwright/mcp@0.0.75` under a detached `claude -p` child (`apps/web-platform/server/inngest/functions/cron-ux-audit.ts`;
  `_cron-claude-eval-substrate.ts` spawns with `detached: true` and signals `process.kill(-pid, ...)`). The removed `Stop` hook
  was the only turn-end reaper for such Chromes, and it could also kill them mid-run. Now `ux-audit/SKILL.md` step 8 calls
  `browser_close`, and a group kill of claude's group does not reach Chrome (it is `detached`), so after the run Chrome's end of
  life is the upstream pipe-EOF and the server's stdin watchdog. That mechanism was measured only for 0.0.78 under the proxy, not
  for the unwrapped 0.0.75; production containers also run with `--init` and the workspace is ephemeral. The change reaches the
  web platform only after the image rebuild (ADR-093 amendment, ADR-080).

## Pin-bump checklist

When `@playwright/mcp` is re-pinned, re-verify, against the new pin's `coreBundle.js` and not from memory:

- The heartbeat is still not started on stdio: `grep -nE 'connect\(serverBackendFactory'` shows `false` for the stdio branch, and
  `startHeartbeat` still returns on a zero timeout (Decision 5).
- The fallback keeps its sandbox: resolve the new pin's config for `{browser:'chromium', sandbox:true}` and expect
  `chromiumSandbox: true` and no `--no-sandbox` in the launch args; confirm `--sandbox` is still a declared flag.
- `isProfileLocked` still throws before launching (the premise of Decision 3) and `install-browser` is still rewritten to
  `install` in `cli.js` (the SKILL.md remedy).
- Playwright still spawns Chrome `detached` and the server's stdin watchdog is still installed (Decision 2).
- The idle-survival recipe under "Not proven" still passes with the new pin or after any change to `plugins/soleur/hooks/hooks.json`
  (the `stop_hook_summary` count, the marker page and the surviving Chrome pid).

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
  named a single persistent profile. It now states the conditional bundled-Chromium fallback (sandbox kept on), the slot-leased
  project profile (slot 0 may wait a bounded time for a same-session owner) and the inert ping env guard. `snapshotGuard` and its
  edge text gain one clause for the opt-in `--chromium-fallback` argv behaviour (`--browser chromium --sandbox`).
  `model.likec4.json` is regenerated with `bash plugins/soleur/scripts/render-c4-model.sh`.
