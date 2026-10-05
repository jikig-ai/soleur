---
title: "Postmortem: the zot mirror blocked releases for ~18h while the error named a cause the same job had refuted"
date: 2026-08-04
incident_pr: 7244
incident_window: "2026-08-03T17:11:50Z (first Web Platform Release failure at the zot-mirror step) → 2026-08-04T11:09:24Z (run 30903635026, first release with every mirror step green). ~17h58m. Eight consecutive release failures in the window; FIVE at the mirror step, three at an unrelated `Verify deploy script completion` step (see Open questions)."
recovery_at: "2026-08-04T11:09:24Z — run 30903635026. Recovery was NOT attributed: no fix was applied to the crash-looping registry (#7247 is still OPEN), so the mirror leg recovered on its own and can regress at any time."
suspected_change: "No deploy-time change caused it. The measured proximate cause is zot crash-looping on the registry host at ~4 restarts/min from 17:08 UTC (#7247): a `docker login` plus a three-tag `crane copy` takes tens of seconds, so it straddles a restart, the tunnel's origin dial fails mid-push, and that surfaces as `websocket: bad handshake`. The REASON the crash-loop began is UNKNOWN and this PIR does not guess it — that is the invariant this incident is about, applied to itself."
brand_survival_threshold: aggregate pattern
status: unresolved but ended
triggers:
  - websocket bad handshake on the registry bridge
  - zot crash-looping at ~4 restarts/min (#7247)
  - operator-facing error naming a credential the same job had verified live
  - production pinned behind for the length of the window
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability incident. No personal data was accessed, exfiltrated, altered or lost: the failure is a container image that could not be pushed to a mirror. No database, storage bucket, or user-facing data path was involved."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

From 17:11 UTC on 2026-08-03, `Web Platform Release` failed at the zot-mirror bridge. The
failure message told the operator the cause was a stale `REGISTRY_PUSH_ACCESS_TOKEN_*` and to
run the drift check. A step **in the same job, six minutes earlier**, had already printed
*"Registry-push Access service token verified live."*

The message asserted a cause the job had, by then, disproved — and it was wrong on the merits.
Both hypotheses it steered toward were refuted by measurement: the Cloudflare Access policy was
intact (token in the allow policy, `client_id` byte-matching Doppler, expiring 2027-07-29), and
the tunnel connector had never re-registered because it had never dropped — there is no
`cloudflared` on the registry host at all. A sibling advisory supplied a third refuted premise,
"the host rebooted at 17:13", on a host with 18.2 days of uptime; that advisory was reading a
*cumulative* `reboot_count` as an event.

**This was the third iteration of one defect class on one code path.** Iterations one
(2026-07-15) and two (2026-07-29) were each fixed by rewriting the offending sentence, and each
re-drifted. The 2026-07-29 fix wrote a *new* standing claim — "the MEASURED cause class is a CF
Access service-token rotation that never propagated" — which was true of that incident and false
as a general fact, and which is exactly what iteration three inherited.

## Status

`unresolved but ended` — releases flow again, but nothing was done to the crash-loop that caused
the blockage. #7247 is OPEN and recurrence is live. The PR this PIR accompanies fixes the
**message**, not the cause, and deliberately says so.

## Symptom

`Web Platform Release` failing at *"Mirror image GHCR→zot (crane) + cosign-sign the zot digest"*
with `websocket: bad handshake`, and an `::error::` naming a credential rotation as the cause.
Production stayed pinned behind for the length of the window, so every fix merged during it was
invisible to users until the mirror recovered.

## Incident Timeline

- **Start time (detected):** 2026-08-03T17:11:50Z (first failing run, 30835641260)
- **End time (recovered):** 2026-08-04T11:09:24Z (run 30903635026)
- **Duration (MTTR):** ~17h58m

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-08-03T17:08 | zot begins crash-looping on the registry host at ~4 restarts/min (#7247). Root reason UNKNOWN. |
| agent | 2026-08-03T17:11:50 | Run 30835641260 fails at the mirror step. The error names a stale registry-push token; a step six minutes earlier had printed that the same token verified live. |
| agent | 2026-08-03T19:55 / 20:22 / 21:06 | Three further release failures (one at an unrelated deploy-verify step; two at the mirror). |
| human | 2026-08-03T20:54:52 | Issue #7242 filed, noting the error's own diagnosis is refuted in-job. |
| agent | 2026-08-04T09:17 / 09:41 | Two failures at `Verify deploy script completion` — a different step (see Open questions). |
| agent | 2026-08-04T10:25 / 10:54 | Two further mirror-step failures. |
| agent | 2026-08-04T11:09:24 | Run 30903635026: every mirror step green. Blockage ends with no fix applied. |

## Participants and Systems Involved

`Web Platform Release` / `reusable-release.yml`; the `cf-tunnel-registry-bridge` composite
action; the self-hosted zot registry (ADR-096) and its Cloudflare Tunnel origin; Doppler
(`REGISTRY_PUSH_ACCESS_TOKEN_*`); Better Stack (the `zot_restarts` series that decided the
diagnosis).

## Detection (+ MTTD)

- **How detected:** external/manual. The operator noticed prod was releases behind and read the
  job log. No monitor fired on "the mirror has failed N releases in a row" — the recurrence
  alarm that should have caught it **could not file its issue**, see Root cause 2.
- **MTTD:** ~3h43m (17:11:50 first failure → 20:54:52 issue filed).

## Root cause

### 1. The message named a cause nothing had measured

The failure path hardcoded a credential-rotation remedy. It did not read the token verdict its
own job had computed six minutes earlier, and `check-cloudflare-token-drift.sh` exits 1 for
`dead > 0` **OR** `unverifiable > 0` — so even a job that *did* consult the exit code would
print *"the token is STALE, rotate it"* about a token nothing graded.

A cause measured **once** is not a cause measured **always**. That is the whole finding, and it
is now ADR-166.

### 2. The recurrence alarm was structurally unable to report

`scheduled-zot-restart-loop.yml` exists to catch precisely this. Seven of its issue-filing steps
carried a bare `if:`, inheriting an implicit `success()` — and a FIRE is a non-zero exit **by
design**. Measured on run 30851584863: the checker failed, all seven steps skipped, and four
hours of a 4/min climb produced no issue. The alarm was dark exactly when it mattered.

### 3. A sibling advisory manufactured a third false premise

The private-NIC advisory reported a reboot with no date, reading a cumulative `reboot_count` as
an event. An 18-day-old convergence read as news and sent part of the investigation to a host
that had not rebooted.

## What went well

- The in-job token verification existed and was correct. The information needed to refute the
  message was already printed in the same log — the failure was that nothing consumed it.
- The refutations were cheap once someone measured rather than read: the Access policy check,
  the `cloudflared` absence, and the uptime each took one command.

## What went badly

- Two prior iterations of this defect were "fixed" editorially, and both re-drifted. Rewriting a
  sentence does not survive the next author.
- The self-checking apparatus failed in the same direction as the thing it watches: the alarm
  could not file, and the advisory dated nothing.
- **The gate that should have demanded this PIR did not fire.** `ship-incident-pir-gate.sh`
  matched only user-facing outage vocabulary; a delivery outage — releases blocked, production
  pinned versions behind — matched none of it, so the PR fixing an 18-hour release blockage
  reported "no incident signal". Fixed in this PR, with both directions mutation-pinned.

## Open questions (not investigated)

- Three of the eight failures in the window (19:55, 09:17, 09:41) failed at `Verify deploy
  script completion`, not at the mirror. They are **not** explained by this incident and were not
  investigated; the runs are 30847900745, 30895651460, 30897409450. Releases are green as of
  11:09, so this is recorded rather than chased.
- **Why** zot began crash-looping at 17:08 is unknown. This PIR records it as UNKNOWN rather
  than guessing — the invariant applied to itself. Tracked as #7247.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7247 | zot is crash-looping on the registry host (~4/min since 17:08 UTC) — the proximate cause of the blockage. Still OPEN; recovery at 11:09 was unattributed, so recurrence is live. Enrolled in the follow-through sweeper. | agent |
| #7248 | The zot health verdict is read-path only: a registry serving reads while every push fails grades green. This is why nothing alarmed on the push leg. | agent |

## Prevention

- **ADR-166** — no operator-facing message emitted by CI may name a cause the job did not
  measure. Enforced by `scripts/lint-diagnosis-claims.sh` (scanning `.github/workflows/`,
  `.github/actions/`, `scripts/` **and** `apps/web-platform/infra/`, the fourth added by
  #7310), ratcheted by a `.highwater`, registered in
  `test-all.sh` whose `scripts` shard feeds the CI Required `test` job — blocking, not advisory.
- **`scripts/alarm-issue-filing-guard.sh`** — blocks issue-filing steps that cannot report the
  verdict they exist for. Widening it from the 2 workflows originally walked to all 71 surfaced
  11 pre-existing violations across six other alarms, carried as a ratcheting baseline.
- **Delivery outages now trip the PIR gate.** Without the fix in this PR, this postmortem would
  not have been written, because the gate does not read "prod is N releases behind" as an event.

## Related

- ADR-166 — a CI message may only name a cause the job measured
- `knowledge-base/engineering/operations/post-mortems/2026-07-15-zot-mirror-silent-skip-connector-homogeneity-postmortem.md` (iteration one)
- `knowledge-base/engineering/operations/post-mortems/2026-07-29-v0244-1-published-green-with-an-unpullable-image-postmortem.md` (iteration two)
- `knowledge-base/project/learnings/2026-08-04-the-pr-that-fixed-unmeasured-claims-shipped-three-of-them.md`
- #7242 (this incident), #7247, #7248, #6416 (silent mirror), #6288 (zot crash-loop class)
