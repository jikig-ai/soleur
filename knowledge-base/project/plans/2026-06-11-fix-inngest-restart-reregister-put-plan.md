---
title: "fix(infra): inngest restart arm must PUT /api/inngest to force SDK re-registration"
issue: 5159
branch: feat-one-shot-inngest-restart-reregister-5159
type: ops-remediation
classification: deploy-pipeline-fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-06-11
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: the only `systemctl restart` references in this plan describe the
     EXISTING ci-deploy.sh / inngest-bootstrap.sh restart behavior being modified, not a new
     manual provisioning step. The script reaches the prod host via the existing
     terraform_data.deploy_pipeline_fix sha256 bridge (apply-deploy-pipeline-fix.yml auto-apply
     on merge) — fully routed through Terraform, documented in the ## Infrastructure (IaC) section.
     No new server, secret, vendor, or persistent process is introduced. -->

# fix(infra): inngest restart de-plans all crons until app-side re-registration

🐛 **Bug** · Production incident (crons de-planned twice on 2026-06-11) · deploy-pipeline-fix

## Overview

`ci-deploy.sh`'s `restart` action restarts `inngest-server.service` and then runs `verify_inngest_health` (which gates on `/health` at `127.0.0.1:8288` **and** on `/v1/functions` listing ≥1 cron-triggered function). The restart leaves the Inngest function registry **empty until an app-side re-registration occurs**. Recovery is **push-driven** (the web-platform SDK `PUT /api/inngest` at container boot, or a manual `PUT`), **not poll-driven** as #5145 assumed. On 2026-06-11, `--poll-interval 60` did not repopulate cron plans across 5+ consecutive poll cycles on two independent restarts — the full widened 120s cron budget elapsed with `"inngest_crons": {}`. The registry only repopulated when a `curl -X PUT https://app.soleur.ai/api/inngest` was fired manually (09:14:51) or when the concurrent Web Platform Release restarted the app container (re-registration at boot).

**Root cause (re-sync asymmetry):** after the inngest-server service restarts, the inngest-server does **not** self-initiate a function-manifest sync. Function discovery is push-bound — the web-platform SDK must `PUT /api/inngest` to (re-)register its manifest, which re-plans cron triggers at the substrate. The server's `--poll-interval 60`/`--sdk-url` only polls the SDK's *serve* endpoint; it does not, in the post-restart window, reliably re-plan within the verify budget. No retry budget can pass when recovery requires an external push that nothing fires.

**Fix:** fire a loopback `PUT /api/inngest` against the web-platform SDK (`127.0.0.1:3000`) **inside `verify_inngest_health`'s cron-plan loop**, retried each iteration until the registry shows a cron trigger. The PUT is fire-and-forget (`|| true`); the cron-plan loop remains the authoritative gate. This converts the loop from passive-poll to **active push-and-poll**: each iteration re-fires the registration, so a transient web-platform `:3000`-not-ready window (concurrent release, container mid-restart in the deploy-inngest arm) self-heals on the next iteration instead of collapsing to the pre-fix slow-resync behavior. This forces the re-registration that previously required an external container restart, collapsing the slow-resync race the #5145 budget was widened to tolerate.

> **Design decision (from spec-flow P1):** an early draft fired the PUT **once, before** the loop. That is correct in the restart arm (web-platform `:3000` is untouched and up) but races `:3000` readiness in the **deploy-inngest arm** — `verify_inngest_health`'s own header (`ci-deploy.sh:208`, `:876`) documents "the immediate post-restart SDK sync can RACE the web-platform container." A one-shot PUT that hits a not-yet-ready `:3000` returns connection-refused, `|| true` swallows it, and the loop waits out the full 120s budget anyway — reproducing the very failure the fix targets. Firing the PUT **inside** the loop (before each `/v1/functions` poll) is strictly better and is the chosen design.

**Empirical validation of the PUT contract:** the issue's own incident evidence proves `PUT /api/inngest` re-plans crons in production — at 09:14:51 the manual PUT returned `{"message":"Successfully registered","modified":true}` and the cron monitors began checking in normally afterward. The PUT is the missing step, confirmed live.

