---
title: "fix(deploy): correct oneshot heartbeat misreport + confirm #4886 deploy recovery (#4896)"
date: 2026-06-03
type: ops-remediation
classification: ops-only-prod-write
lane: cross-domain
brand_survival_threshold: aggregate pattern
issue: 4896
related_prs: [4886, 4895]
related_issues: [4891, 4882, 4881, 4650, 4652, 4116]
---

# fix(deploy): correct oneshot heartbeat misreport + confirm #4886 deploy recovery (#4896)

> Note: this one-shot path ran no brainstorm; no `spec.md` exists for the branch, so
> `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Issue #4896 reports that web-platform deploys have failed on 3 consecutive merges
since #4886, the deploy-completion gate fails with `reason=unhandled`, the root
signal is `inngest_heartbeat: inactive`, and prod is stuck on a stale image
(v0.101.100). It asks us to root-cause #4886's cron/KB-volume isolation change as
having "moved/broken the heartbeat systemd unit or its storage path," restore the
heartbeat service, and unstick the deploy queue.

**Premise validation (Phase 0.6) found the premise substantially stale.** The
incident is already resolved by PR #4895 (the revert cited in the issue), which
merged at 2026-06-03 18:00:06 UTC. Verified facts as of plan-write time:

- **Deploy queue is unstuck.** `gh run list --workflow=web-platform-release.yml`
  shows the three failures at 17:24 / 17:35 / 17:42 (exactly the issue's table),
  then **success** at 18:00, 18:06, and 18:17 — all after #4895's revert.
- **Prod is current, not stale.** `https://app.soleur.ai/health` returns
  `version: 0.102.0, build_sha: f78bb0a1` (the latest merge #4890), uptime ~54 min.
  v0.101.100 is gone; prod swapped forward.
- **#4886 did NOT break the heartbeat systemd unit.** `inngest-bootstrap.sh`'s
  `inngest-heartbeat.{service,timer}` and `HEARTBEAT_SCRIPT` were untouched by
  #4886 (its diff touched only `ci-deploy.sh` line 432-465 — the `.cron` mkdir +
  `CRON_WORKSPACE_ROOT` — plus the GC function and tests). No storage-path move.
