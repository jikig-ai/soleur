---
title: A follow-through soak that reads a monitor's ARMED state must extend the arming wiring to every new host, or it false-FAILs a healthy target
date: 2026-07-24
category: integration-issues
module: apps/web-platform/infra, scripts/followthroughs
tags: [follow-through, better-stack, heartbeat, for_each, observability, soak, false-fail, arm-gate]
issues: [6459, 6919]
severity: high
---

## Problem

Phase 4.3 of the active-active web cluster (#6919) enrolled a follow-through soak
(`scripts/followthroughs/web2-standby-soak-6459.sh`) that asserts a fresh cattle host `web-2` is
NOT dark by reading its two per-host Better Stack heartbeats (`web_zot_consumer`, `web_nic_guard`)
via `/api/v2/heartbeats` and requiring `status == "up"`. It shipped green (syntax + shellcheck +
enrollment gate all passed), yet the `observability-coverage-reviewer` found it would **false-FAIL
a perfectly healthy web-2 as a DARK host**, so #6459 could never close.

## Root cause

Two coupled facts the soak's author (me) did not connect:

1. **`web-probe.tf` creates every per-host heartbeat `paused = true` with `ignore_changes = [paused]`.**
   Because they are `for_each = var.web_hosts`, adding web-2 to the roster creates web-2's monitors
   `paused` at the SAME apply that creates the host.
2. **The ONLY unpause path is the apply workflow's "Arm web-host probe heartbeats" step, whose
   `arm_one` calls were hardcoded to `["web-1"]`.** This PR added web-2 to the roster but never
   touched the arm-gate.

So web-2's heartbeats stay `paused` forever. The soak read `paused`, which is neither `up` nor its
`ABSENT` sentinel, so it landed in the `NOT_UP` bucket → `exit 1` / "web-2 is a DARK host." Worse,
the probe could not distinguish a genuinely-dark web-2 (the #6538 regression it exists to catch)
from the benign never-armed state — both surface as `paused → FAIL`. Its documented
"not-born ⇒ ABSENT ⇒ TRANSIENT" fail-safe never engaged, because a `for_each` monitor is created
`paused`, **never `ABSENT`** (ABSENT only happens pre-apply).

## Solution

Two fixes, both in this PR:

1. **Extend the arming wiring to the new member.** Add the two web-2 `arm_one` calls next to web-1's
   in `apply-web-platform-infra.yml` (the gate's `arm_one` already no-ops `return 0` when an address
   is absent from tfstate, so it is inert on any apply path that has not yet created web-2).
2. **Reconcile the soak's status taxonomy with the real post-apply lifecycle.** `paused`/`pending`
   is a BORN-but-arming state, not a dark one — route it to TRANSIENT (retry), distinct from ABSENT
   (not born) and a genuinely-down status (DARK). Plus a `.pagination.next` fail-safe so a monitor on
   an unfetched page reads TRANSIENT, not a false ABSENT/dark-mask.

## Key insight

**A follow-through/soak probe that keys on a resource's ARMED / enabled / unpaused state has a hidden
dependency on the wiring that arms it — and that wiring is a per-member list that does not fan out with
`for_each`.** When you add a probe over a new host/tenant/queue, trace the ENABLE path (the arm-gate,
the `systemctl enable`, the `paused=false` flip) and confirm it was extended to the new member, exactly
as you would trace the roster-coupled parity guards. A `for_each`-created monitor born in a non-serving
state (`paused`) reads that state, **never `ABSENT`** — so any "not-provisioned ⇒ ABSENT ⇒ TRANSIENT"
contract silently does not hold for the born-but-not-yet-enabled window, and the probe false-FAILs
(or false-closes) on a healthy target. The generalization of the roster-coupled-guard sweep: a new
`for_each` member needs not just its config fanned out, but every imperative per-member ENABLE step
(arm, unpause, register) extended too.

## Session Errors

- **Followthrough soak false-FAILs a healthy web-2** — Recovery: extend the arm-gate to web-2 +
  treat paused/pending as TRANSIENT. Prevention: this learning + the routed review-skill bullet —
  when a probe reads an armed/enabled state, verify the arming wiring covers the new member.

## Related

- [[2026-06-16-realtime-event-guard-must-equal-fetch-query-scope]] — sibling class (a new for_each
  member needs the consumer-side scope extended, not just the config).
- `web-probe.tf` (per-host heartbeats, `paused=true` + `ignore_changes=[paused]`).
- ADR-142 (active-active web cluster).
