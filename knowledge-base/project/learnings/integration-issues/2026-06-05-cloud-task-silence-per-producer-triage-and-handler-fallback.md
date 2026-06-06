---
module: cron-content-generator / cloud-task-heartbeat
date: 2026-06-05
problem_type: integration_issue
component: inngest_cron
symptoms:
  - "[cloud-task-silence] watchdog issue filed for a scheduled producer that stopped emitting its [Scheduled] audit issue"
  - "Two cloud-task-silence alerts sharing the same label class assumed (wrongly) to share one root cause"
  - "Manual cron trigger produces nothing for ~75 min with no success and no FAILED issue"
root_cause: read_only_output_check_no_handler_fallback
severity: high
tags: [cloud-task-silence, inngest-cron, observability, watchdog, silent-failure, redaction, triage]
synced_to: [trigger-cron]
---

# Learning: cloud-task-silence triage is per-producer; the output-aware heartbeat needs a handler-level fallback

## Problem

Two open `cloud-task-silence` watchdog issues — #4960 (content-generator) and #4928
(roadmap-review) — shared the same `cloud-task-silence` label and the same tracking
issue (#2714), and looked like one incident. They were not.

- **#4928 (roadmap-review)** was already fixed by merged PR #4932 (a bwrap user-namespace
  sysctl drift, `kernel.apparmor_restrict_unprivileged_userns` flipped 0→1, that broke the
  cron sandbox's `/proc` mount). It just hadn't fired since the fix merged.
- **#4960 (content-generator)** had a **distinct** residual: an upstream Anthropic API 500
  killed `claude --print` ~6 min into the eval (Sentry event `141195e`, exitCode 1, no
  max-turns notice) — and the handler produced **no** audit issue at all (neither a success
  `[Scheduled] Content Generator` nor a `FAILED` one). Silent until the watchdog noticed
  ~9 days later.

## Investigation

1. Pulled the issue-artifact history per label: peer producers community-monitor (daily) and
   competitive-analysis (monthly) were firing fine → **not** a global Inngest outage and
   **not** a Doppler token revocation (those take down all crons).
2. Confirmed roadmap-review and content-generator both clone the repo via the same
   `_cron-claude-eval-substrate` — so the workspace-volume churn was not the differentiator.
3. **Active verification beat passive waiting:** fired `cron/content-generator.manual-trigger`
   and `cron/roadmap-review.manual-trigger`. roadmap-review produced #4973 within minutes
   (recovery confirmed on the same bwrap substrate → bash healthy); content-generator
   produced nothing in ~75 min → its cause was distinct.
4. Fired `cron/cloud-task-heartbeat.manual-trigger` → it auto-closed #4928 (roadmap-review
   healthy) and correctly left #4960 open (content-generator still stale).

## Root cause

`resolveOutputAwareOk` (`apps/web-platform/server/inngest/functions/_cron-shared.ts`) is
**read-only** — it turns the per-function Sentry monitor RED when no `scheduled-<task>` issue
exists in the run window, but it never *creates* one. The only producers of the audit issue
are the prompt's in-prompt `STEP 1b/2/4/6` "create issue and stop" guards. Any termination
that bypasses the prompt — a mid-eval crash, an API-500 that kills `claude --print`, or a
max-turns kill — produces nothing. All 8 always-create cron producers share this hole.

## Solution

Add a **handler-level** `ensure-audit-issue` `step.run` AFTER the output-aware `verify-output`
check, gated on `!heartbeatOk`: when no issue exists in the window, the handler itself files a
self-reporting `FAILED [Scheduled] Content Generator - <date>` issue (carrying exitCode /
durationMs / redacted stdoutTail). It lives above the prompt so it survives an eval kill.
Wrapped `try/catch → reportSilentFallback` (never throws into the `finally` teardown);
`runStartedAt.slice(0,10)` is the replay-stable date anchor; an in-step today's-prefix
title-dedup (explicit `sort:created/direction:desc`) prevents a double-file under `retries:1`.

Scoped to content-generator only; generalizing the fallback to the other 7 producers (extract
into `_cron-shared.ts`) is a tracked follow-up.

## Key Insight

**Two watchdog alerts sharing a label are NOT proof of a shared root cause.** Before bundling a
fix, check each issue's linked PRs (`gh pr list --search "linked:issue #N" --state all`) and
**verify each producer independently with a manual trigger** — recovery on a manual fire is the
authoritative signal, and it cleanly separates an already-fixed producer from one with a
distinct residual. The `/soleur:one-shot` collision gate caught this automatically: it
abort-by-defaulted the first (bundled) fix when it found the merged linked PR #4932.

**Secondary (security):** the cron substrate's `redactToken` strips ONLY the GitHub
installation token. When you persist spawn `stdoutTail`/`stderrTail` to a **new sink** (a
GitHub issue body), a crash stack can still spill other allowlisted-env secrets
(`ANTHROPIC_API_KEY` / `sk-ant-…`). Route through the canonical multi-secret scrubber
`redactGithubSourcedText` (`apps/web-platform/lib/safety/redaction-allowlist.ts`) AND
neutralize markdown table-breakout chars (backtick/pipe/newline) before interpolation. Caught
by security-sentinel at review, not by tsc or the unit suite.

## Session Errors

1. **`trigger-cron/scripts/trigger.sh` fails from the bare-repo root** (`not inside a git repo
   (cannot locate cron-manifest.ts)`). Recovery: ran it from an existing worktree path.
   **Prevention:** the trigger-cron skill must be run from a worktree, not the bare root —
   noted as a Sharp Edge on the skill.
2. **Plan subagent: one bare-root Write blocked by the worktree-protection hook.** Recovery:
   re-applied to the worktree path. **Prevention:** already hook-enforced (no change needed).
3. **Test pipe-escape assertion regex `/boom.*\| pipe/` matched the escaped `\|` form.**
   Recovery: re-asserted on the escaped form (`toContain("\\| pipe")`). One-off test-authoring
   slip; no recurrence vector.

## Tags
category: integration-issues
module: cron-content-generator
