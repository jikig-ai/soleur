---
title: "web-platform deploys stuck on stale image — #4886 .cron ENOSPC + oneshot-heartbeat misreport"
date: 2026-06-03
incident_pr: 4886
incident_window: "2026-06-03 17:24Z–18:00Z"
recovery_at: "2026-06-03 18:00Z"
suspected_change: "#4886 (cron-workspace-gc: sudo mkdir -p /mnt/data/workspaces/.cron added to ci-deploy.sh critical path)"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - deploy-pipeline availability (web-platform-release.yml deploy-completion gate)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/deploy incident, no personal-data exposure"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

`web-platform-release.yml` deploy jobs failed on three consecutive merges to `main`
(17:24–17:42 UTC, 2026-06-03), leaving production stuck on a stale image
(`v0.101.100`). Each run exited non-zero at the "Verify deploy script completion"
step with `reason=unhandled`. The failure JSON also reported
`services.inngest_heartbeat: inactive`, which the `/ship` Phase 7 post-merge
auto-filer surfaced as the suspected root signal when it filed #4896 — a
misdiagnosis. The real cause was an ENOSPC `mkdir` introduced by #4886 on the
already-full shared volume; recovery came from #4895's revert at 18:00 UTC.

## Status

resolved — recovered by #4895 (`fix(cron): revert .cron isolation that deadlocked
the deploy on a full volume`); production current on `v0.102.0` (build `f78bb0a1`).

## Symptom

- 3 consecutive `web-platform-release.yml` deploy failures (17:24 / 17:35 / 17:42
  UTC) at the deploy-completion gate, all `reason=unhandled`.
- Production `/health` stuck on `v0.101.100`; new merges merged-but-not-deployed.
- Failure JSON showed `services.inngest_heartbeat: inactive`, `inngest_server: active`,
  `vector: active`, `journald_storage.persistent: false`, `root_avail: 54G`.

## Incident Timeline

- **Start time (detected):** 2026-06-03 ~17:42Z (third consecutive failure / #4887 ship session)
- **End time (recovered):** 2026-06-03 18:00Z
- **Duration (MTTR):** ~18 minutes (from detection to #4895 merge + first green deploy)

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 17:24 | Deploy for #4886 (`1998af5f`) fails at completion gate (`reason=unhandled`). |
| agent | 17:35 | Deploy for #4871 (`251b80ea`) fails (same gate). |
| agent | 17:42 | Deploy for #4887 (`4d1e1cb8`) fails (same gate); /ship Phase 7 auto-filer opens #4896, naming `inngest_heartbeat: inactive` as the suspected root signal. |
| agent | ~18:00 | #4895 reverts the `.cron` mkdir + repoints `CRON_WORKSPACE_ROOT` to `/workspaces`. |
| agent | 18:00 | Deploy for `b06de5b6` (#4895) succeeds. Queue unstuck. |
| agent | 18:06 / 18:17 | Subsequent deploys (`1350733f`, `f78bb0a1`) succeed; prod swaps to `v0.102.0`. |

## Participants and Systems Involved

`web-platform-release.yml` (deploy-completion gate), `ci-deploy.sh` (EXIT trap +
`final_write_state`), `cat-deploy-state.sh` (deploy-status reporter), the shared
20 GB `/mnt/data` volume (full — the #4882 ENOSPC condition), `cron-workspace-gc`
(the GC introduced by #4886).

## Detection (+ MTTD)

- **How detected:** automated — the `/ship` Phase 7 post-merge release-verification
  step (which monitors `web-platform-release.yml`) caught the failed deploys and
  filed #4896.
- **MTTD:** ~18 min from the first failed deploy (17:24) to the filing during the
  #4887 ship session. The three-deploy gap is the cost of not failing the merge
  itself on a failed *deploy* (merge CI and deploy are decoupled).

## Triggered by

system — a code change (#4886) interacting with a pre-existing degraded
environment (the full `/mnt/data` volume, #4882).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `inngest_heartbeat: inactive` = broken heartbeat unit (the #4896 framing) | field present in failure JSON | gate never reads the field (`grep -c inngest_heartbeat web-platform-release.yml` = 0); `inactive` is the healthy steady state for a `Type=oneshot` timer-driven unit | REJECTED (red herring) |
| #4886 moved/broke the heartbeat systemd unit or its storage | #4886 touched the cron substrate | `#4886 --stat` touches none of `inngest-bootstrap.sh`/`inngest.tf`; heartbeat unit untouched | REJECTED |
| #4886's `sudo mkdir -p /mnt/data/workspaces/.cron` ENOSPC'd under `set -e` | full 20 GB volume (#4882); mkdir on critical path; EXIT trap wrote `reason=unhandled` | — | CONFIRMED |

