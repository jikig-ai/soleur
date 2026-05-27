---
title: "feat(deploy): add inngest-server restart to deploy pipeline"
type: feat
date: 2026-05-27
issue: "#4538"
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat(deploy): add inngest-server restart to deploy pipeline

## Overview

Add a lightweight inngest-server restart capability to the deploy pipeline, closing the H9 runbook gap identified in PR #4531. The current deploy pipeline can only perform full inngest bootstrap deploys (image pull + binary install + systemd unit write). When inngest-server.service desyncs after rapid web-platform deploy churn (H9 hypothesis in `cloud-scheduled-tasks.md`), the only recovery path is SSH + manual `systemctl restart` -- a non-automatable barrier for a solo-founder product.

This feature adds three capabilities:
1. A `restart` action in `ci-deploy.sh` that accepts `restart inngest _ latest` -- restarts `inngest-server.service`, waits for health, verifies function registry is non-empty.
2. Post-deploy function registry sanity check in the `web-platform` handler -- after canary promotion, logs the Inngest function count (informational, non-blocking, no auto-restart).
3. A GitHub Actions workflow for standalone inngest restart via webhook dispatch.

## Problem Statement / Motivation

PR #4531 documented the gap after `scheduled-community-monitor` missed 2 consecutive daily fires following 15+ deploys in a 24h window (TR9 Phase 2). The H9 runbook in `cloud-scheduled-tasks.md` (lines 264-327) prescribes `sudo systemctl restart inngest-server.service` as the primary restore step, but this requires SSH access with admin IP allowlist -- exactly the kind of manual operator step `hr-all-infrastructure-provisioning-servers` and `hr-no-ssh-fallback-in-runbooks` prohibit.

The function-registry-count drift guard (`function-registry-count.test.ts`) catches registry drift at CI time (compile-time parity), but there is no runtime verification that the deployed Inngest server's function count matches the expected count after a web-platform deploy.

## Research Reconciliation -- Spec vs. Codebase

| Spec/Issue Claim | Codebase Reality | Plan Response |
|---|---|---|
| Issue says `deploy inngest restart latest` | ci-deploy.sh validates exactly 4 fields: `deploy <component> <image> <tag>` and validates image against `ALLOWED_IMAGES` map. `restart` would fail image validation. | Use a new top-level action `restart` instead of overloading `deploy`. Command becomes `restart inngest _ latest`. Requires widening the field-count + action validation in ci-deploy.sh. |
| Issue says "use count from function-registry-count.test.ts" | Test at `apps/web-platform/test/server/inngest/function-registry-count.test.ts:85` asserts `routeEntries.length` toBe `40`. | [Plan review: DHH + Code Simplicity agreed exact-count matching creates maintenance coupling and false positives] Use a floor check (`count >= 1`) instead of exact count. The real H9a signal is "zero functions registered" (full desync), not "39 vs 40" (legitimate removal). The CI-time test already enforces exact count; deploy-time verification should be a sanity check, not a mirror. |
| Issue says health check at `127.0.0.1:8288` | inngest-bootstrap.sh binds `0.0.0.0:8288` (line 147). ci-deploy.sh's web-platform handler uses `host.docker.internal:8288` for the container. From the host (where ci-deploy.sh runs), `127.0.0.1:8288` is reachable. | Use `127.0.0.1:8288` for the health check from ci-deploy.sh (confirmed reachable from host). |
| Issue says sudoers for `systemctl restart inngest-server.service` | Current sudoers (`deploy-inngest-bootstrap.sudoers`) only allows `inngest-bootstrap.sh` execution and `webhook` self-restart. No entry for `systemctl restart inngest-server.service`. | Add a new `Cmnd_Alias INNGEST_RESTART` to the sudoers file. This requires `terraform apply` to push the updated sudoers via infra-config-apply.sh. |

## Proposed Solution

### Architecture Decision: New `restart` action vs. overloading `deploy`

The current ci-deploy.sh validates exactly 4 fields (`deploy <component> <image> <tag>`) and checks `image` against `ALLOWED_IMAGES`. Two approaches:

**Option A: New action `restart` with 4 fields** -- `restart inngest _ latest`
- Adds a new `ACTION` branch (`restart` alongside `deploy`)
- The `image` field is unused (placeholder `_`), `tag` is unused (`latest` as sentinel)
- Clean separation: `deploy` = full image-pull pipeline, `restart` = lightweight systemctl restart
- Validation: only `inngest` component allowed for `restart` (web-platform restart is `docker restart`, different pathway)