**Why this matters now:** `ci-deploy.sh` is a `deploy_pipeline_fix` trigger file — merging this PR auto-fires `apply-deploy-pipeline-fix.yml`, which `terraform apply -target=terraform_data.deploy_pipeline_fix` delivers the new script to the host (HTTPS, no SSH) and verifies the per-file landed contract. This was a live production incident, so the PR must carry a PIR per the ship Incident-PIR gate.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Reality (verified on this branch) | Plan response |
| --- | --- | --- |
| Restart arm runs service restart + `verify_inngest_health` | Confirmed: `ci-deploy.sh:371` restart, `:378` verify call | No arm-level edit — the PUT now lives INSIDE `verify_inngest_health` (both arms call it) |
| `verify_inngest_health` gates on `/health` (8288) AND cron-plan `/v1/functions` | Confirmed: `ci-deploy.sh:204–258`; `/health` loop 219–234, cron loop 244–257 | PUT goes INSIDE the cron-plan loop (after `:244` `for`, before the `/v1/functions` curl at `:246`), retried each iteration. Uses `--max-time 10 -X PUT` so it does NOT match the `--max-time 5` form the `VERIFY_FN_MAXTIME==2` pin counts |
| Fix PUTs `http://127.0.0.1:3000/api/inngest` | Confirmed: web-platform container binds `-p 0.0.0.0:3000:3000`; inngest-server polls `--sdk-url http://127.0.0.1:3000/api/inngest` (`inngest-bootstrap.sh:162`) | PUT target correct; loopback `:3000` is the SDK serve endpoint |
| `PUT /api/inngest` triggers re-registration | Confirmed: `route.ts:84` `export const { GET, POST, PUT } = serve(...)`; PUT is the SDK sync/register endpoint; live evidence at 09:14:51 returned `modified:true` | No auth header needed on the loopback caller (SDK uses its own signing key outbound); `/api/inngest` is in `PUBLIC_PATHS` (#4017) so no 307→/login. **Caveat:** `curl -sf` (no `-L`) treats a 307 as success with empty body — a `PUBLIC_PATHS` regression would silently no-op the PUT; the cron loop is the backstop and Phase 0 greps membership |
| Second site: `deploy inngest` arm post-bootstrap | Confirmed: bootstrap runs `ci-deploy.sh:851–852`; verify at `:882–885` | No separate edit — the deploy-inngest arm calls the same `verify_inngest_health`, so the in-loop PUT covers it (and self-heals the `:3000` race in this arm) |
| "consider the same PUT in `inngest-bootstrap.sh` post-restart" | `inngest-bootstrap.sh:303` restarts the service; NO post-restart verify there. The bootstrap may not have the web-platform `:3000` reachability guarantee ci-deploy.sh has. | **Scope OUT** of bootstrap (see Non-Goals). The two ci-deploy.sh arms are load-bearing; the deploy-inngest ci-deploy.sh arm already covers the bootstrap path (verify runs after bootstrap returns). |
| H9 runbook "restart web-platform container afterwards" becomes unnecessary | Confirmed: `cloud-scheduled-tasks.md:417–423` (automated backstop) + `:429` (manual fallback step 3) | Revise both to note the restart arm now self-registers |
| `deploy-status-debugging.md` `inngest_health_failed` row remediation needs revision | Confirmed: `deploy-status-debugging.md:65` ("Sentry green = slow-resync, re-dispatch") | Revise: re-dispatch alone cannot recover pre-fix; post-fix the PUT forces immediate resync |
| Ref #5145 / PR #5146 | #5145 CLOSED; #5146 merged to main (commit `c2146e7a5`) | Premise holds — necessary budget fix, insufficient without the PUT |

## User-Brand Impact

**If this lands broken, the user experiences:** every standalone inngest restart silently de-plans ALL production crons (drift guards, KB template health, OAuth probes, community monitors, release digests) until something external re-registers the app. On 2026-06-11 two windows (~07:11→~07:25 and 09:04→09:15) ran with zero scheduled work firing — invisible to the operator unless they happen to read the Sentry cron-monitor miss alerts.

**If this leaks, the user's workflow is exposed via:** N/A — no data leak vector. This is an availability/reliability defect, not a confidentiality one. The PUT carries no body and no credentials; it is a loopback registration trigger only.

**Brand-survival threshold:** `single-user incident`. A de-planned cron substrate means the one operator's automated brand presence (releases, community digests, drift remediation) silently stops; a single missed window is a brand-survival event for a solo-operator product. CPO sign-off required at plan time; `user-impact-reviewer` invoked at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — In-loop PUT wiring.** `verify_inngest_health`'s cron-plan loop fires `curl -sf --max-time 10 -X PUT http://127.0.0.1:3000/api/inngest || true` once per iteration, BEFORE the `/v1/functions` poll (`ci-deploy.sh:246`). Verify: `awk` over the function body (`/^verify_inngest_health\(\)/` to its closing `}`) shows the PUT line inside the `for i in $(seq 1 "$cron_max_attempts")` loop and ordered before the `/v1/functions` curl.
- [ ] **AC2 — Both arms covered by one edit.** Because both the restart arm (`:378`) and the deploy-inngest arm (`:883`) call `verify_inngest_health` with zero args, the single in-loop PUT covers both. Verify: no arm-level PUT exists (`grep -c 'api/inngest' apps/web-platform/infra/ci-deploy.sh` counts only the in-function occurrence(s), not arm-level duplicates).
- [ ] **AC3 — `VERIFY_FN_MAXTIME==2` pin still holds.** The `verify_inngest_health` function body still contains exactly two `curl -sf --max-time 5` lines (the #5145 pin). The new PUT uses `--max-time 10 -X PUT`, which does NOT match `--max-time 5`. Verify: `bash apps/web-platform/infra/ci-deploy.test.sh` passes its `VERIFY_FN_MAXTIME` assertion.
- [ ] **AC4 — PUT count.** Exactly **1** `-X PUT http://127.0.0.1:3000/api/inngest` line exists in `ci-deploy.sh` (inside the cron loop). Verify: `grep -cE 'curl -sf --max-time 10 -X PUT http://127\.0\.0\.1:3000/api/inngest' apps/web-platform/infra/ci-deploy.sh` returns `1`.
- [ ] **AC5 — Test: restart arm still passes the existing 5 restart-arm cases.** `success`/`0`, `component_not_restartable`, `inngest_restart_failed` (MOCK_SYSTEMCTL_FAIL — note this `exit 1`s before `verify_inngest_health`, so the PUT never fires on a failed restart), `inngest_health_failed` (MOCK_CURL_INNGEST_HEALTH_FAIL), and cron-deplaned `inngest_health_failed` (MOCK_CURL_INNGEST_FUNCTIONS_NOCRON) all still assert correctly. Verify: `bash apps/web-platform/infra/ci-deploy.test.sh` exits 0.
- [ ] **AC6 — Test: PUT mock case-arm + failure tolerance.** Add an explicit `*":3000/api/inngest"*` case to the `curl` mock in `ci-deploy.test.sh` (placed before `esac` — note the current mock falls through to an unconditional `exit 0` fallback that ignores `MOCK_CURL_*`, so without the explicit arm a PUT-fail cannot be simulated). The arm honors `MOCK_CURL_INNGEST_PUT_FAIL=1` (returns non-zero/empty). Add a test proving a failed PUT does **not** abort the deploy (`|| true`): the loop still reaches the `/v1/functions` poll and reports `inngest_health_failed` only if the cron poll fails, never a PUT-specific reason. Verify: asserts `success`/`0` when PUT fails but the cron poll later succeeds. **Coverage honesty note in the test comment:** the mock returns a cron-planned `/v1/functions` independent of whether the PUT fired, so these tests prove *wiring + fail-tolerance*, NOT *efficacy* — efficacy is only provable live (AC15).
- [ ] **AC7 — Test: wiring-order + restart-fail-skip assertions.** Add grep/awk-based assertions to `ci-deploy.test.sh`: (a) the PUT line number falls within the cron-plan loop AND before the `/v1/functions` curl; (b) `MOCK_SYSTEMCTL_FAIL=1` yields `inngest_restart_failed` and the PUT mock is never invoked (the restart-fail path `exit 1`s before `verify_inngest_health`). Verify: both assertions pass.
- [ ] **AC8 — #5145 drift guard must COUNT the PUT and the client window must widen (BLOCKER — corrected at plan-review).** The in-loop PUT is an **additive, sequential** `curl -sf --max-time 10` per cron iteration (bash runs PUT → `/v1/functions` poll → `sleep interval` in sequence; the PUT does NOT overlap the sleep). When `:3000` is listening-but-hung (the deploy-inngest arm's likely failure mode), every PUT consumes its full `--max-time`. **Corrected math** (current values: `DG_HEALTH=10`, `DG_CRON=40`, `DG_INTERVAL=3`, `DG_STOP=TimeoutStopSec=180` from `inngest-bootstrap.sh:178` — NOT 30, which is the vector unit):
  - Pre-fix `DG_RIGHT = (10+40)×(3+5) + 180 + 60 = 640s`; `DG_LEFT = 140×5 = 700s` → real slack only **60s** (my earlier "210s/290s" was wrong — `DG_STOP` is 180, not 30).
  - Post-fix server worst case, PUT counted on the cron loop only: `health 10×(3+5) + cron 40×(3+5+10) + 180 + 60 = 80 + 720 + 240 = 1040s` >> 700s. **The guard MUST fail as currently configured — and that failure is correct.**
  - **Required changes in this PR (not deferred):**
    1. Update the drift-guard formula (`ci-deploy.test.sh:2139`) to split the per-loop terms and count the PUT on the cron loop, extracting the PUT `--max-time` **by shape** (consistent with the guard's existing by-shape extraction, `:2083`): `DG_RIGHT = DG_HEALTH×(DG_INTERVAL+5) + DG_CRON×(DG_INTERVAL+5+DG_PUT_MAXTIME) + DG_STOP + 60`, with `DG_PUT_MAXTIME=$(grep -oE -- '-X PUT[^|]*--max-time [0-9]+' ...)` or equivalent. Update the comment block (`:2086–2094`) to enumerate the PUT tail.
    2. Widen the restart workflow client window (`restart-inngest-server.yml:74–75`) so `DG_LEFT > DG_RIGHT` holds with the PUT counted: set `MAX_POLLS=240` (× `POLL_INTERVAL=5` = `1200s` > `1040s`, ~160s headroom). The `restart-inngest-server.yml` `timeout-minutes` must also cover 1200s (≥ 25 min).
  - Verify: `bash apps/web-platform/infra/ci-deploy.test.sh` drift-guard assertion prints `PASS` **with the PUT counted** and `1200 > 1040`. A green guard that ignores the PUT (current state) is a false-green and is rejected.
- [ ] **AC8b — Bound the hung-`:3000` worst case (consider shorter PUT timeout).** Evaluate dropping the PUT `--max-time` from 10 to a smaller value (e.g. 5, matching the readiness vantage of the existing `/health` probes) to halve the worst-case PUT tail (`40×5=200s` saved) and reduce the required client-window widening. Document the chosen `--max-time` and its budget contribution. (Deepen-plan Phase 4.4 precedent-diff: compare against the existing `--max-time 5` probe convention in `verify_inngest_health`.)
- [ ] **AC9 — H9 runbook revised.** In `cloud-scheduled-tasks.md`, the automated-backstop block (`docker restart soleur-web-platform` at `:422`) and the manual-fallback step 3 (`:429`) no longer instruct restarting the web-platform container as a required step; replaced with a note that the restart arm now self-registers via the in-loop PUT (cite #5159). The revised runbook keeps the **no-SSH `/hooks/deploy-status` path primary** (`hr-no-ssh-fallback-in-runbooks`) — the "Manual fallback (SSH required)" block must not be the documented first remediation. Verify: human-readable check that the backstop block no longer lists the container restart as a follow-up; the no-SSH path leads.
- [ ] **AC10 — Reason-taxonomy doc revised.** `deploy-status-debugging.md:65` (`inngest_health_failed` row) remediation updated: re-dispatch alone cannot recover a de-planned registry; post-#5159 the restart arm forces the SDK PUT so the slow-resync race is eliminated. Verify: the row's remediation text references #5159 and the PUT-forces-resync behavior.
- [ ] **AC11 — `## Observability` block present and honest.** The plan/PR `## Observability` section's `discoverability_test.command` contains no `ssh `. Verify: the command is the `/hooks/deploy-status` GET + Sentry monitors API query documented below (both no-SSH).
- [ ] **AC12 — PIR on the branch.** A PIR exists at `knowledge-base/engineering/operations/post-mortems/inngest-restart-cron-deplan-2026-06-11-postmortem.md`, with frontmatter carrying `brand_survival_threshold` + GDPR Art. 33/34 fields, and an `## Action Items & Follow-ups` table whose every row carries a filed `#NNNN` issue (or the single permitted "No action items" sentence). Verify: path matches `post-mortems/.+-postmortem\.md$`; ship Incident-PIR gate passes.
- [ ] **AC13 — Issue link uses `Ref`, not `Closes`.** PR body uses `Ref #5159` (not `Closes #5159`) — the drift is not resolved until the post-merge `terraform apply` runs. Verify: PR body grep.

### Post-merge (operator)

- [ ] **AC14 — Auto-apply landed.** Two landing paths: (a) `ci-deploy.sh` reaches the host via `apply-deploy-pipeline-fix.yml` (paths filter includes `ci-deploy.sh`) → `terraform apply -target=terraform_data.deploy_pipeline_fix` → post-apply gate `/hooks/infra-config-status` (`exit_code==0 && files_failed==0 && files_written==files_total`); (b) the `restart-inngest-server.yml` workflow-window widening lands at merge directly (a workflow file is read from the merged ref on next dispatch — no terraform apply). Automation: workflow verify steps + `/soleur:ship` Phase 5.5 Deploy Pipeline Fix Drift Gate. Do NOT set `[skip-deploy-fix-apply]`.
- [ ] **AC15 — Live re-dispatch proves the fix.** After apply lands, dispatch `restart-inngest-server.yml` once and confirm `reason=success` (not `inngest_health_failed`) via `/hooks/deploy-status`, AND confirm the Sentry cron monitors (org `jikigai`) check in within the next hour without a manual PUT. Automation: `gh workflow run restart-inngest-server.yml` + `/hooks/deploy-status` GET + Sentry monitors API query (both no-SSH); deterministic verdict: `reason==success`. Then `gh issue close 5159`.

## Implementation Phases

> Phase order is load-bearing: the contract-changing edits (ci-deploy.sh arms) come first, then tests, then docs, then PIR. All land in one atomic PR.

### Phase 0 — Preconditions (verify, no code)
- Confirm `/api/inngest` is still in `PUBLIC_PATHS` (`apps/web-platform/lib/routes.ts:16` confirmed) so the loopback PUT is not 307→/login. Grep: `git grep -n '/api/inngest' apps/web-platform/lib/routes.ts apps/web-platform/middleware.ts`.
- Confirm `route.ts:84` still exports `PUT` from `serve(...)`.
- Re-read the #5145 drift-guard block (`ci-deploy.test.sh:2080–2151`); the corrected current numbers are `DG_RIGHT=640s` (`DG_STOP=180`) vs `DG_LEFT=700s` (60s slack). The in-loop PUT pushes server worst case to ~1040s — Phase 2 widens the client window per AC8.
- Confirm the bootstrap-context `:3000` reachability claim used to scope OUT the `inngest-bootstrap.sh:303` PUT (Non-Goals item 1): the deploy-inngest arm's `verify_inngest_health` (which now fires the in-loop PUT) runs AFTER bootstrap returns, in the deploy-user context where `:3000` loopback is established — verify no window exists where neither path fires the PUT.

### Phase 1 — In-loop PUT in `verify_inngest_health` (RED→GREEN)
- Add failing tests in `ci-deploy.test.sh` first: in-loop wiring (PUT inside the cron loop, before the `/v1/functions` curl) + PUT-fail tolerance case (`MOCK_CURL_INNGEST_PUT_FAIL`) + restart-fail-skip (`MOCK_SYSTEMCTL_FAIL` → PUT never invoked).
- Add the PUT line **inside `verify_inngest_health`'s cron-plan loop** (`ci-deploy.sh:244–254`), as the first statement after the `for i in $(seq 1 "$cron_max_attempts")`, before the `/v1/functions` curl at `:246`:
  ```bash
  # #5159: active push-and-poll — re-register on EACH iteration (the inngest-server
  # cannot self-sync post-restart; only an SDK PUT re-plans crons). Self-heals a
  # transient :3000-not-ready window. `|| true` MANDATORY under set -e (curl exit 7
  # else aborts verify). --max-time bounds a hung :3000 (counted in the #5145 drift
  # guard — see ci-deploy.test.sh DG_RIGHT). NB: -sf (no -L) treats 307 as success.
  curl -sf --max-time 10 -X PUT http://127.0.0.1:3000/api/inngest || true
  ```

### Phase 2 — Test harness completeness
- Add the explicit `*":3000/api/inngest"*` mock case to the `curl` mock in `ci-deploy.test.sh` (before `esac` — the current post-`esac` fallback returns success unconditionally and ignores `MOCK_CURL_*`), honoring `MOCK_CURL_INNGEST_PUT_FAIL` (returns non-zero/empty when set).
- Add the PUT-count assertion (`==1`), the in-loop wiring assertion, and the restart-fail-skip assertion (AC7), with the coverage-honesty comment (AC6).
- Run `bash apps/web-platform/infra/ci-deploy.test.sh` — all green; confirm `VERIFY_FN_MAXTIME==2` and the #5145 drift guard `PASS`; apply the `DG_RIGHT` model-honesty note (AC8).

### Phase 3 — Runbook + reason-taxonomy doc revisions
- `cloud-scheduled-tasks.md`: revise the H9 automated-backstop block (`:417–423`) and manual-fallback step 3 (`:429`) — the `docker restart soleur-web-platform` follow-up is no longer required; the restart arm self-registers. Cite #5159.
- `deploy-status-debugging.md:65`: revise the `inngest_health_failed` remediation — re-dispatch alone cannot recover; the PUT forces immediate resync post-#5159.

### Phase 4 — PIR authoring
- Author `inngest-restart-cron-deplan-2026-06-11-postmortem.md` from `plugins/soleur/skills/incident/templates/pir.md` (or via `/soleur:incident`). Timeline: 07:11→07:25 and 09:04→09:15 de-plan windows; root cause = re-sync asymmetry (push-driven recovery defeats poll-driven retry); resolution = restart-arm PUT. `## Action Items & Follow-ups`: this PR is the fix; any residual (e.g., bootstrap-path coverage) gets a filed `#NNNN` issue, else the "No action items" sentence.

### Phase 5 — Post-merge (operator, automated where feasible)
- Merge → `apply-deploy-pipeline-fix.yml` auto-applies (AC14). `/soleur:ship` Phase 5.5 covers the drift gate.
- `gh workflow run restart-inngest-server.yml` → poll `/hooks/deploy-status` for `reason=success` → confirm Sentry monitors check in (AC15) → `gh issue close 5159`.

## Non-Goals / Out of Scope

- **PUT inside `inngest-bootstrap.sh` post-restart (`:303`).** Scoped out: the deploy-inngest arm in ci-deploy.sh already runs `verify_inngest_health` after the bootstrap returns, and the PUT in that arm (Phase 2) covers the deploy path. The bootstrap executes in a context where web-platform `:3000` reachability is not guaranteed the same way (it runs as the inngest restart unit, not the deploy user with the established loopback vantage). Adding it there is redundant with the ci-deploy.sh deploy-inngest-arm PUT and untested (inngest.test.sh is not CI-wired). **Deferral tracking:** if a future incident shows the deploy-inngest-arm PUT races the bootstrap restart, file a follow-up issue. (Tracking issue to be created — see Domain Review.)
- **Changing `--poll-interval` / `--sdk-url`.** The poll mechanism stays; the PUT is the deterministic forcing function. Out of scope.
- **Widening the #5145 cron budget further.** The budget is correct; the PUT removes the need to wait out the slow-resync race.

## Risks & Mitigations

- **Risk: PUT adds latency that blows the #5145 client/server budget (CONFIRMED at plan-review — P0).** The in-loop PUT is sequential and additive; counted, the server worst case rises from 640s to ~1040s, exceeding the 700s client window. Mitigation: AC8 widens the client window to 1200s AND updates the drift-guard formula to count the PUT by shape; AC8b evaluates a shorter PUT `--max-time` to shrink the worst case. This is the load-bearing finding — the guard must fail-then-be-fixed, not stay false-green.
- **Risk: PUT under `set -e` aborts the deploy on transient SDK unavailability.** Mitigation: `|| true` + `--max-time 10`; the cron-plan loop is the authoritative gate, so a failed PUT degrades gracefully to the pre-fix poll behavior (AC6).
- **Risk: `/api/inngest` falls out of `PUBLIC_PATHS` → 307→/login → PUT no-ops.** Mitigation: Phase 0 precondition grep + `middleware.test.ts` membership assertion already guards this (#4017).
- **Risk: PUT mock missing in ci-deploy.test.sh → many unrelated tests go red.** Mitigation: explicit mock case-arm before `esac` (Phase 3); baseline origin/main in isolation if cascade observed (learning 2026-06-03).
- **Risk: new command not in mock PATH aborts under `set -euo pipefail`.** Mitigation: `curl` is already mocked; the PUT reuses it.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron-monitor check-ins for all production inngest crons (drift guard, KB template health, OAuth probe, community monitor) resume within one poll window after any inngest restart"
  cadence: "per-cron schedule (hourly/daily); restart recovery verified within 1h"
  alert_target: "Sentry cron monitors (org jikigai), infra/sentry/cron-monitors.tf"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf"
error_reporting:
  destination: "ci-deploy.sh final_write_state -> /var/lock/ci-deploy.state -> cat-deploy-state.sh -> /hooks/deploy-status (HMAC GET); journald -> Vector -> Better Stack Logs"
  fail_loud: "reason=inngest_health_failed surfaced via /hooks/deploy-status JSON + restart-inngest-server.yml ::error:: GHA annotation; PUT failure never masks the cron-plan gate (|| true)"
failure_modes:
  - mode: "PUT fails (SDK transiently down) but cron loop later succeeds"
    detection: "reason=success in /hooks/deploy-status (graceful degradation to poll path)"
    alert_route: "none needed — non-fatal"
  - mode: "PUT succeeds but registry still empty after cron budget (true H9b)"
    detection: "reason=inngest_health_failed + Sentry monitors missing check-ins"
    alert_route: "Sentry cron-monitor miss alerts + deploy-status JSON"
  - mode: "restart-arm regression de-plans crons again"
    detection: "Sentry cron monitors stop checking in post-restart"
    alert_route: "Sentry monitor miss alert -> H9 runbook"
  - mode: "client window exceeded while the in-loop PUT loop is still running (hung :3000)"
    detection: "restart-inngest-server.yml ::error:: 'did not complete within poll budget' with NO terminal reason in /hooks/deploy-status (server still looping)"
    alert_route: "GHA workflow failure annotation + /hooks/deploy-status shows reason=running past the floor — distinct from inngest_health_failed"
logs:
  where: "journald (LOG_TAG ci-deploy) -> Vector -> Better Stack; /hooks/deploy-status state JSON"
  retention: "Better Stack default retention; state file overwritten per deploy"
discoverability_test:
  command: "curl -s -H \"$DEPLOY_STATUS_HMAC_HEADER\" https://deploy.soleur.ai/hooks/deploy-status | jq '.reason' && curl -s -H \"Authorization: Bearer $SENTRY_TOKEN\" 'https://sentry.io/api/0/organizations/jikigai/monitors/?environment=production' | jq '[.[] | select(.status==\"active\")] | length'"
  expected_output: "reason == \"success\" after a restart-inngest-server.yml dispatch; cron monitors active count > 0 with recent check-ins (no manual PUT required)"
```

## Infrastructure (IaC)

This plan edits an already-provisioned host script (`ci-deploy.sh`); it introduces no new server, secret, vendor, or persistent process.

### Terraform changes
- No new `.tf` resources. The edit reaches the host via the **existing** `terraform_data.deploy_pipeline_fix` sha256-bridge (`apps/web-platform/infra/`), auto-applied by `.github/workflows/apply-deploy-pipeline-fix.yml` on merge (paths filter already includes `ci-deploy.sh`).

### Apply path
- **(b) cloud-init + idempotent bootstrap-bridge equivalent:** `terraform apply -target=terraform_data.deploy_pipeline_fix` delivers the new script via the `/hooks/infra-config` webhook (HTTPS, no SSH). Triggered automatically on merge; operator-authorized by the merge itself per `hr-menu-option-ack-not-prod-write-auth`. Blast radius: replaces `ci-deploy.sh` on the prod host; no service downtime (the script is invoked per-deploy, not a running daemon).

### Distinctness / drift safeguards
- `hcloud_server.web` carries `lifecycle.ignore_changes=[user_data]`, so the edit does NOT reach the host via re-provision — only via the deploy_pipeline_fix sha256 bridge. Post-apply verify is provisioner-layer: `/hooks/infra-config-status` asserts `exit_code==0 && files_failed==0 && files_written==files_total` (per-file landed contract), not an HTTP-200 proxy.

### Vendor-tier reality check
- N/A — no vendor resource created.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** carried forward (single-domain infra fix)
**Assessment:** Pure deploy-pipeline reliability fix in a `deploy_pipeline_fix` trigger file. Re-sync asymmetry root cause is well-understood (learning 2026-05-30). Shell discipline (`|| true`, `--max-time`, no `set +e` toggle inside functions), test-mock completeness, and the #5145 cross-file drift guard are the engineering risks — all enumerated in Risks & Mitigations and ACs. No product, legal, finance, or marketing implications.

**Deferral tracking:** Phase 2.5 / final-review must create a follow-up GitHub issue for the scoped-out bootstrap-path PUT (Non-Goals item 1), with re-evaluation criterion "if the deploy-inngest-arm PUT is observed racing the bootstrap restart" and milestone "Post-MVP / Later".

### Product/UX Gate
**Tier:** none — no UI surface in Files to Edit (all `.sh`, `.md`, `.test.sh`). Skipped.

### Sign-off
`brand_survival_threshold: single-user incident` → `requires_cpo_signoff: true`. CPO sign-off required at plan time before `/work`; `user-impact-reviewer` invoked at review time (handled by the review SKILL conditional-agent block).

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — add the loopback `PUT /api/inngest` INSIDE `verify_inngest_health`'s cron-plan loop (after `:244` `for`, before the `/v1/functions` curl at `:246`). One edit covers both arms (restart + deploy-inngest both call the function).
- `apps/web-platform/infra/ci-deploy.test.sh` — PUT mock case-arm (before `esac`), `MOCK_CURL_INNGEST_PUT_FAIL` tolerance test, restart-fail-skip test, PUT-count `==1` assertion, in-loop wiring assertion, coverage-honesty comment, AND **update the #5145 drift-guard formula (`:2139`) + comment (`:2086–2094`) to count the PUT `--max-time` by shape on the cron-loop term** (AC8). `VERIFY_FN_MAXTIME==2` stays green (PUT uses `--max-time 10`/`5`, not the pinned `--max-time 5` health/functions form — confirm whichever PUT value AC8b selects still avoids the pin: if AC8b picks `--max-time 5`, the `-X PUT` token still distinguishes it, but verify the `VERIFY_FN_MAXTIME` awk counts only the two non-PUT probes).
- `.github/workflows/restart-inngest-server.yml` — widen the client poll window: `MAX_POLLS=240` (× `POLL_INTERVAL=5` = 1200s > 1040s server worst case) and raise `timeout-minutes` to ≥25 (AC8). The `:5` header comment documenting the window-vs-server-budget contract must be updated.
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — revise H9 automated-backstop (`:417–423`) + manual-fallback step 3 (`:429`).
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — revise `inngest_health_failed` row (`:65`).

## Files to Create

- `knowledge-base/engineering/operations/post-mortems/inngest-restart-cron-deplan-2026-06-11-postmortem.md` — PIR (from `plugins/soleur/skills/incident/templates/pir.md`).

## Open Code-Review Overlap

None — no open `code-review`-labeled issue references `ci-deploy.sh`, `inngest-bootstrap.sh`, `verify_inngest_health`, `cloud-scheduled-tasks.md`, or `deploy-status-debugging.md`.

## Hypotheses

Network-outage / SSH-firewall checklist (plan Phase 1.4) is **not** applicable: although the issue mentions "timeout"/"health"/"restart", the defect is push-vs-poll re-registration logic, not an L3→L7 connectivity failure. No SSH/firewall hypothesis is in play (the loopback PUT and probes all run on the host itself). The single load-bearing hypothesis — "`PUT /api/inngest` re-plans cron triggers, not just re-registers definitions" — is already confirmed by the issue's live 09:14:51 evidence (`modified:true` + subsequent monitor check-ins).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- The PUT lives INSIDE `verify_inngest_health` (in the cron loop) but MUST use `--max-time 10 -X PUT` (not `--max-time 5`) so it never matches the #5145 `VERIFY_FN_MAXTIME==2` curl-count pin (which counts `curl -sf --max-time 5` lines in the function body).
- `curl -sf` without `-L` treats a 307 as success with an empty body — a `/api/inngest` `PUBLIC_PATHS` regression would make the PUT a silent no-op. The cron `/v1/functions` gate is the only backstop; Phase 0 greps `PUBLIC_PATHS` membership (#4017 / `middleware.test.ts`, which is NOT wired to `infra-validation.yml`).
- The in-loop PUT must stay fire-and-forget (`|| true`): it runs under the function's `set -e`, so dropping `|| true` would let a connection-refused (curl exit 7) abort `verify_inngest_health` before the gate, converting a recoverable slow-resync into a hard `unhandled` EXIT-trap failure. AC6 tests this.
- `inngest.test.sh` is NOT CI-wired (only `ci-deploy.test.sh` runs in `infra-validation.yml`) — do not rely on inngest.test.sh to catch a bootstrap-path regression.
- Use `Ref #5159`, not `Closes #5159` — this is an ops-remediation PR; the issue closes post-merge after `terraform apply` lands and the live re-dispatch proves recovery.
