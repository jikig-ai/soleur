---
title: "A Stop hook killed the live Playwright Chrome every turn; the heartbeat theory was refuted from source"
date: 2026-10-04
category: bug-fixes
tags: [playwright, mcp, hooks, stop-hook, process-lifetime, diagnosis, correlation]
module: plugins/soleur/hooks/hooks.json
issue: none
related: [9281]
---

# A Stop hook killed the live Playwright Chrome every turn; the heartbeat theory was refuted from source

The decision, its alternatives and the unproven live check are in
[ADR-271](../../../engineering/architecture/decisions/ADR-271-browser-lifetime-belongs-to-the-launching-session.md). This
learning keeps the diagnosis: what the symptom looked like, how the cause was found, how a wrong theory was refuted, and the
method to reuse the next time a browser tool "closes on its own".

## Problem

The Playwright MCP browser vanished within tens of seconds of launch. The next call returned `browserBackend.callTool: Target
page, context or browser has been closed` until `browser_close` forced a fresh backend. The window disappeared together with
its process, with no crash.

## Root cause

`browser-cleanup-hook.sh`, registered on the plugin's `Stop` event, ran `pgrep -f 'chrome.*--remote-debugging-pipe'` and sent
SIGTERM to every match. `Stop` fires at the end of every assistant turn, not at session exit. SIGTERM makes Chrome exit
gracefully (exit 0, no core dump), so "idle" was simply "the turn ended". The 2026-04-03 learning that introduced the hook
assumed `Stop` meant session exit; that assumption is the root error (a correction note is appended there).

## Why the first theory (the ping heartbeat) was wrong

The request's working theory was that the server's heartbeat closes the browser after a ping timeout
(`PLAYWRIGHT_MCP_PING_TIMEOUT_MS`). The source settles it without running anything:

1. Find the pinned package in the npx cache: `ls ~/.npm/_npx/*/node_modules/@playwright/mcp/package.json` and read each
   `version` (0.0.78 and 0.0.83 were both cached).
2. Find who passes `runHeartbeat`:
   `grep -nE 'connect\(serverBackendFactory' ~/.npm/_npx/*/node_modules/playwright-core/lib/coreBundle.js`. The stdio branch of
   `start()` (`options.port === void 0`, a `StdioServerTransport`) passes `false`; so does the SSE branch; only the streamable
   HTTP session branch passes `true`. Same result in both versions.
3. Our registrations are stdio, so the heartbeat never starts there. That is the refutation. A second argument is inference,
   not exercised against the pinned server: after `server.close()` a stdio server would be expected to stop reading stdin, so a
   later call would be expected to hang, not return a tool-level "Target page ... closed". Do not cite it as measured.

Line numbers differ between installs; anchor on the `connect(` calls and the `if (runHeartbeat)` guard, not on a number.

## The correlation method (re-run on 2026-10-04)

A cause that fires "sometimes" has to be matched against the failures it should explain.

1. List the failures. The persisted MCP log is
   `~/.cache/claude-cli-nodejs/<project-slug>/mcp-logs-<server>/<start-timestamp>.jsonl`. Failures are the entries whose
   `error` field contains `Target page, context or browser has been closed` (the matching `debug` line repeats each one, so
   `grep -c` shows twice the failure count: 30 lines, 15 failures).
2. List the kills. Each time the hook ran it printed `Browser cleanup: killed N orphaned Playwright Chrome process(es)`, and
   Claude Code stored that as an attachment in the session transcript
   (`~/.claude/projects/<project-slug>/<session>.jsonl`) as an entry whose `attachment.type` is `hook_success` and
   `attachment.hookEvent` is `Stop`; the text is in `attachment.stderr` (not `stdout`) and the registered command is in
   `attachment.command`. Filter on those fields: the same sentence also appears in quoted text (plans, tool output,
   queued commands) and counting those inflates the total. Take every transcript of the day, in every project directory of the
   repository including its worktrees: any session's hook kills every session's Chrome.
3. Match. For each failure, take the window from the previous successful tool completion (`Tool '...' completed
   successfully`) to the failure's timestamp, and ask whether any kill from any session falls inside it.