**Option B: Overload deploy with sub-action** -- `deploy inngest restart latest`
- Treats `restart` as the image field, fails current image validation
- Requires special-casing in the inngest case branch to distinguish deploy vs. restart
- Muddies the command grammar

**Chosen: Option A.** The `restart` action is semantically distinct from `deploy`. Clean action-level dispatch avoids convolving image validation with action routing.

### Command format: `restart inngest _ latest`

- Field 1 (`ACTION`): `restart` (new, alongside existing `deploy`)
- Field 2 (`COMPONENT`): `inngest` (reuses existing component validation)
- Field 3 (`IMAGE`): `_` (placeholder, validated as literal `_` for restart)
- Field 4 (`TAG`): `latest` (sentinel, validated as literal `latest` for restart)

### Implementation Phases

#### Phase 1: Sudoers entry for inngest-server restart

Add a new `Cmnd_Alias` to `deploy-inngest-bootstrap.sudoers`:

```
Cmnd_Alias INNGEST_RESTART = /usr/bin/systemctl restart inngest-server.service
deploy ALL=(root) NOPASSWD: INNGEST_RESTART
```

This is an IaC change that requires `terraform apply` to push the updated sudoers file via `infra-config-apply.sh` (which writes it to `/etc/sudoers.d/deploy-inngest-bootstrap`). The `triggers_replace` in `terraform_data.deploy_pipeline_fix` already includes `deploy-inngest-bootstrap.sudoers` in its SHA hash list (server.tf:236), so the change will be detected and pushed automatically on next `terraform apply`.

**Files to edit:**
- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers`

#### Phase 2: ci-deploy.sh restart action + inngest function verification helper

Widen the command parser to accept `restart` as a valid action alongside `deploy`. Add:
1. Action validation: accept `restart` in addition to `deploy`
2. For `restart` action: validate component is `inngest`, reject other components
3. `restart inngest` handler: `sudo systemctl restart inngest-server.service`, health check loop, function registry sanity check
4. Shared helper function `verify_inngest_functions()` that:
   - Waits for health at `127.0.0.1:8288` (up to 30s, 10 attempts x 3s)
   - Queries `curl -s http://127.0.0.1:8288/v1/functions | jq length`
   - Returns 0 if count >= 1 (functions registered), 1 if count == 0 (H9a full desync)
   - Logs the actual count for operator visibility

**Files to edit:**
- `apps/web-platform/infra/ci-deploy.sh`

#### Phase 3: Post-deploy inngest function log in web-platform handler

[Plan review: All 3 reviewers agreed auto-restart is premature. Kieran P1 identified structural impossibility of post-`exit 0` placement. Simplified to log-only.]

BEFORE the `final_write_state 0 "ok"` / `exit 0` at the end of the successful web-platform deploy path (between canary cleanup at lines 532-533 and the final state write at line 535), add a lightweight informational log:
1. Wait 5s for the new container to register functions with inngest-server
2. Query `curl -s http://127.0.0.1:8288/v1/functions | jq length` (single attempt, no retry)
3. Log the count via `logger -t "$LOG_TAG" "INNGEST_FUNCTION_COUNT: $count"`
4. If count == 0, emit a `logger -t "$LOG_TAG" "INNGEST_WARN: zero functions registered after deploy — consider running restart-inngest-server.yml workflow"`
5. This is strictly informational. Deploy success is NOT gated on inngest function count. No auto-restart. The standalone restart workflow (Phase 4) is the operator-initiated recovery path.

**Files to edit:**
- `apps/web-platform/infra/ci-deploy.sh` (web-platform case branch, before final_write_state)

#### Phase 4: GitHub Actions workflow for standalone inngest restart

Create a `workflow_dispatch`-triggered workflow that:
1. Sends the `restart inngest _ latest` command to the deploy webhook (HMAC-signed)
2. Includes CF Access headers (`CF-Access-Client-Id`, `CF-Access-Client-Secret`) -- required because the webhook endpoint is behind Cloudflare Access (same pattern as web-platform-release.yml lines 292-313)
3. Polls the deploy-status endpoint until `exit_code != -1` (mirrors the web-platform-release.yml "Verify deploy script completion" step pattern at lines 316-387, but simpler -- no version matching, just wait for terminal state)
4. Reports success/failure via `::notice::` / `::error::` annotations

**Files to create:**
- `.github/workflows/restart-inngest-server.yml`

#### Phase 5: Update H9 runbook with automated restore

