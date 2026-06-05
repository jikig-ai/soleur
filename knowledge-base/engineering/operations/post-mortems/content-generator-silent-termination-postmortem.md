---
title: "content-generator scheduled cron silently terminated on an upstream Anthropic API 500"
date: 2026-06-05
incident_pr: 4975
incident_window: "2026-05-21 → 2026-06-05 (no audit issue produced)"
recovery_at: "2026-06-05 (handler-level fallback merged; watchdog auto-closes on next fire)"
suspected_change: "none — transient upstream Anthropic API 500 mid-eval; no Soleur change regressed it"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - provider
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `human` — Operator did this directly.

# Incident Overview

The `cron-content-generator` Inngest scheduled task (Tue/Thu 10:00 UTC) stopped
producing its `[Scheduled] Content Generator` audit issue after 2026-05-21. The
`cron-cloud-task-heartbeat` watchdog correctly flagged the absence on 2026-06-05,
filing `[cloud-task-silence]` issue #4960 ("Days since last issue: 14"). No blog
article, no distribution content, and no failure issue were produced in the window —
the run was **silent**.

This PIR covers the content-generator-specific residual only. The concurrent
community-monitor/roadmap-review silence in the same window had a *different* root
cause (a bwrap user-namespace sysctl drift) already fixed + post-mortemed via merged
PR #4932 and learning `2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`.

## Status

resolved — handler-level fallback merged in PR #4975; `Closes #4960` auto-closes the
watchdog alert at merge, and the next fire (or a manual trigger) now produces a
success-or-FAILED audit issue end-to-end.

## Symptom

A producing scheduled task produced neither its success `[Scheduled] Content Generator`
issue nor a `FAILED` issue. The only signals were the per-function Sentry monitor going
RED and, ~9 days later, the watchdog filing #4960.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-05-21 12:50 | Last healthy `[Scheduled] Content Generator` issue (#4247) produced. |
| system | 2026-05-26 … 06-04 | ~4 Tue/Thu fires produced nothing (no success, no FAILED issue). |
| system | 2026-06-05 09:30 | `cron-cloud-task-heartbeat` watchdog filed #4960. |
| agent | 2026-06-05 ~15:05 | Manual `cron/content-generator.manual-trigger` fired to verify recovery post-#4932. |
| agent | 2026-06-05 ~15:11 | Run died at ~6.1 min (Sentry event `141195e`): `exitCode 1`, `signal null`, `stdoutTail` = "API Error: 500 Internal server error." Still no audit issue → silence confirmed as a distinct, producer-side hole. |
| agent | 2026-06-05 | Handler-level `ensure-audit-issue` fallback authored, reviewed, merged (PR #4975). |

## Participants and Systems Involved

`cron-content-generator` Inngest function; `_cron-claude-eval-substrate` (bwrap-sandboxed
`claude --print`); `cron-cloud-task-heartbeat` watchdog; the upstream Anthropic API.

## Detection (+ MTTD)

- **How detected:** monitoring — the `cron-cloud-task-heartbeat` watchdog's label-absence
  signal (filed #4960). The per-function Sentry monitor also went RED at fire time.
- **MTTD:** the watchdog's threshold is `maxGapDays: 9` for this task — so up to ~9 days of
  silence is invisible by design before the watchdog fires.

## Triggered by

provider — a transient upstream Anthropic API 500 killed `claude --print` ~6 minutes into
the eval, before the prompt reached its `STEP 6` audit-issue create.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| max-turns 50 starvation | plan's prior hypothesis; PR #4932 deferred a 50→80 bump | Sentry `stdoutTail` shows an API-500, no "Reached max turns" notice; died at ~6.1 min, far from the 55-min ceiling | rejected |
| upstream API-500 mid-eval crash bypassing the prompt's issue-create | Sentry event `141195e`: exitCode 1, signal null, "API Error: 500" | — | confirmed |

## Resolution

The eval can be killed mid-run by any upstream/process failure, so a prompt-level guard can
never fully cover it. Added a **handler-level** `ensure-audit-issue` step that runs after the
output-aware `verify-output` check: when no `scheduled-content-generator` issue exists in the
run window, the handler self-reports a `FAILED [Scheduled] Content Generator - <date>` issue
(carrying exitCode/durationMs/redacted tails) before returning. Wrapped so it never throws into
the teardown; today's-prefix dedup prevents a double-file under `retries:1`. `--max-turns 50`
left unchanged — the evidence refuted the turn-kill hypothesis.

## Recovery verification

PR #4975 merges with `Closes #4960` (auto-closes the watchdog alert at merge). End-to-end:
the next content-generator fire — or a manual `cron/content-generator.manual-trigger` — now
produces a success **or** FAILED audit issue, so the run can no longer be silent. Roadmap-review
recovered on the same bwrap substrate earlier this session (produced #4973), proving the sandbox
itself is healthy.

## Follow-ups

- **The 7 other always-create cron producers share the same read-only-heartbeat hole** — none
  self-reports a fallback issue. Generalizing the fallback into `_cron-shared.ts` and wiring all
  producers is deferred (scope was content-generator only). Tracked as the cohort follow-up
  referenced in the plan's Non-Goals; re-evaluate after this PR proves the pattern in production.

## GDPR / data-exposure assessment

art_33/art_34 both **false** — this is an availability/observability incident only. No personal
data was exposed: the fallback issue body carries only the cron's own redacted spawn tail
(routed through `redactGithubSourcedText`), exitCode, and timing. No customer or operator-session
data is in scope.
