---
title: "Failure signal never reaches a human"
summary: "Monitors and artifact steps can be green while the alert has no route, the unit was never installed, or the step swallows its error; each failure channel needs an end-to-end reach check."
status: open
opened_on: "2026-10-24"
tags: [observability, monitoring, alerting, silent-failure]
evidence:
  - knowledge-base/project/learnings/2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md
  - knowledge-base/project/learnings/2026-09-27-the-monitor-that-was-never-installed-and-the-dependency-that-would-have-mounted-plaintext.md
  - knowledge-base/project/learnings/2026-10-15-dormant-followthrough-probe-is-not-a-standing-detector.md
  - knowledge-base/project/learnings/2026-08-12-every-fix-i-shipped-for-a-silent-failure-had-a-silent-failure-in-it.md
  - knowledge-base/project/learnings/2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md
required_reading: false
---
## Root cause

Detection and delivery are verified separately, or not at all. Monitors were created with no
workflow routing them to a recipient, a timer was armed by a line that had never executed, a probe
stopped running when its tracker closed, a monitor proved that a timer fired without asserting the
condition, and a step meant to leave a durable record lacked the permission to write it while an
error-swallowing suffix kept the run green. The fix for a silent failure frequently reintroduced a
silent path of its own.

## Fix

Verify the full path from event to recipient on a live sample, not only that the event is emitted.
A check that must outlive its tracker becomes a standing alert. A step whose purpose is to guarantee
a record fails the run on error instead of swallowing it, and permissions are checked at the point of
use. Static arming guards are paired with evidence that the armed code ran, and a heartbeat is tied
to the condition it claims to cover.

## Evidence

- knowledge-base/project/learnings/2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md
- knowledge-base/project/learnings/2026-09-27-the-monitor-that-was-never-installed-and-the-dependency-that-would-have-mounted-plaintext.md
- knowledge-base/project/learnings/2026-10-15-dormant-followthrough-probe-is-not-a-standing-detector.md
- knowledge-base/project/learnings/2026-08-12-every-fix-i-shipped-for-a-silent-failure-had-a-silent-failure-in-it.md
- knowledge-base/project/learnings/2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md
