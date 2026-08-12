---
title: "Inngest dedicated host booted but never bound :8288 — 12 days of silent dispatch failure behind a green heartbeat"
date: 2026-08-12
incident_pr: "#7457"
incident_window: "2026-07-31 → 2026-08-11 (~12 days, dark)"
recovery_at: "unresolved at merge — the host is still down; restore is tracked in #7462"
suspected_change: "The dedicated inngest host (10.0.1.40) bootstrapped and started inngest-server, which then failed to bind :8288. The sole liveness signal in the path was a `curl \"$HEARTBEAT_URL\"` fired by a systemd timer, which proves a timer fired and asserts nothing about the port — so every monitor stayed green while no dispatch was served."
brand_survival_threshold: aggregate pattern
status: unresolved but ended
triggers:
  - observability-gap
  - silent-failure
  - liveness-signal-does-not-observe-the-service
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability incident with zero personal-data exposure. The failure is a scheduler that did not accept dispatches; no user content was read, written, transmitted or exposed. GDPR Art. 33/34 not engaged."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The dedicated self-hosted Inngest host booted, bootstrapped, and started
`inngest-server.service` — which never bound `:8288`. For approximately twelve days every
dispatch to that host failed, and every monitor reported healthy.

The monitor reported healthy because of what it measured. The host's only liveness signal was a
`curl "$HEARTBEAT_URL"` fired by a systemd timer. That proves a timer fired. It asserts nothing
about the port, nothing about the process, and nothing about whether a single dispatch was
accepted. The beat was not a weak check of the right thing; it was a correct check of the wrong
thing.

## Status

`unresolved but ended` — the dispatch failures have stopped mattering only because the host is
not serving at all. The scheduler is still down at merge time. PR #7457 closes the *observability
and cutover-safety* gaps that let the failure run dark; the host restore itself is #7462.

## Symptom

Dispatches to the dedicated host failed silently. `:8288` never accepted a connection. The
heartbeat timer continued to fire and report success throughout.

## Incident Timeline

- **Start time (detected):** 2026-08-11 (discovered ~12 days after onset)
- **End time (recovered):** not yet — see #7462
- **Duration (MTTR):** unresolved at time of writing

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-31 (approx) | Host boots; `inngest-server` starts and fails to bind `:8288`. No marker emitted. |
| agent | 2026-07-31 → 2026-08-11 | Heartbeat timer fires on schedule and reports healthy for ~12 days. Dispatches fail. |
| human | 2026-08-11 | Operator discovers the host is not serving. #7228 filed. |
| agent | 2026-08-11 | Investigation confirms the beat never observed the port. Plan authored. |
| agent | 2026-08-12 | PR #7457: listener gate, emitter loudness, per-boot token re-stage, probe identity, instance-scoped `done`. |
| agent | 2026-08-12 | 12-agent review finds 25 findings, nine of them the same silent-failure family inside the fix. All P1/P2 fixed inline. |

## Participants and Systems Involved

Self-hosted Inngest on a dedicated Hetzner host (10.0.1.40); `inngest-server.service`;
`inngest-heartbeat` timer; the cutover FSM (`inngest-cutover-flip.sh`) and its ExecStartPre arm
guard; Vector → Better Stack log transport; Doppler `soleur-inngest/prd`.

## Detection (+ MTTD)

- **How detected:** operator observation. No monitor fired — by construction, since no monitor
  in the path observed the port.
- **MTTD:** ~12 days.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The liveness signal did not observe the service it claimed to cover | The beat is `curl "$HEARTBEAT_URL"` on a timer; it has no reference to `:8288`, the process, or a dispatch | none | **confirmed** |
| The boot emitter could exit silently, so the failure produced no trace | Two of `inngest-boot-phone-home.sh`'s failure arms were `exit 0` with no output | none | **confirmed** |
| A stale/absent bootstrap token could leave a replaced host unable to fetch config | Token was baked, not re-fetched per boot | not yet observed as the live cause | plausible contributor |

## Root Cause(s) — 5-Whys

1. **Why did dispatches fail?** `inngest-server` was not listening on `:8288`.
2. **Why did nobody notice for twelve days?** The only monitor was a timer-fired `curl` to an
   external heartbeat URL.
