---
title: Verify long-running background processes are actually dead before relaunching
date: 2026-05-20
category: workflow-issues
tags: [background-tasks, bench, anthropic-api, process-verification, observability]
module: workflow-discipline
synced_to: [work-skill]
description: 'A long-running background bench appeared dead due to log buffering and a too-restrictive pgrep pattern. Three concurrent benches got launched against the same API key before the truth surfaced. Cost: ~$2-3 of extra Anthropic API spend.'
issue: 4119
pr: 4156
problem_type: workflow_issue
severity: high
---

# Verify long-running background processes are actually dead before relaunching

## Problem

During Stage 1 of #4119, the bench script (`scripts/learning-retrieval-bench.sh --confirm`, ~70min, ~$3.07) was launched in the background via the Claude Code Bash tool. Twice during the run I "verified" it had died and launched a replacement. In fact it was running fine the whole time. By the end, three concurrent benches were racing for the same Anthropic API key.

**Concrete sequence:**

1. **14:33** — Bench 1 launched (`bw81p6ug7`, foreground-style background task with `run_in_background: true`, output redirected to `/tmp/kb-bench-2026-05-20/run.log`).
2. **14:58** — Checked status. `pgrep -fa 'learning-retrieval-bench --confirm$'` returned nothing. Log file mtime was 14:58 (matched current time so looked frozen). Tail showed `progress: 600/1147` with no new entries.
3. **Concluded:** Bench 1 died at ~52% through light pass.
4. **15:02** — Launched bench 2 (`bg9z8hlve`) with `--cache-paraphrases` for resilience.
5. **15:22** — Checked status. Same pattern: pgrep empty, log mtime stale at 333/1147. Concluded bench 2 died too.
6. **15:25** — Launched bench 3 (`bvd1y49wd`) as a foreground command (which the harness auto-routed to background due to the 90-min timeout exceeding the 2-min foreground default).
7. **15:46** — Bench 1's harness completion notification fired: **exit code 0**. Log file showed it had gone from `progress: 600/1147` all the way through Phase 3 (lookups), Phase 4 (aggregation), Phase 5 (write outputs). The 14:58 "freeze" was log buffering, not death.
8. **15:46** — Discovered benches 2 and 3 were STILL RUNNING (and presumably benches 2 and 3 also competed with bench 1 for the API). Killed them both with `pkill -9` after locating them via `ps -ef | grep -E 'learning-retrieval-bench --confirm'` (NOT pgrep).

## Root Cause

Three compounding errors in the verification procedure:

1. **`pgrep -fa 'learning-retrieval-bench --confirm$'` was too restrictive.** The anchored `$` at the end of the pattern excluded processes wrapped in `doppler run -p soleur -c prd_scheduled -- bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases /tmp/...` because the command line continues after `--confirm`. The actual bash subshell processes were running fine; my pattern just didn't match them. `ps -ef | grep -E 'learning-retrieval-bench'` (broader, no anchor) found all of them.

2. **Log file mtime is not a liveness signal.** The bench writes progress every 50 paraphrases. Between writes (which can be 60-120 seconds at API latency), the mtime stays stale. Treating "log file hasn't moved in 60+ seconds" as "process is dead" is a false-negative-prone heuristic.

3. **The harness's task-completion notification is the authoritative signal.** When the Bash tool's `run_in_background: true` task exits, the harness fires a `<task-notification>` with `status: completed|failed` and exit code. That fired at 15:46 for bench 1, confirming it ran the full ~75 minutes. I was checking pgrep and log mtime instead of waiting for that signal.

## Solution

When a long-running background bash task appears unresponsive, **do not relaunch** until ALL three checks fail:

1. **Broad `ps -ef | grep -E` lookup.** No anchored patterns. Match by a short, unambiguous substring of the command. Example:

   ```bash
   ps -ef | grep -E 'learning-retrieval-bench|api.anthropic.com/v1' | grep -v grep
   ```

   If anything matches, the process is alive — wait, don't relaunch.

2. **Inspect the cache or output file size.** If the script supports incremental writes (NDJSON cache, partial JSON), the file size growth IS the liveness signal. `wc -l <cache-file>` over a 30-second window is more reliable than log mtime.

3. **Wait for the harness's completion notification.** For Bash tool background tasks, the `<task-notification>` is fired on process exit with a definitive `status` field. Trust that signal over polling.

**Only after all three checks confirm death should a relaunch be considered.** And the relaunch should preserve the cache file from the prior run (e.g., `--cache-paraphrases <path>`) so partial work isn't lost.

