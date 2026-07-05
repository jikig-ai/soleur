---
title: "Social content auto-posting silently stalled for ~3 weeks with zero alerts"
date: 2026-07-05
incident_pr: 6059
incident_window: "2026-06-15 → 2026-07-05 (~20 days)"
recovery_at: "2026-07-05 (fix merged; posting resumes on next daily 14:00 UTC run)"
suspected_change: "No code change — the draft→scheduled promotion was a manual step that simply stopped happening; the drought was invisible because no starvation signal existed."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - operator report ("nothing posting to our socials for 2 weeks, and no notifications")
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

For ~20 days (2026-06-15 → 2026-07-05) the `cron-content-publisher` Inngest cron ran green every day at 14:00 UTC but published **nothing** to any social channel (Discord/X/LinkedIn/Bluesky). The publisher only posts distribution-content files with `status: scheduled` + `publish_date == today`; during the window **zero** of 43 files were `scheduled` (all new drafts landed `status: draft` with empty `publish_date`). The draft→scheduled promotion is a manual CMO/operator step that quietly stopped. No alert fired because a run with nothing to post is a *success* — there was no "zero content published for N days" signal, and the one monitor that could have caught a dead cron (#4861) was itself reporting heartbeats-not-landing.

## Status

resolved — the fix (PR #6059) automates draft→scheduled promotion, adds a loud content-starvation alert, and makes the Sentry heartbeat's silent env-skip loud. Posting resumes on the next daily run.

## Symptom

Operator observed no social posts for ~2 weeks and, critically, received **no failure notification** the entire time.

## Incident Timeline

- **Start time (detected):** 2026-07-05 (operator report). The stall itself began 2026-06-15 (last successful publish).
- **Root cause active since:** 2026-06-16 (first draft that was never promoted).
- **Detection latency:** ~20 days — the entire point of this PIR.
- **Fix merged:** 2026-07-05 (PR #6059).

## Root Cause

Two independent gaps combined:

1. **The promotion step had no owner in code.** Content drafts accumulated (18 by 2026-07-05) but nothing flipped them `draft → scheduled`, so the publisher had nothing to post. (Known manual gap: #2756.)
2. **Absence-of-work was indistinguishable from health.** The pipeline alerted only on *failures* (script errors, stale scheduled content, per-platform post failures). A run that published zero items posted an `ok` heartbeat — a healthy-looking green. There was no starvation/zero-throughput signal. Compounding it, the raw Sentry cron heartbeat itself failed silently when its env was unset/malformed (#4861), logging at `info`/`warn` and returning — paging nowhere.

## Resolution

PR #6059:
- Automates draft→scheduled promotion onto the documented Tue/Thu cadence (self-heals; resolves #2756).
- Adds a failure-isolated **content-starvation alert** (Sentry `reportSilentFallback` + a deduped, auto-closing `action-required` GitHub issue) that fires on 0-scheduled-for-N-days — including the zero-published-baseline case a naive `NaN >= N` would have skipped.
- Makes `postSentryHeartbeat`'s env-unset/malformed skip **loud** (additive Sentry SDK mirror via `SENTRY_DSN`), resolving #4861 pending post-deploy heartbeat-landing verification.

## What Went Well

- The internal `routine_runs` table gave a definitive "cron ran green daily" signal, which distinguished "idle, not down" from "outage" in minutes and pointed straight at the content-gating root cause.

## What Went Poorly

- A revenue/brand-relevant automation degraded silently for three weeks. Throughput pipelines were monitored for failure but not for starvation.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #6065 | Harden `content-publisher.sh`: credential-skip `return 0` is scored as a publish (file flips to `published` while posted nowhere) — return a distinct sentinel and count skips separately. | agent |

## Lessons

See `knowledge-base/project/learnings/2026-07-05-content-starvation-absence-of-work-is-not-an-error.md` — "absence of work is not an error," standing-alert dedup needs a dedicated label, and touching a shared cron helper demands the full-suite gate.
