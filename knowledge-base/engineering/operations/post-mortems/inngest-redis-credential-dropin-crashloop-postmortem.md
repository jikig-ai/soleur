---
title: "inngest-redis crash-looped for 17h on a stale credential path, and its stderr reached no telemetry"
date: 2026-08-06
incident_pr: 7301
incident_window: "2026-08-05T06:34:07Z (first `dial tcp 127.0.0.1:6379: connect: connection refused`) → still failing at 2026-08-05T23:23:49Z when PR-1 was authored (~17h, ongoing at PIR time)"
recovery_at: "pending — PR-1 (#7301) ships the credential drop-in + the diagnostic; recovery is verified post-merge on delivery + daemon-reload, and #7286 closes on the watchdog's own healthy path"
suspected_change: "#7241 (per-config Doppler read tokens) merged 2026-08-04T16:18Z; onset 2026-08-05T06:34Z. inngest-redis.service is the only Doppler consumer #7095's sweep left without a `soleur-doppler-token` drop-in, so it alone kept resolving the pinned copy in /etc/default/inngest-server. A config-scoped token errors rc=1 on a wrong `-c`, and this unit hardcodes `--config prd`."
brand_survival_threshold: single-user incident
status: mitigation-shipping
triggers:
  - availability (Inngest scheduler/executor on web-1 — all scheduled and event-driven background jobs)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability-only. inngest-redis holds the queue and
# run-state for background jobs; the failure mode is that jobs never RUN, not that
# data is disclosed or altered. No personal data left the host: redis never started,
# so it served nothing, and the crash-loop's stderr stayed on-box (that unreadability
# is itself the second defect this PIR records). No confidentiality or integrity loss
# — GDPR Art. 33/34 do not apply. The `single-user incident` threshold is carried from
# the plan: one operator losing their entire background-job substrate for 17 hours
# with no actionable signal is the incident.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

`inngest-redis.service` on prod web-1 (`hetzner-123931471`) crash-looped every ~5 seconds from
2026-08-05T06:34:07Z. Redis therefore never bound `127.0.0.1:6379`, and `inngest-server` — healthy
against Postgres — died on `error creating redis client: dial tcp 127.0.0.1:6379: connect:
connection refused` every ~9 seconds.

Every scheduled and event-driven background job stopped: inbound-email triage, `cron/*` workflows,
`step.sleep` reminders. There was no user-visible error — the app answered 200 while the work never
happened.

The external watchdog detected it at 07:17, auto-dispatched `restart-inngest-server.yml`, the
restart could not help (a restart cannot conjure a Redis), and the 45-minute age gate suppressed
further restarts at 10:06 with `ci/inngest-restart-exhausted`. The age gate behaved correctly — it
suppressed a restart that provably could not help. The defect was that exhaustion produced no
evidence.

## Root cause

Two independent defects, and the second is why the first cost 17 hours instead of 20 minutes.

**1. A credential path with no re-delivery.** `/etc/default/inngest-server` holds a Doppler token
grep-extracted out of `/etc/default/webhook-deploy` (`inngest-bootstrap.sh:586`) and then pinned
forever (`:567-568` preserves the file whenever its value still matches `^DOPPLER_TOKEN=dp.`), so a
dead-but-well-formed token never self-heals — not even on re-bootstrap. #7095 fixed this for the
consumers it found by delivering `/etc/default/soleur-doppler-token` plus systemd drop-ins for
`vector.service`, `inngest-heartbeat.service` and `inngest-server.service`.

`inngest-redis.service` was not among them, and it is the one unit where the omission is
load-bearing rather than latent:

- it reads **only** the pinned copy;
- its `ExecStart` runs `doppler run --config prd` **unconditionally** — no `[ -n "$DOPPLER_TOKEN" ]`
  gate, so no degraded-but-alive arm, unlike the four cron-egress / container-restart-monitor units;
- `Restart=on-failure` + `RestartSec=5` against systemd's default `StartLimitIntervalSec=10s` /
  `StartLimitBurst=5` **never latches `failed`**. That is why it looped for 17 hours instead of
  stopping, and why a `failed`-keyed alarm would never have fired.

**2. The failing component could not report.** For 17 hours the only fact any remote surface could
establish about `inngest-redis` was *it exited non-zero*. Its stderr was unreadable off-box, so the
watchdog printed a hard-coded guess into the incident issue and nobody could adjudicate it — while
the decisive evidence sat one already-authenticated GET away on a route that simply had no field
for it.

## Timeline

| Time (UTC) | Actor | Event |
|---|---|---|
| 2026-08-04 16:18 | agent | #7241 merges (per-config Doppler read tokens) |
| 2026-08-05 04:28:50 | — | Last healthy probe: `Inngest healthy on attempt 1/3: functions=68` |
| 2026-08-05 06:34:07 | — | First failure: `dial tcp 127.0.0.1:6379: connect: connection refused` |
| 2026-08-05 06:34:09 | — | `inngest-redis.service: Failed with result 'exit-code'.` — then every ~5s, continuously |
| 2026-08-05 07:17 | agent | Watchdog detects `inngest_down`, files #7286, dispatches `restart-inngest-server.yml` |
| 2026-08-05 07:18:28 | agent | `ACCEPTED: restart inngest` → `INNGEST_HEALTH: healthy=false after 10 attempts` |
| 2026-08-05 10:06 | agent | Age gate suppresses further restarts; `ci/inngest-restart-exhausted` applied |
| 2026-08-05 ~22:40 | agent | `/soleur:go 7286` — root cause established from telemetry, no host login |
| 2026-08-05 23:23:49 | agent | Re-confirmed still crash-looping (journal tail fresh to 2s before the read) |
| 2026-08-06 | agent | PR #7301 (PR-1): credential drop-in + nine `services.inngest_redis*` probe fields |