## Prevention

- **In skill instructions for long-running bash:** add an inline reminder that `pgrep` with anchored patterns misses wrapper-process command lines. Prefer `ps -ef | grep -E '<substring>' | grep -v grep`.
- **In long-running scripts:** add a heartbeat write to a known liveness file every N seconds (e.g., `touch /tmp/<job>.heartbeat`), so a stat-based liveness check is reliable. `learning-retrieval-bench.sh` could touch `/tmp/<bench>.heartbeat` after every API call.
- **Workflow rule (proposed, see Constitution Promotion):** before relaunching any long-running background process, verify via broad `ps -ef` AND wait for the harness's completion notification. Documenting the wait time bound makes it explicit — for the 70-min bench, expect notification at ~75 min plus 15 min safety margin.

## Session Errors

**1. Log-buffering false-negative misdiagnosed bench 1 as dead.**
Recovery: discovered when the harness's task-completion notification fired showing exit 0 and final outputs written.
Prevention: see Solution section above.

**2. Three concurrent bench runs against the same Anthropic API key.**
Recovery: killed the two zombies with `pkill -9 -f 'learning-retrieval-bench'` and `pkill -9 -f 'api.anthropic.com'`. Extra cost: ~$2-3 in redundant Haiku paraphrase generation.
Prevention: never relaunch a long-running background process before exhausting the verify-it's-actually-dead procedure.

**3. `extract_inline_tags` over-absorbed bullet list items.**
The Phase 1 backfill produced 13 files with corrupt tags (`--2799`, `category-process`, `module-brainstorm`) extracted from markdown bullet lists in `Related:` / `PRs:` / `Closes:` sections.
Recovery: PyYAML cleanup pass committed as `82584251`. Filed #4163 with hardening scope.
Prevention: in `scripts/backfill-frontmatter.py`, `extract_inline_tags` needs reject patterns for `^--`, `^category-`, `^module-`, and tokens longer than 50 chars.

**4. First plan was 5× longer than the patch.**
The initial Stage 1 plan was 400+ lines (decision tables, ladder bands, frozen-impl complexity, calendar reminders) for what became a ~58-line bash + markdown change. DHH/Kieran/Simplicity reviewers triaged the ceremony and the plan was rewritten to ~130 lines.
Recovery: applied the triangulated review and trimmed in place.
Prevention: at plan-write time, draft a one-line "patch size estimate" before writing decision tables. If the plan grows past ~3× the estimated patch, treat that as a smell and trim before review.

**5. Stale frontmatter denominator carried forward from prior brainstorm.**
The 2026-05-19 brainstorm cited "533/841 missing frontmatter". The actual current state was 324/1152. Spec + initial plan repeated 533 without re-measuring.
Recovery: re-measured in Phase 1 prep and adjusted the plan's AC inline.
Prevention: before quoting a count in a spec, re-run the underlying measurement on the current corpus. Numbers from prior brainstorms can be stale within days on an active KB.

**6. Restrictive pgrep pattern hid running processes.**
See root cause #1. `pgrep -fa 'pattern$'` with anchor excludes wrapped processes. `ps -ef | grep -E 'substring'` is the reliable alternative.

**7. Plan AC mismatch: recursive find vs. top-level-only script.**
Plan FR3 said "0 missing frontmatter (recursive)" but `scripts/backfill-frontmatter.py` only processes top-level (uses `os.listdir`, not `os.walk`). Result: 32 subdir files remained missing FM after Phase 1.
Recovery: filed #4163 to extend the script + tightened the AC to top-level.
Prevention: when prescribing a tool in a plan, verify the tool's actual scope (recursion, glob semantics) before writing the AC.

**8. Chained `sleep 60 && cmd` blocked by harness.**
The harness disallows `sleep + command` chains to discourage polling. Attempted to use this pattern to wait for the bench to start producing output.
Recovery: used `run_in_background: true` instead, then trusted the harness's completion notification.
Prevention: when intent is "wait then check", use `run_in_background: true` from the start, not chained sleeps.

## Cross-References

- Source PR: #4156 (Stage 1 of #4119)
- Sibling learning (this session's primary outcome): `knowledge-base/project/learnings/2026-05-20-retrieval-diagnostic-findings.md`
- Backfill hardening follow-up: #4163
- Stage 2 deferred ladder branch: #4176
- Bench script: `scripts/learning-retrieval-bench.sh` (especially `--cache-paraphrases` flag at line 65)
- Related: `2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md` (the precedent that enabled --cache-paraphrases; this session would have lost work without it)