Filter used for the agent-executable form: `cat ~/.claude/projects/<slug>/*.jsonl | jq -c 'select(.attachment.hookEvent=="Stop" and
(.attachment.command|tostring|test("browser-cleanup")))' | wc -l`. It is EQUAL to the kill-text filter, not stronger: run over
this project's transcripts on 2026-10-05 it printed 142, and also requiring `(.attachment.stderr|tostring|test("Browser cleanup:
killed"))` printed 142 (107 and 107 on 2026-10-04; a point-in-time count that grows while an installed copy still fires; a
`zzz-no-such-hook` control printed 0). A transcript records only hooks that printed something, and `browser-cleanup-hook.sh` prints
only when it killed, so a loaded but idle hook leaves no attachment: the filter detects a loaded hook only when a Chrome was alive
at that `Stop`. The two other `Stop` hooks print nothing, so they leave no `command`-carrying attachment either (the same `select`
with `test("unkept-promise-hook|stop-hook")` printed 0, against 143 `Stop` attachments that carry a `command`); do not assert "the
other hooks loaded" from a transcript.

Result: 18 kill events on 2026-10-04 from 5 sessions at analysis time (re-run during the review: 26 from 5 sessions; a first pass that matched the bare sentence found 29 and was wrong, for
the reason in step 2; the 14 of 15 below is the same under both); 15 failures; **14 of 15 have a kill inside their
window.** The 15th failed 3 s into a `browser_run_code_unsafe` call and its nearest kill is stamped 26 ms after the failure.
Transcript attachments are written after the hook finishes, so that ordering cannot be resolved; it is counted as a
non-match and that is the figure to quote. The script was a throwaway Python file in the session scratchpad, not committed;
the three steps above are the whole method.

## Stop fires per turn

The kill entries in the transcript are `hook_success` attachments whose `hookEvent` is `Stop`, one per turn end, and the
repo's own ralph-loop `stop-hook.sh` is a documented per-turn firer (`2026-03-09-ralph-loop-crash-orphan-recovery.md`: "stop
hook to fire on every turn"). A hook that must run "on session exit" is a `SessionEnd`
hook; a `Stop` hook that kills anything the user is still using will fire on the next turn boundary.

## Finding any other killer

Before concluding "no hook kills it", enumerate every source the harness will execute, and write down which were searched:

- project `.claude/settings.json` and `.claude/settings.local.json`, and user `~/.claude/settings.json`;
- every enabled plugin's `hooks/hooks.json`: the repository's `plugins/<name>/hooks/hooks.json` and the installed copy named by
  `installPath` in `~/.claude/plugins/installed_plugins.json` (here `~/.claude/plugins/cache/soleur/soleur/<version>/`, which
  still registers the hook until the plugin is updated);
- the scripts those commands invoke, and the MCP launch strings in both `.mcp.json` files;
- then look for `kill`, `pkill`, `killall`, `pgrep` in them, and for any `Stop` or `SessionEnd` registration.

When the closer is not a hook, the proxy's own MCP log (`~/.cache/claude-cli-nodejs/<slug>/mcp-logs-<server>/<start>.jsonl`, the
`Server stderr:` entries) separates the cases. The proxy prints `child pgid N` when it starts the server and `child exited
rc=<rc> signal=<sig> (<why>)` at teardown, so a `child exited` line near the failure means the proxy tore the server down (stdin
EOF or a signal to the proxy). A kill that hits only Chrome (a pattern killer, an OOM kill, a crash) logs nothing in that file:
the server stays alive, so there is no `child exited` line, and the only trace is the failing tool call itself. A SIGKILLed proxy
also logs nothing. "No proxy line" therefore does not exonerate anything; look at transcript hook attachments and the kernel or
journal log instead.

Searched on 2026-10-04 with `git grep -n -a -E '\bkill\b|pkill|killall|pgrep' fa8bc5961f -- 'plugins/soleur/hooks/*.sh'
'plugins/soleur/hooks/lib/*'`: executable code matches in two files. `browser-cleanup-hook.sh` is the only one that signals by
pattern (`pgrep -f ...` then `kill "$pid"`); `stop-hook.sh` has a `kill -0 "$OWNER_PID"` liveness probe, which sends no signal;
every other hit is a comment. The project and user settings register no `Stop` or `SessionEnd` hook.