## What went well

- **The root cause was established entirely from telemetry** — Better Stack + `/hooks/deploy-status`
  + `/hooks/inngest-liveness`. No host login, no operator asked to fetch anything
  (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **The age gate was right.** It suppressed a restart that could not help. Nothing about the
  suppression logic needs changing.
- **The fix is provable at code level**, independent of the unreadable host journal: "this unit has
  no drop-in" is a grep against `FILE_MAP`.
- **Review caught what the author's own verification did not.** Three agents found 20 findings,
  including that the "class-closing" invariant closed only a subset, that the new scrubber was a
  weaker fork of `vector.toml`'s (a Postgres DSN survived verbatim), and that a new probe could hang
  the one diagnostic surface the same PR left standing.

## What went wrong

- **A sweep that fixed a class missed a member, and nothing detected the miss.** #7095 enumerated
  Doppler consumers by hand. The invariant it discovered — *no secret may be copied into a second
  host file without the copy inheriting the original's re-delivery path* — was written down in a
  code comment and left unenforced.
- **A unit whose restart parameters guarantee it never latches `failed`** is invisible to any alarm
  keyed on `failed`, and nothing said so.
- **`is-active` on a 5-second crash loop is a coin flip.** Three probes 8 seconds apart reported
  `degraded, degraded, durable` — a signal that answers three different ways in 16 seconds is not a
  signal.
- **The watchdog printed a hypothesis it could not support.** A guess rendered as prose anchors the
  next responder on the wrong branch, which is what happened here.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7286 | PR-2 / PR-3 remediation: attach real host state to the `[ci/inngest-down]` issue body, delete the hard-coded hypothesis sentence, de-flap `derive_durability_state`, land ADR-169 (detect-and-fail-loud, never silently degrade to SQLite), correct the two falsified `model.c4` descriptions, add the runbook's Redis-down decision table, and build the Phase-6 remedy arm the PR-1 payload names. Closes on the watchdog's own healthy path. | agent |
| #6551 | The Vector Source-4 emitter↔allowlist pairing class. PR-1 adds both halves to the payload (`SyslogIdentifier` from the unit, `redis_allowlisted` from the running config) so the pair is measurable; the general "a row ships that no source admits" defect — including `inngest-heartbeat`, which is dark by the same mechanism — belongs here rather than being absorbed into the redis fix. | agent |
| #7308 | inngest is pinned at v1.19.4 against upstream v1.41.1, and nothing monitors that pin's freshness (`vendor-pin-verify.yml` does not mention inngest). Not a cause of this incident — recorded because it was found while investigating it, and because a freshness owner is the thing that would surface the next one. | agent |

## Prevention

Shipped in PR-1 (#7301):

- **The invariant is now a test, not a comment.** `inngest.test.sh` asserts that every unit reading
  the pinned copy as a REQUIRED `EnvironmentFile`, invoking doppler directly, with no
  live-credential source of its own, carries a drop-in across the full seven-surface delivery
  lockstep — over BOTH checked-in `.service` files and heredoc-authored units (review found the
  first version walked only the glob, leaving three hazard-class units invisible).
- **The unit can now report.** Nine `services.inngest_redis*` fields on `/hooks/deploy-status`,
  including `NRestarts` + `ActiveEnterTimestamp` + `ActiveState` (so "still looping" is decidable
  from ONE read rather than a coin-flip `is-active`), `DropInPaths` as systemd's *loaded* view (so
  "fix delivered" and "fix delivered inert" are distinguishable), and `tail_status` as a four-value
  enum (so an empty tail is not conflated with an absent journalctl).
- **The credential-bearing tail is scrubbed on the response path**, with the rules ported from
  `vector.toml` rather than re-derived, and bounded from both sides — secrets must go AND the
  diagnosis must survive.
- **The no-SSH gate can now fail.** `lint-infra-no-human-steps.py` returned `OK … exit 0` against a
  runbook carrying seven `ssh root@` instructions: its pattern never matched the `user@host` form
  AND `scan_text` skipped fenced content wholesale. Both fixed; all seven host logins removed with a
  per-line verb disposition.

Not yet shipped, tracked above: the watchdog attaching the evidence it can now read (#7286), and a
freshness owner for the vendored pin (#7308).

## Links

- Incident issue: #7286
- PR-1: #7301
- Plan: `knowledge-base/project/plans/2026-08-06-fix-inngest-redis-crash-loop-dark-error-channel-plan.md`
- Learning: `knowledge-base/project/learnings/2026-08-06-my-class-closing-invariant-closed-a-subset-and-my-battery-had-a-red-control.md`
- Prior sweep that established the invariant: #7095
- Suspected trigger: #7241
