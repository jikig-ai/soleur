# Learning: a dead-man alert is judged by what its evaluator can see; a guard-building PR fails open in its own helpers

## Problem

Two Better Stack logs alerts (`luks_monitor_host_timer_dark`, `claude_cost_capture_dark`) waited for one row per 24-27 h. The host was healthy (39 nightly passing rows since 2026-09-27), yet incident 1023423999 stayed open for 33 nights with `Current value: 0`. The same query returned 1 row with the archive arm and 0 rows from `remote()` alone, and the hot window measured about 1 h. So a 27 h window over a once-a-day row can never be satisfied if the evaluator reads only the hot window (INFERRED, not observed: the vendor exposes no evaluated value).

## Solution

Replace both alerts with Better Stack heartbeats fed by an hourly workflow that reads the archive (`scripts/deadman-heartbeat-feeder.sh`), beating only when a qualifying row exists in the old window; trigger it from the web-server watchdog clock because hourly GitHub cron delivery was measured too sparse; keep the Sentry monitor unrouted under the two-PR rule; born paused and owner-armed. Reviewed by a 12-seat panel and two fix rounds; every in-scope finding fixed inline.

## Key Insight

1. **Judge an alert by what its evaluator can see, not by what the query returns when you run it by hand.** A hand-run query with the archive arm was green while the live alert was blind. Measure the evaluator's window (`min(dt)` over `remote()`) before sizing any window.
2. **A guard-building PR's own helpers are the first thing to fail open.** The author's 266-case suite and ~40-row mutation battery were green while neutering any of the five verdict-grading helpers (`expect_red`, `static_red`, `wire_red`, `wf_check`, `ctl`) left the suite at 266/0. Every verdict-owning helper needs a control that drives it with a known-survivor and a known-wrong-reason input, and the control wrapper (`own_ctl`) needs its own control. Fix round 2 then found the same class again one level up (the wrapper), the denylist form of a pin (`/usr/bin/wget` hid the tool it listed) and a lexer that desynced on a quote inside an interpolation. Prefer closed sets (an allowlist of command words) over denylists, and an independent anchored count beside any lexed count.
3. **N seats converging on one finding is one finding.** Four seats independently flagged that the arming runbook pointer led to a block hard-wired to a different heartbeat; the fix was one section. Do the structural roll-up first.
4. **Arming prose must be owner-gated text that works as written.** A multi-block runbook run through `Monitor` loses shell state between blocks; make each block a complete script that pastes a helpers block at its top.

## Session Errors

1. **`gh issue create --body-file` failed because the body was written in the same Bash call (hook-gated)** — Recovery: Write tool first, then the create as its own call — Prevention: already a documented rule (the Phase 4 note on never heredoc-ing a body into the same command as a hook-gated `gh issue create`); I re-hit it, so the reflex is not wired. Recurring-but-covered.
2. **`pgrep -f` inside a `Monitor` command was blocked by the self-match hook** — Recovery: dropped the watcher, relied on the agent completion notification — Prevention: covered by `hr-monitor-not-run-in-background-for-polling` and the hook; poll rc/marker files, never `pgrep -f`.
3. **Three 47 MB PostScript files (`argparse`, `functools`, `os`) appeared untracked in the worktree root** — a Python snippet was piped to `bash`, where `import argparse` ran ImageMagick's `import` (an X screenshot tool) and wrote a screenshot named after each module. Recovery: deleted them (never staged; `git add -u` does not add untracked files) — Prevention: pass Python via `python3 - <<'PY'` (quoted heredoc), never `bash`; spawn prompts that ask for scripted edits should say so. Recurring (any agent running ad-hoc Python); disposition: file-tracked candidate for a work Sharp Edge, not applied here (skill edit outside this PR's subsystem).
4. **A stale mutation-row anchor and two stale pins broke the feeder suite after merging `origin/main`** — main edited the line the `g4a-*` rows anchor on (`-target=…egress_gateway_web2 2>&1 | tf_redact_random_ids`), and my own `sed` of the routing-comment text invalidated a pin that I had not re-run. Recovery: re-anchored on the new line, updated both pins — Prevention: after any edit to text that a pin reads (even a comment), re-run the suite that pins it, not only the suites you believe cover the file; anchor mutation rows on a token that other PRs do not edit, and re-run the whole battery after every merge of main.
5. **The affected-test gate returned rc=6 (budget deferred) after 39 min queued behind a sibling session's full run** — nothing ran. Recovery: ran every covering suite directly with explicit `rc=$?` capture and treated CI as the authoritative gate — Prevention: do not read rc=6 as green; name the suites you ran instead.
6. **Plan/CTO ruling said the trigger could be `schedule` + `workflow_dispatch` only; measured hourly cron delivery (min 7232 s, median ~15400 s) could not hold the page budget** — Recovery: a CTO ruling to add a `WATCHDOG_DISPATCH_TABLE` row — Prevention: measure the substrate's delivery before accepting a trigger in a ruling (already the measure-first rule).
7. **`max_runtime_minutes = 8` (a fix agent's choice) pushed the Sentry margin arithmetic to 60.6 min over the 60 min ceiling** — Recovery: reverted to 6 and kept `timeout-minutes: 6` — Prevention: when a fix changes a value that feeds a documented budget, recompute the budget in the same edit.

## Tags

category: observability
module: betterstack, dead-man heartbeats, review panel
