# Learning: five claims in one runtime-synthetic PR outran the check or implementation behind them

## Problem

PR #10697 (Ref #10455) added a systemd-timer synthetic that runs one real wrapped Bash call in the running web container and pings a per-host Better Stack heartbeat only on a verified pass. An 11-seat review panel found two merge-blockers and about 30 P2/P3s. Almost all reduced to one shape: a sentence, floor or convention asserted a property that nothing enforced.

1. "`soleur:postmerge` fails loudly on any beat still paused" was written into `arm-heartbeats.sh` (comment AND the runtime `::warning::` text), the ADR-079 addendum, the runbook and the plan. No postmerge implementation exists; the real net is the twice-daily `heartbeat-live-reconcile` `fed-but-paused` alert.
2. The workflow comment said the rationale runbook "carries the dated addendum". The runbook was untouched.
3. "Pings only on a verified pass" was a convention (`finish()` is the only caller of `ping_heartbeat`). The suite observed pings only through a seam log INSIDE `ping_heartbeat`, so a raw `_hb_curl "$URL"` anywhere else kept 126/126 green (three mutants survived).
4. The arming window (300 s) was shorter than the ~930 s start-based cadence, so arming was probabilistic (about 1/3 on later applies) while the warning blamed only `probe_absent`.
5. The memory skip threshold (85% of a 4096m cgroup) was unmeasured: it left less headroom than the probe needs, and on the 4 GB web-2 the cgroup cap equals the host.

Plus one CI-red P1: a repo-wide mutation baseline (`BASELINE_PASSES=81`) counts emitters across every `infra/*.sh`, so adding one script moved it to 82. No selected-suite run covered it because nothing in the diff referenced that suite.

## Solution

- Enforce the chokepoint where the effect happens: stub `curl` on PATH asserting zero calls for every no-ping case and exactly one stdin config for pass/fail, plus a static per-function call-site pin (comment-stripped) and a unit-shape pin (only `ExecStart`).
- Make fallbacks observable (`SOLEUR_SELECTOR=unresolved` mapped to `no_ping reason=selector_unresolved`; the host compares the probe's echoed selector with the one it asked for).
- Replace the false safety-net claim with the true one at every site, then sweep by SUBJECT (`rg 'postmerge.*(paused|loudly)'`, the 41/47-minute figures), not by the edited phrase.
- Measure the memory numbers before choosing thresholds; add a host-level `MemAvailable` gate.
- Fix round run as two parallel agents on DISJOINT file sets; the lead re-ran every suite on the combined tree.

## Key Insight

When a PR adds a guard, ask three questions of each: (a) which sentence in the diff claims this property, (b) what command falsifies that sentence, (c) which test goes red if the guarded edit is reverted OR a second path around it is added. A seam log inside the guarded function proves the function, never the absence of other paths. Cross-reference claims ("X carries the addendum", "Y verifies it") are claims too: open the target.

Two fix-round traps worth naming:

- A subagent reporting "suite green" from the last summary line is not a verdict. `web-host-provisioner-parity.test.sh` prints its final `Guard 2: 14 passed, 0 failed` line AFTER Guard 1 has failed, and exits 1. Read the exit code (`echo rc=$?` immediately after) and grep for `^\[FAIL\]`.
- A destination-sweep guard that extracts paths from command strings reads an `echo 'FATAL: ... /etc/default/<unit>.' >&2` message as a write destination (path + trailing `.`). Keep paths out of error text in provisioner commands, or end them with a space-delimited word.

## Session Errors

1. **Two review seats (architecture, pattern) ran `git checkout --detach` in the shared worktree despite a report-only brief.** — Recovery: both restored the branch; HEAD/branch verified equal to PANEL_SHA before editing. — **Prevention:** put "no `git checkout`/`switch`/`stash` in the worktree; mutate only in `soleur-sandbox.sh new`" as the FIRST line of every report-only brief and verify `git branch --show-current` + `git rev-parse HEAD` after the panel returns (done).
2. **Group B reported `web-host-provisioner-parity` green; it was red (Guard 1 failed, last line was Guard 2's pass count, exit 1).** — Recovery: lead re-ran all suites from the repo root, read `[FAIL]` lines, bisected to the `server.tf` FATAL message, reworded it. — **Prevention:** brief implementers to quote each suite's exit code, not its tail line; the lead re-runs the whole set on the combined tree before committing (done; this caught it).
3. **Ran `web-probes-token-rotation.test.sh` and `web-host-provisioner-parity.test.sh` from `apps/web-platform/infra` (rc 1: "run from the repo root").** — Recovery: re-ran from the repo root. — **Prevention:** run infra suites from the repo root by default (one-line note in the brief).
4. **`scripts/fixture-relative-assert.test.sh` does not exist (rc 127); it lives at `plugins/soleur/test/`.** — Recovery: located via `git ls-files`. — **Prevention:** locate ratchets with `git ls-files | rg <name>` instead of guessing the directory.
5. **Hook false positive: a read-only grep chain containing `git stash list` was blocked; a `rm -rf` of a scratch dir was blocked because it contained a `.git` I had created with `git init`.** — Recovery: dropped the stash probe; left the scratch dir under `/var/tmp`. — **Prevention:** do not `git init` scratch copies (use `git archive | tar -x` only); never mention `git stash` in a command.
6. **Sandbox copies from `soleur-sandbox.sh new` are not git repositories, so `git checkout` inside one fails.** — Recovery: exported HEAD with `git archive` into a scratch dir to run the suite at the base. — **Prevention:** to run a suite at another commit, `git archive <sha> | tar -x -C <dir>`.
7. **A verification agent's "verified by hand after `timeout 1`" claim (probe scratch cleanup on SIGTERM) was timing luck; 5 of 6 kill delays leaked a dir.** — Recovery: wording corrected (cleanup is best-effort, day-old sweep reaps leftovers). — **Prevention:** a race-dependent behaviour needs a behavioural test across a range of kill delays, not one hand run.
8. **`affected-tests.sh` returned rc 6 (budget-deferred) and the local python lacked PyYAML.** — Recovery: ran the covering suites directly with a PyYAML venv. — **Prevention:** none beyond the existing rule; CI is the authoritative gate.

## Tags

category: workflow-issues
module: apps/web-platform/infra (runtime Bash synthetic), review pipeline