Update the H9 section in `cloud-scheduled-tasks.md` to reference the new automated restore path via `gh workflow run restart-inngest-server.yml` instead of SSH.

**Files to edit:**
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` (H9 Restore section)

## User-Brand Impact

- **If this lands broken, the user experiences:** Inngest-fired scheduled tasks (daily triage, community monitor, bug fixer, oauth probe) stop firing after a deploy burst. Sentry cron monitors detect the silence within 2-10 days depending on task cadence. The user's autonomous agent capabilities degrade silently.
- **If this leaks, the user's workflow is exposed via:** No data exposure. The restart command operates on a loopback-only service with HMAC-authenticated webhook. The function registry count (40) is not sensitive.
- **Brand-survival threshold:** `aggregate pattern`

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeat for inngest-server (existing, inngest.tf:108)
  cadence: 60s (inngest-heartbeat.timer)
  alert_target: operator email via Better Stack
  configured_in: apps/web-platform/infra/inngest.tf:108

error_reporting:
  destination: journald via logger -t ci-deploy + deploy-status webhook endpoint
  fail_loud: reason=inngest_restart_failed or reason=inngest_health_failed in deploy state JSON

failure_modes:
  - mode: inngest-server.service fails to start after restart
    detection: deploy state reason field contains inngest_restart_failed; Better Stack heartbeat goes silent within 90s grace
    alert_route: Better Stack email + deploy-status webhook surfacing via GHA workflow
  - mode: function registry empty after restart (H9a full desync)
    detection: deploy state reason=inngest_no_functions; journald log ci-deploy INNGEST_WARN
    alert_route: GHA workflow annotation via ::error:: in restart-inngest-server.yml

logs:
  where: journalctl -u webhook -t ci-deploy (restart action logs); journalctl -u inngest-server.service (server logs)
  retention: systemd journal default (system-configured, typically 4GB or 1 month)

discoverability_test:
  command: >
    SIGNATURE=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //');
    curl -s --max-time 10 -H "X-Signature-256: sha256=$SIGNATURE"
    -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID"
    -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET"
    "https://deploy.soleur.ai/hooks/deploy-status" | jq .
  expected_output: '{"exit_code":0,"component":"inngest","reason":"success",...}'
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `ci-deploy.sh` accepts `restart inngest _ latest` and dispatches to the restart handler (verified via ci-deploy.test.sh mock test)
- [ ] AC2: `ci-deploy.sh` rejects `restart web-platform _ latest` with `component_not_restartable` reason (only inngest is restartable)
- [ ] AC3: `verify_inngest_functions()` helper function exists and checks `count >= 1` (not exact match). Called from restart handler. Web-platform handler logs count informally (single curl, no helper call needed).
- [ ] AC4: web-platform handler logs inngest function count BEFORE `final_write_state 0 "ok"` (placement verified by grep: `logger.*INNGEST_FUNCTION_COUNT` appears before `final_write_state 0` in the web-platform case branch)
- [ ] AC5: ci-deploy.test.sh has test cases for: (a) successful restart with health check pass, (b) inngest health check failure after restart, (c) restart of non-inngest component rejected, (d) inngest restart with zero functions returns non-zero
- [ ] AC6: `deploy-inngest-bootstrap.sudoers` includes `INNGEST_RESTART` Cmnd_Alias for `systemctl restart inngest-server.service`
- [ ] AC7: `restart-inngest-server.yml` workflow exists with `workflow_dispatch` trigger, sends `restart inngest _ latest` to the deploy webhook with CF Access headers, and polls deploy-status for completion
- [ ] AC8: H9 Restore section in `cloud-scheduled-tasks.md` references `gh workflow run restart-inngest-server.yml` as the primary restore path
- [ ] AC9: cloud-init.yml template includes the updated sudoers content (fresh-host parity with deploy_pipeline_fix)

### Post-merge (operator)

- [ ] AC10: `terraform apply` pushes updated sudoers to the host (verified via deploy-status endpoint showing successful infra-config push). Automation: `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=terraform_data.deploy_pipeline_fix` via the canonical Terraform invocation triplet (export AWS creds separately for R2 backend).
- [ ] AC11: `gh workflow run restart-inngest-server.yml` successfully restarts inngest-server and reports function count. Automation: `gh workflow run restart-inngest-server.yml` from any machine with `gh` auth.

## Test Scenarios

- Given ci-deploy.sh receives `restart inngest _ latest`, when inngest-server.service is running and functions are registered, then it restarts the service, waits for health at 127.0.0.1:8288, verifies function count >= 1, and writes state `{exit_code: 0, reason: "success"}`
- Given ci-deploy.sh receives `restart inngest _ latest`, when inngest-server.service fails to start (health check times out), then it writes state `{exit_code: 1, reason: "inngest_health_failed"}`
- Given ci-deploy.sh receives `restart inngest _ latest`, when health check passes but function count = 0, then it writes state `{exit_code: 1, reason: "inngest_no_functions"}`
- Given a web-platform deploy succeeds (canary promotion), then ci-deploy.sh logs the inngest function count before writing final state. Deploy succeeds regardless of count.
- Given ci-deploy.sh receives `restart web-platform _ latest`, then it rejects with `component_not_restartable`
- Given ci-deploy.sh receives `deploy inngest restart latest`, then it rejects with `image_mismatch` (existing validation -- `restart` != `ghcr.io/jikig-ai/soleur-inngest-bootstrap`)

## Technical Considerations

### Command grammar change

The current ci-deploy.sh only accepts `deploy` as the action. Adding `restart` widens the command grammar. The field-count validation (exactly 4 fields) remains unchanged. The image and tag fields have different validation rules for `restart` vs `deploy`:
- `deploy`: image must match `ALLOWED_IMAGES[$COMPONENT]`, tag must be `vX.Y.Z`
- `restart`: image must be literal `_`, tag must be literal `latest`

### Sudoers security surface

Adding `systemctl restart inngest-server.service` to the sudoers allowlist is a minimal privilege escalation. The `deploy` user can already run `inngest-bootstrap.sh` as root (which itself calls `systemctl enable --now inngest-server.service`). The new entry pins the exact command -- no wildcards, no argument injection.

### Log-only post-deploy verification

[Plan review: All 3 reviewers agreed auto-restart is premature and risky in the deploy pipeline. The standalone restart workflow is the right operator-initiated recovery path.]

The inngest function count log in the web-platform handler is strictly informational. It does NOT gate deploy success, does NOT auto-restart, and does NOT write to the state file. The existing Better Stack heartbeat and Sentry cron monitors provide the load-bearing alerting. If the count is 0, the log message tells the operator to run `gh workflow run restart-inngest-server.yml`.

### Flock serialization

The restart action shares the same flock at `/var/lock/ci-deploy.lock` as deploy actions. This prevents a restart from racing with a concurrent deploy. The serialization is correct: a restart during a deploy would be dangerous (the deploy may be mid-bootstrap).

### Floor check vs. exact count

[Plan review: DHH P2 + Code Simplicity P1 agreed exact-count matching creates maintenance coupling and false positives.]

The `verify_inngest_functions()` helper uses `count >= 1` (not exact match against 40). The real H9a signal is "zero functions registered" (full desync after rapid deploy churn). A count of 39 vs 40 is not a desync -- it could be a legitimate function removal between a CI run and the deploy. The CI-time test (`function-registry-count.test.ts`) already enforces exact count at compile time; the deploy-time check is a runtime sanity check for the catastrophic failure mode only.

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Sudoers file syntax error bricks sudo on host | Low | High | `visudo -c -f` validation in infra-config-apply.sh (already exists at line 59). Test syntax in ci-deploy.test.sh. |
| Function count is zero after deploy (H9a desync) | Low | Medium | Floor check (>= 1) catches the catastrophic case. Better Stack heartbeat + Sentry cron monitors detect within 90s/2-10 days respectively. Operator runs restart workflow for recovery. |
| Restart during ongoing Inngest event processing | Low | Medium | Inngest server uses SQLite; restart causes brief unavailability but queued events survive on disk. The 30s post-restart wait allows recovery. |
| `terraform apply` required post-merge for sudoers | Certain | Low | Well-documented in AC11. The existing `deploy_pipeline_fix` resource handles this automatically. |

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` -- add restart action, verify_inngest_functions helper, post-deploy function count log
- `apps/web-platform/infra/ci-deploy.test.sh` -- add restart test cases
- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` -- add INNGEST_RESTART Cmnd_Alias
- `apps/web-platform/infra/cloud-init.yml` -- add INNGEST_RESTART Cmnd_Alias to inline sudoers block at lines 54-64 (fresh-host parity with deploy-inngest-bootstrap.sudoers, per Kieran review P5)
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` -- update H9 Restore with automated path