3. **Why did that monitor report healthy?** Because it measured whether the timer fired, which
   was true. It never queried the port.
4. **Why was the check written that way?** A heartbeat is cheap and reads as liveness. "The beat
   arrived" was allowed to stand in for "the service works" without anything asserting the link.
5. **Why did no other signal cover it?** The boot emitter — the single delivery path for all
   eight boot-stage markers, and the entire diagnosis surface on a host with no inbound SSH — had
   failure arms that were `exit 0` with no output. The one component that existed to make a boot
   failure visible was itself silent on failure.

**Root cause:** a liveness signal that did not observe the service, backed by a diagnostic
channel that was silent on its own failure. Either alone is survivable; together they make a
dead scheduler indistinguishable from a healthy one.

## Resolution

Not yet resolved — the host restore is #7462. PR #7457 removes the conditions that let the
failure run dark:

- **The beat proves the port.** No heartbeat leaves the host unless `:8288` answers. Rate limiting
  applies to the *emit*, never to the *check*.
- **The emitter cannot exit silently.** Both silent arms now `logger -t inngest-boot-phone-home`,
  an identifier already on Vector's allowlist.
- **The bootstrap token is re-fetched per boot** rather than re-stamped from a baked value.
- **The probe carries identity** (`instance_id`, `cli_version`, `cutover_flag`).
- **`done` is instance-scoped and probe-derived**, on the root disk so it does not survive a
  replace — while the monotonic re-flush latch stays on `/mnt/data`, where it must.

## Recovery verification

Deferred to #7462 by construction: verifying an armed consumer heartbeat requires a host that
boots and serves, which is that issue's closing condition, not this PR's. This is why PR #7457
cites `Ref #7228` rather than `Closes` — the fix is necessary and not sufficient.

# Incident Post-Mortem Analysis

## Versions of Components

Inngest CLI pinned at v1.19.4 (bump tracked separately in #7463); Ubuntu 24.04 host; Vector
log shipper; Doppler CLI for secret delivery.

## Impact details

### Services Impacted

Self-hosted Inngest dispatch on the dedicated host. Blast radius is **fleet-wide** for
dispatches routed to that host — not inbound-email only, as first assumed.

### Customer Impact (by role)

No customer-visible data loss or exposure. Dispatches routed to the host failed for the window.
The 53 registered crons were **unaffected** (#7230). The ~12 days of failed dispatches are
**accepted as lost** — no replay, backfill, or dead-letter recovery is in scope, an explicit
operator decision.

### Revenue Impact

None identified.

### Team Impact

One full investigation-and-remediation cycle, plus a 12-agent review whose findings materially
changed the fix.

## Lessons Learned

### Where we got lucky

The crons were registered elsewhere and kept running, so the blast radius stopped short of the
scheduled workload. Nothing in the design guaranteed that — it is luck, not architecture.

### What went well

The review panel caught nine defects of the same family as the incident *inside the fix for the
incident*, before merge. Several would have reproduced #7228 through its own remediation — most
sharply, a listener gate whose fixtures could not distinguish an allowlist from a blocklist, so
inngest's own not-ready 503 would have produced a green beat over a scheduler serving nothing.

### What went wrong

The monitor measured the monitor. A heartbeat that fires on a timer and asserts nothing about the
service is not a liveness check, and it was treated as one for twelve days. The diagnostic path
that existed to catch exactly this was silent on its own failure.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #7462 | Restore the dedicated inngest host — replace, diagnostic boot, cutover window. Carries the recovery verification this PR cannot satisfy at merge. | open |
| #7463 | Bump the pinned inngest CLI off v1.19.4 in its own window, with pin-freshness monitoring. | open |
| #7464 | Port the userdata-stub incompressibility bound into `registry-userdata-budget.test.sh`. | open |

## Related

- PR #7457 — the remediation.
- `knowledge-base/project/learnings/2026-08-12-every-fix-i-shipped-for-a-silent-failure-had-a-silent-failure-in-it.md`
  — the review findings and the recurring shape behind them.
- ADR-100 — amended in place for the instance-scoped `done` and probe-derived verification.
