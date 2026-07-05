---
title: "Content starvation — absence-of-work is not an error, and standing-alert dedup needs a dedicated label"
date: 2026-07-05
category: observability
tags: [observability, cron, inngest, silent-failure, content-publisher, dedup]
related_pr: 6059
closes: [2756, 4861]
---

## Context

Social-content auto-posting silently stalled for ~3 weeks with **zero alerts**. The
`cron-content-publisher` Inngest cron (daily 14:00 UTC) completed green every day —
prod `routine_runs` showed `status: completed, error_summary: null` throughout. It was
not down; it simply had **nothing to post**: 0 of 43 distribution-content files were
`status: scheduled` (the draft→scheduled promotion was a manual step that stalled).

## Learning 1 — "absence of work" is indistinguishable from "healthy" unless you alert on it

A cron that runs, finds nothing to do, and posts an `ok` heartbeat looks **identical** to
a healthy cron on every dashboard. The pipeline had monitoring for *failures* (script
errors, stale scheduled content, per-platform post failures) but **no signal for
starvation** — 0 items published for N days. So a multi-week content drought produced no
Sentry issue, no missed heartbeat, no GitHub issue.

**Rule:** any pipeline whose value is *throughput* (posts published, jobs drained, emails
sent) needs an explicit **starvation/zero-throughput alert** distinct from its
failure/liveness alerts. The heartbeat proves the cron *ran*; it says nothing about
whether the cron *did anything*. Keep the two signals separate — starvation is a CONTENT
signal and must never flip the liveness heartbeat to `ok:false` (that would false-page
cron-DOWN). Wire it failure-isolated: an Octokit throw inside the starvation check degrades
to "not starved" and returns normally.

**Predicate trap:** a naive `daysSincePublish >= N` **silently skips the worst drought** —
when zero items have ever been published, `daysSincePublish` is `NaN`, and `NaN >= N` is
`false`. The predicate must fire on the empty/undefined/non-finite baseline explicitly:
`starved = scheduledWithinHorizon === 0 && (latestPublishedDate === undefined ||
!Number.isFinite(daysSincePublish) || daysSincePublish >= N)`.

## Learning 2 — a STANDING (stable-title) dedup issue must not reuse a dated audit issue's `per_page:10` read

The dedup + auto-close for a long-lived, stable-title alert cannot copy
`ensureScheduledAuditIssue`'s `GET issues?labels=action-required&sort=created&direction=desc&per_page=10`
+ page-1 title match. That precedent is safe **only because its title is date-suffixed and it
dedups same-day**. A standing alert's issue ages; once ≥10 newer open `action-required`
issues exist — exactly the neglected-backlog state a multi-week drought represents — the
standing issue scrolls off page 1, causing (a) a **duplicate filed every day** and (b) a
**missed auto-close** on recovery.

**Rule:** give a standing dedup issue its own dedicated label and filter the dedup/close
reads on BOTH labels (GitHub `labels=` is AND-semantics), so the candidate set stays ~1
regardless of backlog size. Create the repo label out-of-band so the cron's `POST issues`
does not 422 in prod.

## Learning 3 — touching a shared cron helper breaks every sibling test that wholesale-mocks the shared module

Making `postSentryHeartbeat` (called by ~45 crons) route its env-unset/malformed skip
through `mirrorWarnWithDebounce` broke 6 sibling cron tests that `vi.mock("@/server/observability", () => ({ reportSilentFallback }))`
wholesale — the new named export was missing from their factory (the documented
"wholesale-mock-drops-named-export" trap). Two fixes applied together: (1) add the missing
export stub to each sibling factory; (2) make the source change **additive** — keep the
existing `logger.info`/`logger.warn` line AND add the Sentry mirror, so the change is
"strictly louder" and pre-existing `expect(logger.info).toHaveBeenCalled()` assertions
still hold. The targeted test run passed; only the **full-suite exit gate** caught the
6 sibling breakages — a reminder that touching a shared function demands the full suite,
not just the touched-file tests.