## Resolution

#4895 reverted #4886's `.cron` mkdir and repointed `CRON_WORKSPACE_ROOT` back to
`/workspaces`, removing the ENOSPC-on-critical-path failure. Deploys recovered
immediately (success at 18:00 / 18:06 / 18:17 UTC).

## Recovery verification

`gh run list --workflow=web-platform-release.yml` shows `success` from `b06de5b6`
(#4895) onward; `https://app.soleur.ai/health` returns `version: 0.102.0,
build_sha: f78bb0a1, status: ok`. Both verified read-only (no SSH) at PIR-write time.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did deploys fail?** The deploy-completion gate saw `reason=unhandled`.
2. **Why `reason=unhandled`?** `ci-deploy.sh` exited non-zero without calling
   `final_write_state`, so the `EXIT` trap wrote the `unhandled` sentinel.
3. **Why did `ci-deploy.sh` exit non-zero?** `sudo mkdir -p /mnt/data/workspaces/.cron`
   (added by #4886) failed with ENOSPC under `set -e`.
4. **Why ENOSPC?** The shared 20 GB `/mnt/data` volume was already full (the #4882
   condition — leaked cron clones), and #4886 put a new write on the deploy's
   critical path.
5. **Why was this misdiagnosed as a heartbeat fault?** `cat-deploy-state.sh`
   reported `inngest_heartbeat` from the **oneshot** `.service`, whose healthy
   steady state is `inactive`; the auto-filer read the correlated field as causal.

**Final root cause:** a new critical-path filesystem write (#4886) on a full
volume, compounded by a deploy-status reporter that surfaced a misleading
oneshot-unit state, steering the first triage at the wrong subsystem.

## Versions of Components

- **Version(s) that triggered the outage:** `v0.102.0` build attempt for #4886 (deploy failed; prod stayed on `v0.101.100`).
- **Version(s) that restored the service:** `v0.102.0` via #4895 (`b06de5b6`).

## Impact details

### Services Impacted

web-platform deploy pipeline (3 deploys stuck). Production *serving* was unaffected
— it continued serving the last good image (`v0.101.100`); only the deploy of newer
code was blocked.

### Customer Impact (by role)

- Prospect: none (marketing/app served normally on the prior image).
- Authenticated app user: none observable — prod stayed healthy on `v0.101.100`; only *new* code was delayed ~36 min.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

~1 ship session of triage misdirection (the `inngest_heartbeat` red herring) before
#4895's revert landed.

## Lessons Learned

### Where we got lucky

The three stuck deploys were all low-risk (a workspace-pill UI change and two
docs/KB refactors), so the ~36-min stale-code window had no user-facing
consequence. A user-facing hotfix stuck behind the same gate would have been an
actual outage.

### What went well

- The `/ship` post-merge release-verification auto-filer caught the silent deploy
  failures and opened an issue rather than letting them rot (this is exactly the
  "merged ≠ deployed" gap the gate exists to close).
- #4895's revert was fast and surgical.

### What went wrong

- A new filesystem write was added to the deploy's critical path without guarding
  against the known-full shared volume (#4882).
- The deploy-status reporter surfaced a `Type=oneshot` unit's transient `inactive`
  state as if it were a liveness fault, steering triage at the wrong subsystem and
  costing a misdiagnosis (the #4896 framing).

## Follow-ups

- [x] Fix the reporter misreport: add `services.inngest_heartbeat_timer` (durable
      liveness) + document the oneshot steady-state semantics — **this PR** (Ref #4896).
- [ ] Dedicated cron-clone volume / capacity isolation so the shared `/mnt/data`
      volume cannot ENOSPC the deploy critical path — tracked in #4891 (open).
- [ ] journald `persistent: false` on the host (orthogonal) — tracked in #4792.

## Action Items

- Reporter misreport fix — **this PR** (Ref #4896); closes the mis-signal class.
- Capacity isolation for cron clones — #4891 (deferred, open).
- journald persistence — #4792 (deferred, open).
