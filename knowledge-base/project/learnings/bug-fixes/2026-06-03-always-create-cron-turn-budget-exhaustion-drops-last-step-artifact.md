---
title: "Always-create cron turn-budget exhaustion drops the last-step artifact (fix the budget, not the monitor)"
date: 2026-06-03
category: bug-fixes
module: apps/web-platform/server/inngest/functions
tags: [inngest, cron, claude-code-spawn, max-turns, output-aware-heartbeat, sentry]
related_prs: ["#4714 output-aware heartbeat", "#4786 stdout-tail capture", "#4468 GHA→Inngest migration"]
related_sentry: ["eff0bef435664f4d929d2ac3aa3e6a7e"]
---

# Always-create cron turn-budget exhaustion drops the last-step artifact

## Problem

Sentry `WEB-PLATFORM-1Z` (2026-06-03 08:06 UTC) fired:
`cron-community-monitor spawn exited non-zero AND created no "scheduled-community-monitor" issue in the run window`.
The cron had silently produced no daily digest issue since 2026-05-25 (9 days).

## Root cause (confirmed from live Sentry evidence, not hypothesis)

The org-scoped events endpoint for the issue gave the decisive `extra`:

| field | value | meaning |
| --- | --- | --- |
| `exitCode` | `1` | claude `--print` non-zero exit |
| `stderrTail` | `""` | NO infra fault (no git/auth/network stderr) |
| `stdoutTail` | `"Error: Reached max turns (50)\n"` | **turn-count exhaustion** |
| elapsed | ~6 min (08:00:08 → 08:06:02) | NOT the 50-min wall-clock ceiling |

The spawned agent burned all 50 turns on the 7-platform collection + brand-guide read +
digest write + full `git→PR→auto-merge` flow and **never reached its final step**:
creating the `[Scheduled] Community Monitor` issue. Because the issue is the function's
*success contract* and the issue-create is the **last** prompt step, any turn overrun
drops exactly the artifact the monitor requires.

## Key Insight

**The output-aware heartbeat was correct, not over-firing.** `cron-community-monitor` is a
genuine *always-create producer* (every run must file a digest issue — even the
no-platform path files a `- FAILED` issue), so the `artifact-required` contract
(`resolveOutputAwareOk`, #4714) correctly turned the monitor RED on a real silent no-op.

This is the **complement** of [[2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn]]:
- *Best-effort* producer (e.g. the bug-fixer) → relax the contract to `liveness` (#4730).
- *Always-create* producer → keep `artifact-required`; the bug is the **producer's budget**.

When a monitor RED-fires on an always-create producer, ask "did the producer finish within
budget?" before ever touching the monitor. The fix is supply-side: match the turn budget to
a **proven-healthy cohort comparator**, not to a guessed number.

## Solution

Raise `--max-turns` `50 → 80` in `CLAUDE_CODE_FLAGS`, matching the proven-healthy
`cron-daily-triage` (which runs reliably at 80 through the *same* `DEFAULT_CLAUDE_SETTINGS`).
Keep `MAX_TURN_DURATION_MS` at 50 min: the timeout-to-turns ratio is `50/80 = 0.625 min/turn`,
inside the `0.55–1.2` peer band (per [[2026-03-20-claude-code-action-max-turns-budget]]), so
the wall-clock stays adequate and its test assertion (`toBe(50 * 60 * 1000)`) is untouched.

Note the parity is *turn-count* parity, not *duration* parity — daily-triage pairs 80 turns
with a 60-min ceiling; community-monitor's 50-min/80 is the cohort's tightest density but
still in-band.

A unit test cannot prove 80 is enough — turn-budget adequacy is only provable against a real
7-platform fire, so the binding gate is the **post-merge live run** (trigger-cron → confirm
issue created → confirm Sentry check-in `status=ok`).

## Prevention

- The 27 verbatim prompt anchors (`SUT_SOURCE.toContain(...)`) are order-independent
  substring checks; a budget bump touches none. A source-shape regression guard
  (`toMatch(/"--max-turns",\s*"80"/)` + `.not.toMatch(/.."50"/)`) now pins the value — the
  regex requires the literal `"--max-turns",` argv prefix so it cannot collide with
  `MAX_TURN_DURATION_MS = 50 * 60 * 1000`.
- The diagnostic recipe (org-scoped `/organizations/<org>/issues/<numeric-id>/events/latest/`
  with `SENTRY_ISSUE_RW_TOKEN`; the project-scoped and numeric `/issues/<id>/` endpoints 401
  with that token) is reusable for any cron-spawn post-mortem.

## Session Errors

None detected. session-state.md forwarded `Errors: None`; implementation followed RED→GREEN
(verified RED before fix), all 1383 inngest+sweep tests stayed green, tsc clean, and the
single P3 review finding (a stale `scheduled-community-monitor.yml` comment reference, dead
since #4468) was fixed inline.
