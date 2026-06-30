---
title: "await-ci 900s timeout races CI-under-contention → prod deploy stalled ~2.5h"
date: 2026-06-30
incident_pr: 5798
incident_window: "2026-06-30 14:59Z–17:30Z (approx)"
recovery_at: "2026-06-30 ~17:30Z"
suspected_change: "web-platform-release.yml await-ci fixed 900s poll window (#5052 / PR #5051), exposed under GitHub runner contention"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability/correctness (prod froze on an old build)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach; this is an availability/CD-timing incident, not a confidentiality event"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The `web-platform-release` workflow's `await-ci` gate fail-closes the prod `deploy` job when CI-on-main
is slower than its fixed 900s poll window. Under GitHub runner contention this raced on **every**
squash-merge, and because each successive release lost the same race, the documented "next normal
release self-heals the deploy" recovery did **not** hold. Production stalled ~2.5h on an old build
(`badacd118`, deployed 14:59Z) while two consecutive releases failed identically.

## Status

resolved

## Symptom

`await-ci` logged `attempt 90: test status=missing` → `Timed out after 900s waiting for CI test
(last status=missing) — blocking deploy (fail-closed).` for the full window, then the `deploy` job was
skipped. Meanwhile the CI `test` check-run on the squash SHA was merely **queued** behind a runner
backlog and completed `success` minutes *after* await-ci had already given up.

## Incident Timeline

- **Start time (detected):** 2026-06-30 ~16:50Z (operator noticed prod frozen after the second failed release)
- **End time (recovered):** 2026-06-30 ~17:30Z
- **Duration (MTTR):** ~2.5h from the stale-build deploy (14:59Z) to recovery

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-30 14:59Z | Prod deployed `badacd118` (last good deploy before the stall). |
| system | 2026-06-30 16:23Z | Release `ee0a11852`: `await-ci` timed out (900s, status=missing), `deploy` skipped; CI later went green. |
| system | 2026-06-30 16:50Z | Release `5b096c280`: same race — `await-ci` timed out, `deploy` skipped. |
| human | 2026-06-30 ~16:50Z | Incident detected — prod still on `badacd118` ~2.5h. |
| human | 2026-06-30 ~17:30Z | After CI-on-main went green on a SHA containing the commit, `gh run rerun --failed` re-ran the `5b096c280` release; `await-ci` found the now-present `test=success` → `deploy` proceeded. Prod cut over to `5b096c280`; `live-verify` green. |

## Participants and Systems Involved

GitHub Actions (`web-platform-release.yml` `await-ci` / `deploy`; `ci.yml` `test` aggregator), the prod
web-platform deploy webhook, and the operator (manual `gh run rerun --failed` recovery).

## Detection (+ MTTD)

- **How detected:** manual — operator observed prod frozen on an old build after a second consecutive release failed identically. No automated page fired (fail-closed `await-ci` was pull-only; no `if: failure()` notifier existed, and the `release` job's "released!" Slack/email fired independent of `await-ci`, masking the stall).
- **MTTD:** ~time between the 14:59Z stale deploy and the ~16:50Z notice.

## Triggered by

system — GitHub runner-queue contention delayed the `test` aggregator's shards.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `await-ci` fixed 900s window < real CI-under-contention latency; the `test` check-run is absent while shards queue | incident log shows `status=missing` for the full 900s while the ci.yml run existed (did not hit the `total_count==0` fast-fail) | none | CONFIRMED |

## Resolution

Re-ran the failed `5b096c280` release after CI-on-main went green; `await-ci` found `test=success` and
the deploy proceeded. The **durable fix** (this PR, #5798): replace the fixed 900s window with an
**adaptive wait on the ci.yml-run liveness** — poll the workflow RUN (`status != "completed"` blocklist)
instead of the missing `test` check-run, exit `success` only on the `test` check-run
`conclusion==success`, fail-closed on a wall-clock ceiling (`elapsed >= CEILING_S=3000s`, sized over the
observed p100 ~28m), gate `migrate` on `await-ci` with a leading `always() &&`, and add a `notify-gated`
Slack push so a fail-closed gate is no longer silent.

## Recovery verification

The `5b096c280` release re-run deployed cleanly and `live-verify` concluded green (operator-confirmed
2026-06-30). The durable fix is verified statically: `actionlint` green, extracted `await-ci` body
`bash -n` + `shellcheck` clean, and a 13-case dry-run of the loop branch decisions against synthesized
fixtures (incl. the wall-clock-ceiling fail-closed path). Live self-heal confirmation is the read-only
AC16 check on the next real CI-under-contention squash-merge.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did prod freeze?** The `deploy` job was skipped on two consecutive releases.
2. **Why was deploy skipped?** It is gated on `needs.await-ci.result == 'success'`, and `await-ci`
   fail-closed (timed out).
3. **Why did await-ci time out?** It polled the synthetic `test` aggregator check-run on a fixed 900s
   window, and that check-run did not exist within the window.
4. **Why didn't the check-run exist?** The `test` aggregator is `needs:[shards] + if:always()`; GitHub
   does not create the `test` check-run until those shards reach a terminal state. Under runner
   contention the shards sat `queued` past 900s.
5. **Why didn't "next release self-heals" recover it?** Each consecutive squash-merge lost the **same**
   race under sustained contention, so no release in the busy window ever reached `deploy` — the
   self-heal chain assumes the *next* push wins the race, which it doesn't when contention persists.

## Versions of Components

- **Version(s) that triggered the outage:** `web-platform-release.yml` with the fixed `MAX_ATTEMPTS=90 × INTERVAL_S=10` (900s) `await-ci` window (shipped #5052 / PR #5051).
- **Version(s) that restored the service:** the re-run of release `5b096c280`; durable fix in PR #5798.

## Impact details

### Services Impacted

The prod web-platform app served the previous build (`badacd118`) for ~2.5h — the merged fix/feature
was absent from production though the release was reported "released!".

### Customer Impact (by role)

- Prospect: none (marketing site unaffected; this is the app deploy).
- Authenticated app user: degraded — ran an older app build for ~2.5h (missing the just-merged change). No data loss, no auth impact.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None measurable (single-user / tenant-zero stage).

### Team Impact

~30–40 min of operator time on manual diagnosis + `gh run rerun --failed` recovery.

## Lessons Learned

### Where we got lucky

The fail-closed posture meant prod stayed on a *known-good* build rather than shipping untested code —
the gate failed safe, just silently and without self-heal.

### What went well

The fail-closed design correctly blocked an unverified deploy; the manual `rerun --failed` recovery was
clean once CI-on-main went green.

### What went wrong

The 900s window was shorter than real CI-under-contention latency (~28m p100), the recovery was silent
(no page) AND misleading (the `release` job posted "released!" while prod was frozen), and "next release
self-heals" does not hold under sustained contention.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5806 | Deploy off `workflow_run: completed` on ci.yml — the structural >ceiling self-heal that removes the timeout cliff, the held-runner cost, and the out-of-order/superseded-deploy risk (ADR-072 option 3). | open |