## No browser outlives its launcher (P5 probe)

Removing the hook raised the question of orphans. Measured with a throwaway driver (the procedure is here; the driver itself was
not kept, so the figure cannot be re-run from the records): run the proxy with `--headless --browser chromium` on a temporary
profile, complete a `browser_navigate about:blank`, record every descendant of the spawned proxy, SIGKILL the proxy so its
teardown cannot run, and poll `/proc` until each descendant is gone. Three runs: npm exec, the node server, Chrome's main process
and its renderer, zygote, gpu and utility processes were all gone within 0.04 s, Chrome first. Mechanism, by elimination and not
isolated: `Proxy.teardown` cannot run when the proxy is SIGKILLed, so only the server's stdin-close watchdog and Chrome's
`--remote-debugging-pipe` EOF exit apply (Playwright spawns Chrome `detached`, so the proxy's `killpg` never reached it anyway).
Limits: headless bundled Chromium only. Headed real Chrome (the project registration) relies on the same upstream pipe-EOF
behaviour, unmeasured, and so does the unwrapped 0.0.75 server of cron-ux-audit. ADR-213's older "reaped by the same group
teardown" describes `killpg` by a live proxy, a different mechanism.

## Mixed-version facts (corrected)

The first draft said an old launch string would kill a new-style session's Chrome "once". That is wrong. The old string's three
`pkill -9 -f` patterns end in `.*$prof` and are unanchored, so `[c]hrome.*$prof` matches the Chrome of slot 0, of every numbered
slot (`...-3`) and of every `-p<pid>` fallback (checked with Python `re.search` on synthetic command lines; it does not match the
plugin's `soleur-playwright-mcp-profile`). On every start and `/mcp` reconnect an old-style session can therefore kill any slot of a
new-style session until that old session is restarted. Count on this host on 2026-10-04: `for w in $(git worktree list --porcelain
| sed -n 's/^worktree //p'); do grep -aq pkill "$w/.mcp.json" && echo old; done | wc -l` printed 99 of 103 worktrees. Delivery also
matters: the hook is removed from the repository, but the installed plugin copy under `~/.claude/plugins/cache/` keeps
registering it until `claude plugin update soleur@soleur` and a restart by the user (`jq -c '.hooks.Stop[].hooks[].command'
<installPath>/hooks/hooks.json`, with `installPath` from `~/.claude/plugins/installed_plugins.json`).

## Session Errors

1. **The lead's heartbeat theory was wrong and was published to the user before it was verified.** The ping heartbeat, the
   theory carried in the request, was presented to the user as the likely cause before anyone had read the server source; the
   read that refutes it is one `grep` over the cached `coreBundle.js`.
   - **Prevention:** before telling the user a cause for a tool failure, run the one command that could falsify it (here: who
     passes `runHeartbeat`), and until it has run label the theory a hypothesis in the message, not a finding.
2. **The lead's first hook search covered only project and user settings and missed the plugin's `hooks.json`.** The
   conclusion "no hook or script kills it" was drawn from `.claude/settings.json` and `~/.claude/settings.json`, while the hook
   was registered by the plugin and its output (`Browser cleanup: killed 3 orphaned Playwright Chrome process(es)`) was
   already visible in the session transcript.
   - **Prevention:** "which hooks run" means every source in "Finding any other killer" above (settings, each enabled plugin's
     `hooks.json` including the installed copy, MCP launch strings); state the sources searched next to any negative claim, and
     grep the transcript for hook output lines, which name the hook outright.
3. **The Playwright token-creation attempt failed repeatedly because the Stop hook killed the browser each turn.** Each retry
   began a new turn, the hook ended the previous turn's browser, and the next call returned "Target page, context or browser
   has been closed"; the attempt was retried several times as if the failure were transient.
   - **Prevention:** the same "closed" error at two or more turn boundaries is systematic, not transient: stop retrying and
     look for something killing the browser (the correlation method above). Until the fix is live, complete a whole browser
     flow inside one turn.
4. **The review panel found defects the author's own suites could not reach.** The first lifetime suite shipped with a P1 that
   its own mutation batteries were blind to: seven fixture-relative `cp` sites with no `assert_fixture_dir` guard, so the
   fixture-relative-assert baseline went red in CI. It also had a slot-script liveness probe that failed OPEN when `ps` was absent
   (a live Chrome's lock would have been removed), a bundled-Chromium fallback that silently selected an unsandboxed browser, a
   silent slot-0 skip, a flat 7 s wait for every contended launch, no flock-less host path, and one decoy shape per guard axis.
   Each guard quantified over a set (decoy shapes, scanner axes, Chrome paths, verdict helpers, slots) and its fixtures
   instantiated one member per axis, so a mutation of the guard's own population stayed green.
   - **Prevention:** before calling a guard suite done, list the set each guard quantifies over and add one hostile fixture per
     member axis; run the repository's fixture-relative and fixture-dir-operand lint suites on every new suite, not only the
     suite itself; and treat any probe that shells out to an optional binary (`ps`) as fail-open until a row runs it absent.
5. **Prose restated a claim without the command that falsifies it.** The first ADR said "only executable match", "kills once",
   "5 s grace", "non-blocking" and "the driver is the scratchpad probe named in the learning"; each was contradicted by a
   one-line command or by the code.
   - **Prevention:** for every causal or universal sentence in an ADR or learning, write the command that would falsify it beside
     it, run it, and re-derive each count at write time; mark an inference as an inference.
6. **A fix introduced a contention bug that the author's suite and the first panel could not reach.** The slot script's new
   `flock` capability probe took an exclusive lock on `/dev/null`, one inode shared by every launch, so launches started in the
   same instant made each other's probe fail and fell into the no-lease branch. Two review seats found it independently: a
   30-trial race ended with 2 trials sharing slot 0, and 20- and 34-launch barrier runs gave duplicated profiles at the fix commit
   where the panel SHA gave 20 of 20 and 34 of 34 distinct. The suite's concurrent rows started their launches one after another.
   - **Prevention:** a probe that touches a resource every instance shares (`/dev/null`, a fixed path) is a contention point:
     treat its failure code as something concurrent peers can produce, and give every concurrency guard one row that releases at
     least a dozen instances together and asserts distinct results, plus a mutant that restores the strict probe.
7. **Guard 2 mutant 10 cost a review round.** It walked every process's fd table with one `readlink` per fd (about 18 s at about
   610 processes), so on a busy host the readiness wait gave up first and the suite read "mutant survived" for a guard that was fine.
   - **Prevention:** a fixture or mutant whose cost scales with the host's process count needs a bounded selector (one `find` over
     `/proc/*/fd`), and a readiness timeout must abort as unresolved, never be scored as a verdict.
8. **Decoys were shaped like the retired hook's pattern.** The Guard 1 decoys carried `chrome --remote-debugging-pipe
   --user-data-dir=...`, the shape the still-installed old `Stop` hook kills; with no suite running, five of six probes of that shape
   died on this host within about five minutes (the first after 13 s), so a decoy could be killed by the host and read as a dead scanner.
   - **Prevention:** a decoy must not match the pattern of any killer that may still be installed on the host running the
     suite; select it by pid in the shim and give it an argv no retired pattern can match.
9. **A test shim was keyed on a substring.** The proxy suite's `chrome-fs-shim.py` answered "no such file" for any path containing
   `chrome`, so six rows went red when the checkout path itself contained that word (worktrees are named after their task).
   - **Prevention:** a shim patches the exact strings the test controls and passes every other path through; run the block once
     from a copy of the tree whose directory name contains the shimmed word.
10. **A comparison adjective was asserted without printing both counts.** ADR-271 and this learning called the
    `attachment.command` filter "stronger" than the kill-text filter while their own positive control printed 107 for both.
    - **Prevention:** when a sentence compares two measurements, print both numbers next to it and let them decide the adjective;
      transcripts record only hooks that printed, so a quiet hook is invisible to either filter.