## Files to Create

- `.github/workflows/restart-inngest-server.yml` -- standalone workflow_dispatch trigger

## Open Code-Review Overlap

None. The 3 open code-review issues (#2197, #3216, #3220) touching ci-deploy.sh-adjacent files are unrelated (billing type refactor, canary bundle regex, migration verification).

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Pure infrastructure/ops change. No new data surfaces, no auth changes, no user-facing UI impact. The inngest restart capability is a well-scoped ops remediation that closes the SSH-requiring gap in the H9 runbook. Aligns with `hr-all-infrastructure-provisioning-servers` and `hr-no-ssh-fallback-in-runbooks`.

## Infrastructure (IaC)

### Terraform changes

**Existing TF root:** `apps/web-platform/infra/`
**Modified file:** `deploy-inngest-bootstrap.sudoers` (already tracked in `terraform_data.deploy_pipeline_fix` triggers_replace hash)
**No new providers or resources.** The sudoers change is a file content update that flows through the existing `infra-config-apply.sh` mechanism.

### Apply path

(b) cloud-init + idempotent infra-config push. The `terraform_data.deploy_pipeline_fix` resource detects the sudoers SHA change and pushes via `push-infra-config.sh` -> `infra-config-apply.sh`. Already-running host receives the update; fresh hosts get it via cloud-init.

### Distinctness / drift safeguards

No dev/prd distinction for sudoers -- single production host. The `triggers_replace` SHA ensures the file is pushed when changed.

### Vendor-tier reality check

N/A -- no vendor dependencies for this change.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The restart action reuses the same flock and state file as deploy. A restart's state JSON will have `component: "inngest"` and `reason: "success"`. The web-platform-release.yml deploy verification step (lines 316-387) polls for `tag: "vX.Y.Z"` -- a restart's state (`tag: "latest"`) will not match and will be ignored by the poll loop. This is correct behavior: the restart is not a web-platform deploy.
- The restart workflow (`.github/workflows/restart-inngest-server.yml`) requires `workflow_dispatch` — per the "workflow_dispatch requires default branch" Sharp Edge in the plan skill, this workflow cannot be tested pre-merge via `gh workflow run`. It must be tested post-merge. The pre-merge AC verifies the YAML syntax and HMAC signing logic via `actionlint` + the ci-deploy.test.sh restart test.
- The `_ latest` sentinel fields in `restart inngest _ latest` are ceremony required by the 4-field parser. If a future refactor moves to a variable-length command grammar, they can be dropped.

## Plan Review

Reviewed by DHH Rails Reviewer, Kieran Rails Reviewer, and Code Simplicity Reviewer.

### Agreements (all 3 reviewers)

1. **Cut auto-restart from Phase 3.** All three agreed the auto-restart in the web-platform post-deploy handler is premature, risky, and structurally complex. The standalone restart workflow (Phase 4) is the right operator-initiated recovery path. Phase 3 simplified to log-only.
2. **Floor check instead of exact count.** Replace `EXPECTED_INNGEST_FUNCTIONS=40` exact match with `count >= 1`. The real H9a signal is zero functions (full desync). Eliminates the original Phase 4 (CI parity test) and its maintenance coupling.
3. **Simplify sentinel validation.** The `_ latest` fields are ceremony; validation of them is low-value since the webhook is HMAC-authenticated.

### Kieran-only findings (correctness, applied)

4. **P1: Post-`exit 0` placement is structurally impossible.** Fixed: verification placed BEFORE `final_write_state`.
5. **P2: State file clobbering risk.** Resolved by making Phase 3 log-only (no state writes from verification path).
6. **P3: CF Access headers required in restart workflow.** Added to Phase 4 specification.
7. **P4: Restart workflow needs deploy-status polling.** Added to Phase 4 specification.
8. **P5: cloud-init.yml also needs sudoers update.** Added to Files to Edit.

## References

- Issue: #4538
- H9 runbook: `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` lines 264-327
- Function registry test: `apps/web-platform/test/server/inngest/function-registry-count.test.ts`
- PR #4531: documented the gap and added the H9 hypothesis
- Inngest substrate learning: `knowledge-base/project/learnings/2026-05-19-inngest-substrate-five-bug-cascade.md`
- ci-deploy.sh deploy webhook pattern: `.github/workflows/web-platform-release.yml` lines 292-313
- Sudoers provisioning: `apps/web-platform/infra/server.tf` lines 217-262 (deploy_pipeline_fix)
- Sudoers validation: `apps/web-platform/infra/infra-config-apply.sh` line 59