- **The actual gate failure was `.cron` mkdir ENOSPC under `set -e`.** #4886 added
  `sudo mkdir -p /mnt/data/workspaces/.cron` to ci-deploy.sh's critical path. On
  the already-full 20 GB shared volume (the exact #4882 ENOSPC state), the mkdir
  failed under `set -e`, ci-deploy.sh exited without calling `final_write_state`,
  and the `EXIT` trap (`ci-deploy.sh:111`) wrote `reason=unhandled`. #4895 reverted
  the mkdir and pointed `CRON_WORKSPACE_ROOT` back to `/workspaces`.
- **`inngest_heartbeat: inactive` was a red herring, not the gate input.** The
  "Verify deploy script completion" gate (`web-platform-release.yml:356-382`) keys
  **only** on `exit_code` and `reason`. It never reads `services.inngest_heartbeat`.
  The field is reported by `cat-deploy-state.sh:102,129` via `systemctl is-active
  inngest-heartbeat.service` and was surfaced in the failure JSON only because the
  reporter always attaches it — the /ship Phase 7 auto-filer (who filed #4896)
  mis-read the correlated field as the root signal.

There IS a genuine latent bug worth fixing, distinct from the (already-reverted)
deadlock: **`inngest-heartbeat.service` is a `Type=oneshot` unit driven by
`inngest-heartbeat.timer`** (`inngest-bootstrap.sh:216-245`). A oneshot unit
without `RemainAfterExit=yes` reports `inactive` from `systemctl is-active` as soon
as its `ExecStart` completes successfully — i.e. **`inactive` is the NORMAL,
healthy steady state between the 60s timer fires**, not a fault. `cat-deploy-state.sh`
reports the `.service` state, so the deploy-status JSON shows `inactive` on a
perfectly healthy host, which is exactly the misleading signal that mis-framed this
incident. The watchdog code comment confirms the design:
`cron-inngest-cron-watchdog.ts:14` — "The /health heartbeat
(inngest-heartbeat.timer → Better Stack) proves only process liveness."

This plan therefore does NOT "restore a broken heartbeat" (it was never broken). It:

1. **Confirms recovery is durable** (read-only verification — no prod write needed).
2. **Fixes the latent observability misreport** so a healthy oneshot heartbeat never
   again reads as a scary `inactive` and mis-frames the next incident: report the
   `.timer`'s active state (the durable liveness signal) alongside (or instead of)
   the oneshot `.service`'s transient state.
3. **Closes #4896 with the corrected RCA** (post-merge, `gh issue close`), referencing
   #4895 as the actual fix and #4891 as the deferred capacity work.

This is a small, surgical change to a read-only no-SSH reporter plus its test, framed
as the durable fix for the mis-signal — NOT a re-litigation of the #4895 revert.

## Research Reconciliation — Spec vs. Codebase

| Issue/premise claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "deploys failing since #4886, prod stuck on v0.101.100" | `gh run list` shows success at 18:00/18:06/18:17 post-#4895; `/health` = v0.102.0 build f78bb0a1, uptime ~54m | Already recovered. Plan confirms read-only; no re-deploy needed. |
| "deploy-completion gate fails with `reason=unhandled`" | Gate (`web-platform-release.yml:356-382`) keys on `exit_code`/`reason` only; `reason=unhandled` = `EXIT` trap (`ci-deploy.sh:111`) on a non-zero exit that skipped `final_write_state` | True at incident time; cause was the `.cron` mkdir, reverted in #4895. No gate change needed. |
| "root signal `inngest_heartbeat: inactive`" | `inngest_heartbeat` is NOT read by the gate; it is a reporter field (`cat-deploy-state.sh:102,129`). For a `Type=oneshot` timer-driven unit, `inactive` is the healthy steady state | Red herring. Fix the reporter so the field reflects timer liveness, not the transient oneshot state. |
| "#4886 moved/broke the heartbeat systemd unit or its storage path" | #4886's diff touched `ci-deploy.sh` (`.cron` mkdir + `CRON_WORKSPACE_ROOT`), the GC fn, and tests — NOT `inngest-bootstrap.sh`'s heartbeat unit/script/storage | False. No unit or storage-path change occurred. Reframe: no restore needed. |
| "restore the heartbeat service" | Heartbeat unit + timer are intact and healthy on prod (the betteruptime ping is the liveness proof, separate from the systemd `is-active` read) | Nothing to restore. Fix the misreport that made a healthy unit look broken. |
| "`journald_storage.persistent: false`" in the failure JSON | `cat-deploy-state.sh:54-83` reports journald persistence; tracked separately under #4792. `root_avail: 54G` shows root disk was fine | Out of scope (separate concern, separate issue). Note in Non-Goals. |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct user-facing artifact — this
edits a read-only no-SSH deploy-status reporter (`cat-deploy-state.sh`) and its test.
The indirect risk is the one this incident already demonstrated: a misleading
deploy-status field that causes a future operator (or the auto-filer) to mis-diagnose
the next deploy incident, delaying recovery of a genuinely stuck deploy — which CAN
become user-facing (stale code on prod) if a real failure is masked or misattributed.

**If this leaks, the user's data / workflow / money is exposed via:** nothing — the
reporter is read-only, returns only systemd unit-state words and disk-headroom
numbers (no secrets; the heartbeat URL is deliberately kept out of the unit's journal
per `inngest-bootstrap.sh:195-198`). No regulated-data surface.

**Brand-survival threshold:** aggregate pattern. A single misread of one field is not
a per-user incident; the harm is the aggregate pattern of mis-signalled deploy health
eroding trust in the deploy-status gate over time. (Threshold `none` would require a
sensitive-path scope-out bullet; `aggregate pattern` requires the section only, which
is present.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Recovery confirmed read-only.** Plan body (Phase 0) records: latest
      `web-platform-release.yml` run conclusion = `success`; `/health` `version` ≥
      `0.102.0`; the three issue-cited failing runs are all strictly before the first
      post-#4895 success. Verification commands are baked into Phase 0, no SSH.
- [ ] **AC2 — Reporter reports the durable liveness signal.** `cat-deploy-state.sh`
      adds an `inngest_heartbeat_timer` field reading `systemctl is-active
      inngest-heartbeat.timer` (the timer is `active` on a healthy host), and the
      existing `inngest_heartbeat` (oneshot `.service`) field is retained with an
      inline comment documenting that `inactive` is the expected steady state for a
      timer-driven oneshot. Verified by `jq -e '.services.inngest_heartbeat_timer'`
      against a synthesized state fixture.
- [ ] **AC3 — Test coverage.** `cat-deploy-state.test.sh` asserts the new
      `inngest_heartbeat_timer` field is present across all 4 base-state branches
      (no_prior_deploy, OK, services-merge, corrupt_state), mirroring the existing
      `inngest_heartbeat` assertions at `cat-deploy-state.test.sh:39-66`. Run:
      `bash apps/web-platform/infra/cat-deploy-state.test.sh` — exits 0, all asserts pass.
- [ ] **AC4 — No gate-logic change.** `git diff` shows zero edits to
      `web-platform-release.yml` and zero edits to the `inngest-heartbeat.{service,timer}`
      heredocs in `inngest-bootstrap.sh` (this plan does NOT touch the unit; it fixes
      only the reporter). Grep-verify: `git diff --name-only` contains
      `cat-deploy-state.sh` + `cat-deploy-state.test.sh` and NOT `inngest-bootstrap.sh`
      or `web-platform-release.yml`.
- [ ] **AC5 — Full infra test suite green.** The owning suite passes:
      `bash apps/web-platform/infra/cat-deploy-state.test.sh` AND any harness that
      exercises the reporter (confirm the runner in Phase 0 via `ls
      apps/web-platform/infra/*.test.sh`; do not assume a framework).
- [ ] **AC6 — PR body uses `Ref #4896`, not `Closes #4896`.** Per
      `ops-remediation`/`ops-only-prod-write` convention: the issue is closed in a
      post-merge step after recovery is re-confirmed, not auto-closed at merge.

### Post-merge (operator / automated)

- [ ] **AC7 — Re-confirm recovery post-merge.** After this PR's own
      `web-platform-release.yml` run completes, `/health` reports this PR's `build_sha`
      and `version`. Automatable via the deploy-status webhook + `/health` curl (no SSH).
      Automation: feasible (curl + jq).
- [ ] **AC8 — Volume-pressure check (no-SSH).** Read the deploy-status JSON
      `journald_storage.root_avail` and (if present) the latest
      `scheduled-workspace-gc` Sentry `freeMb`/`freedMb` trend to confirm the shared
      volume is not re-pressured. If pressured, fire the GC via
      `/soleur:trigger-cron cron/workspace-gc.manual-trigger` (the no-SSH reclaim
      lever — `cron-workspace-gc` is in the manifest at `cron-manifest.ts:60` with a
      derived manual-trigger event). Automation: feasible (deploy-status webhook +
      trigger-cron skill). NOT operator-SSH.
- [ ] **AC9 — Close #4896 with corrected RCA.** `gh issue close 4896` with a comment:
      actual cause = `.cron` mkdir ENOSPC under `set -e` (not a broken heartbeat unit),
      fixed by #4895; `inngest_heartbeat: inactive` was a oneshot-misreport red herring,
      now corrected by this PR; capacity isolation deferred to #4891. Automation:
      feasible (`gh issue close`).

## Implementation Phases

### Phase 0 — Preconditions & recovery confirmation (read-only, no prod write)

1. Confirm the deploy queue recovered:
   `gh run list --workflow=web-platform-release.yml --limit 12 --json conclusion,createdAt,headSha`
   — assert the first run after #4895's merge commit `b06de5b6` is `success` and the
   three issue-cited SHAs (`1998af5f`, `251b80ea`, `4d1e1cb8`) are the failures.
2. Confirm prod is current: `curl -fsS --max-time 12 https://app.soleur.ai/health | jq .`
   — assert `version >= 0.102.0` and `status == "ok"`.
3. Identify the reporter test runner: `ls apps/web-platform/infra/*.test.sh` and read
   the head of `cat-deploy-state.test.sh` to confirm the `assert` harness shape (it is
   a bash assert helper, not a JS framework — do NOT prescribe bun/vitest here).
4. Re-read `cat-deploy-state.sh:19-26` (`service_status`) and `:102-134` (the field
   assembly) and `inngest-bootstrap.sh:216-245` (the oneshot `.service` + `.timer`
   heredocs) to confirm the timer unit name is exactly `inngest-heartbeat.timer`.

### Phase 1 — Add the durable timer-liveness field to the reporter (RED → GREEN)

**File: `apps/web-platform/infra/cat-deploy-state.test.sh`** (write the failing
assertions first, per `cq-write-failing-tests-before`):

- Mirror the existing 4 `inngest_heartbeat` assertions (lines 39-66) with parallel
  `inngest_heartbeat_timer` assertions across no_prior_deploy / OK / services-merge /
  corrupt_state. Each: `jq -e '.services.inngest_heartbeat_timer' >/dev/null`.

**File: `apps/web-platform/infra/cat-deploy-state.sh`:**

- Add `HEARTBEAT_TIMER_STATUS="$(service_status inngest-heartbeat.timer)"` next to the
  existing `HEARTBEAT_STATUS` read (line 102).
- Add `--arg hbt "$HEARTBEAT_TIMER_STATUS"` to the final `jq -nc` (after line 122) and
  emit `inngest_heartbeat_timer: $hbt` inside the `services` object (after line 129).
- Add an inline comment on the existing `inngest_heartbeat` field documenting that the
  oneshot `.service` reports `inactive` as its NORMAL steady state between 60s timer
  fires, and that `inngest_heartbeat_timer` (`active` on a healthy host) is the durable
  liveness signal — citing #4896 as the incident this prevents recurring.

Run `bash apps/web-platform/infra/cat-deploy-state.test.sh` → green.

### Phase 2 — Verify no unintended blast radius

- `git diff --name-only` MUST list exactly `cat-deploy-state.sh` +
  `cat-deploy-state.test.sh` (plus plan/spec/tasks docs). Confirm
  `inngest-bootstrap.sh` and `web-platform-release.yml` are untouched (AC4).
- Run the full infra reporter test surface identified in Phase 0 step 3 (AC5).

### Phase 3 — Ship + post-merge close

- PR body: `Ref #4896` (not `Closes`), summarizing the corrected RCA and pointing at
  #4895 as the deadlock fix and #4891 as deferred capacity isolation.
- After this PR's release run lands (AC7), run AC8 (volume-pressure check, fire GC via
  trigger-cron only if pressured), then AC9 (`gh issue close 4896` with the corrected RCA).

## Observability

```yaml
liveness_signal:
  what: "inngest-heartbeat.timer active-state + Better Stack 60s ping (betteruptime_heartbeat.inngest_prd)"
  cadence: "60s (OnUnitActiveSec=60s, inngest-bootstrap.sh:240); Better Stack grace 30s"
  alert_target: "Better Stack email on missed ping (free-tier, inngest.tf:13,149)"
  configured_in: "apps/web-platform/infra/inngest-bootstrap.sh (timer heredoc) + inngest.tf (betteruptime_heartbeat)"
error_reporting:
  destination: "deploy-status webhook JSON (cat-deploy-state.sh) surfaces services.inngest_heartbeat + new services.inngest_heartbeat_timer; Better Stack for the actual ping"
  fail_loud: "true — a dead timer reads inngest_heartbeat_timer != active in the deploy-status JSON AND Better Stack flips to missed/down"
failure_modes:
  - mode: "heartbeat timer dead (no 60s ping)"
    detection: "services.inngest_heartbeat_timer != 'active' in deploy-status JSON; Better Stack missed-ping email"
    alert_route: "Better Stack email; deploy-status webhook field for no-SSH triage"
  - mode: "oneshot .service stuck in 'failed' (curl errored, e.g. empty URL #4116 class)"
    detection: "services.inngest_heartbeat == 'failed' (distinct from the healthy 'inactive')"
    alert_route: "deploy-status JSON; bootstrap logs warn on heartbeat oneshot non-zero (inngest-bootstrap.sh:308)"
  - mode: "deploy gate failure (reason=unhandled)"
    detection: "web-platform-release.yml Verify-completion step: exit_code!=0; reason field carries detail"
    alert_route: "GitHub Actions run failure; deploy-status JSON reason field"
logs:
  where: "journald on the prod host (inngest-heartbeat.service ExecStart); Better Stack Logs via vector.service; deploy-status webhook for read-only no-SSH tail"
  retention: "journald persistent (#4792); Better Stack per plan tier"
discoverability_test:
  command: "curl -fsS --max-time 12 https://deploy.soleur.ai/hooks/deploy-status -H 'X-Signature-256: sha256=<hmac>' -H 'CF-Access-Client-Id: <id>' -H 'CF-Access-Client-Secret: <secret>' | jq '.services.inngest_heartbeat_timer'"
  expected_output: "\"active\" on a healthy host (the oneshot .service may read \"inactive\" — that is healthy steady state)"
```

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Pure infra/observability change to a read-only no-SSH deploy-status
reporter (`cat-deploy-state.sh`) + its bash test. No runtime code, no schema, no
secrets, no new infrastructure surface (the `inngest-heartbeat.timer` already exists;
we only read its state). No new systemd unit, no Terraform resource, no DNS/cert/cron.
The change makes an existing healthy unit's status legible instead of misleading.
Blast radius is bounded to the JSON shape of the deploy-status endpoint, which is
consumed by the release workflow's verify steps (which key on `exit_code`/`reason`,
not the heartbeat fields) and by operators doing no-SSH triage.

No Product/UX surface (no file under `components/**`, `app/**/page.tsx`, or any
UI-surface path). Product/UX Gate: NONE.

## Infrastructure (IaC)

Skipped — this plan introduces NO new infrastructure. It edits a read-only host-side
reporter script (`cat-deploy-state.sh`) that already ships in the deploy image and is
invoked by the existing `/hooks/deploy-status` webhook. No new systemd unit, secret,
vendor, DNS record, TLS cert, firewall rule, or persistent process. The
`inngest-heartbeat.timer` whose state we read is already provisioned by
`inngest-bootstrap.sh`. The deferred dedicated-volume work (a real IaC change — new
`hcloud_volume` + attachment + mount) lives in #4891, explicitly out of scope here.

## Open Code-Review Overlap

None — no open `code-review`-labeled issue touches `cat-deploy-state.sh` or
`cat-deploy-state.test.sh` (verified at plan time; re-run the `gh issue list --label
code-review` + per-path `jq contains` check at Step 1.7.5 once Files-to-Edit is frozen,
which it now is: the two files above).

## Non-Goals / Out of Scope

- **Re-litigating #4895's revert.** The `.cron` deadlock is already fixed and merged;
  this plan does not re-touch `ci-deploy.sh`'s `CRON_WORKSPACE_ROOT` or the mkdir.
- **Dedicated cron-clone volume / capacity isolation.** Deferred to #4891 (open). A
  separate Terraform planning cycle.
- **`journald_storage.persistent: false`.** Tracked under #4792; orthogonal to the
  heartbeat misreport. The incident JSON showed `root_avail: 54G` (root disk fine).
- **Changing the deploy-completion gate logic** (`web-platform-release.yml`). The gate
  correctly keys on `exit_code`/`reason`; no change needed.
- **Modifying the `inngest-heartbeat` systemd unit/timer/script.** They are healthy;
  the bug is in how their state is *reported*, not in the units.

## Alternative Approaches Considered

| Approach | Decision | Rationale |
|---|---|---|
| Close #4896 as already-fixed (no PR), since #4895 resolved the deadlock | Rejected (partial) | #4895 fixed the deploy deadlock but left the latent oneshot-misreport that mis-framed the incident. Closing without fixing the misreport guarantees the next deploy incident is mis-diagnosed the same way. We fix the reporter, THEN close. |
| Add `RemainAfterExit=yes` to `inngest-heartbeat.service` so `is-active` reads `active` | Rejected | That changes a healthy unit's semantics on the prod host (a systemd-unit edit + redeploy, larger blast radius) to paper over a reporter that should simply read the timer. The timer IS the canonical liveness signal; report it. |
| Replace the `inngest_heartbeat` (.service) field entirely with the timer field | Rejected | The `.service` field still distinguishes `failed` (curl errored, the #4116 class) from healthy `inactive`. Keep both: `.timer` for liveness, `.service` for last-fire fault detection. |
| Change the deploy gate to also assert `inngest_heartbeat == active` | Rejected (would have re-broken deploys) | A oneshot's healthy state is `inactive`; gating on `active` would fail every healthy deploy. This is precisely the wrong fix the issue's framing nudges toward — explicitly avoided. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The
  section above is filled with threshold `aggregate pattern`.
- **The issue's own framing is the trap.** #4896 asserts "restore the broken heartbeat
  service" and names `inngest_heartbeat: inactive` as the root signal. Both are wrong:
  the unit was never broken, and `inactive` is healthy for a oneshot. Any implementer
  who takes the issue at face value will either (a) "fix" a healthy unit, or (b) add an
  `is-active == active` gate that re-breaks every deploy. The plan's reframe (read the
  timer, keep both fields, touch no unit) is load-bearing — do not regress to the
  issue's literal ask.
- **`Closes #4896` would false-resolve.** This is `ops-only-prod-write`: the issue is
  closed post-merge after recovery is re-confirmed (AC9), so the PR body must say
  `Ref #4896`. `Closes` auto-closes at merge before the post-merge confirmation.
- **Do not assume the test runner.** `cat-deploy-state.test.sh` is a self-contained
  bash `assert`-helper script, NOT bun/vitest. Run it directly with `bash`; do not
  prescribe `bun test` (the package's runner is vitest for `.test.ts`, but `.test.sh`
  infra scripts run standalone).
- **`service_status` returns empty/`unknown` off-host.** In the test + non-systemd
  contexts the reporter's `service_status` yields `"unknown"` or empty; the new field
  assertions check *presence* (`jq -e '.services.inngest_heartbeat_timer'`), not a
  specific value — mirroring the existing `inngest_heartbeat` assertions which never
  pin the word.
