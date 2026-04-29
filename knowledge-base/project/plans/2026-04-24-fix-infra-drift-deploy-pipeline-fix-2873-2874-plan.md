---
date: 2026-04-24
type: ops-remediation
issues: ["#2873", "#2874"]
related_issues: ["#2618", "#2234", "#1899", "#1505", "#1412", "#994", "#988"]
related_learnings:
  - "knowledge-base/project/learnings/2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md"
  - "knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md"
  - "knowledge-base/project/learnings/2026-03-21-terraform-drift-dead-code-and-missing-secrets.md"
component: apps/web-platform/infra
files_to_edit: none
classification: ops-only-prod-write
priority: p1-high
---

# Plan: Fix recurring `terraform_data.deploy_pipeline_fix` drift (#2873, #2874)

> **2026-04-29 NOTE:** This plan's webhook smoke-test acceptance criterion ("Expected: HTTP 200" against `https://deploy.soleur.ai/hooks/deploy-status`) is **legacy** and incorrect post-CF-Access. Use the file+systemd contract documented in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` "When NOT to use this probe" subsection. Tracking: #3034.

## Enhancement Summary

**Deepened on:** 2026-04-24
**Sections enhanced:** 4 (Phase 1 verification, Phase 2 apply, Phase 3 deferral, Risks)
**Research sources:**

- Local: `knowledge-base/project/learnings/2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`
- Local: `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`
- Local: `knowledge-base/project/learnings/2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`
- Local: `knowledge-base/project/learnings/2026-03-21-ci-terraform-plan-workflow.md`
- Git history: commits `61c637c8` (#2842), `321ceacb` (#2682), `e40b8f9d` (#2653) — files changed since #2618 remediation
- Issue history: #2873, #2874, #2618, #2234, #1899, #1505, #1412, #994, #988 (all same-class)
- Repo code: `apps/web-platform/infra/server.tf:209-269`, `:5-8`, `:43-49`; `hooks.json.tmpl`; `cloud-init.yml:130,139`; `.github/workflows/scheduled-terraform-drift.yml`
- Runbooks: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`

### Key Improvements (from deepen pass)

1. **Confirmed exact trigger PR** — git log + diff of trigger files since #2618
   identifies PR #2842 (commit `61c637c8`, 2026-04-23) as the `ci-deploy.sh` edit
   that invalidated the sha256. Eliminates the "unknown cause" framing from the
   issue body.
2. **Failure-mode recovery enumerated** — Phase 2 step 2 now lists 4 concrete
   failure modes (SSH refused, agent missing key, partial provisioner failure,
   post-apply drift persists) with specific recovery steps, each keyed to a
   documented learning or rule.
3. **Mandatory `-target` scoping** — Phase 2 step 1 scopes the apply to
   `terraform_data.deploy_pipeline_fix` so any *other* drift that appeared
   between plan and apply cannot be silently swept in.
4. **Prevention deferral issue, not AGENTS.md rule** — applies
   `wg-every-session-error-must-produce-either` discoverability exit: the drift
   workflow IS the discovery mechanism, so a rule would be net-negative against
   the 37k-byte AGENTS.md budget. Learning + deferral issue is the right pair.

### New Considerations Discovered

- **`-auto-approve` hook gap** — the hook proposed in
  `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` is *not yet
  installed*. Phase 2 step 1 asserts the rule inline; verify hook installation
  in a follow-up (tracked in the Phase 3 deferral issue scope).
- **8th recurrence in ~6 weeks** — pattern is structural. Deferral issue captures
  the `/ship` post-merge gate as the durable fix.
- **Plan exit-code semantics** — per
  `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`, exit 1 (plan
  error) can *mask* real drift. Phase 1 step 5 halt conditions distinguish exit
  1 from exit 2.
- **Operator IP allowlist** — added as Phase 1 step 4 pre-flight. The apply's
  SSH provisioner will hang or fail if the operator's egress IP is not in
  `ADMIN_IPS`. Runbook `admin-ip-drift.md` covers remediation.

## Overview

Two open `infra-drift` issues (#2873 detected 2026-04-23 19:14 UTC; #2874 detected
2026-04-24 08:07 UTC) report identical drift in `apps/web-platform/infra/`:

```text
# terraform_data.deploy_pipeline_fix must be replaced
-/+ resource "terraform_data" "deploy_pipeline_fix" {
      ~ id               = "260c00b0-..." -> (known after apply)
      ~ triggers_replace = (sensitive value) # forces replacement
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

This is the **same drift class** that produced #2618 (closed 2026-04-19 by the same
remediation pattern), #2234 (2026-04-15), and the earlier #1899/#1505/#1412/#994/#988
cluster. There is nothing wrong with the Terraform code or the resource design — the
drift is **expected behavior** of an intentional bridge resource.

This plan is therefore **ops-only**: no Terraform code edits, no `Files to Edit`,
no application changes. The remediation is a controlled, per-command-authorized
`terraform apply` against the `prd_terraform` Doppler config to push the latest
`ci-deploy.sh` to the existing prod server, after which the drift workflow returns
to exit code 0 and both issues can be closed.

A separate "Prevention" phase enumerates structural mitigations (a `/ship` post-merge
gate for provisioner-touching PRs) and explicitly defers them to a tracking issue —
implementing them is out of scope for this remediation.

## Hypotheses

The drift cause was identified during planning and is **not in dispute** — confirmed by
diffing the relevant files since the prior remediation. Listed here for completeness:

1. **Confirmed root cause: PR #2842 (commit `61c637c8`, merged 2026-04-23 13:28 +0200)
   modified `apps/web-platform/infra/ci-deploy.sh`** — replacing the
   `credential.helper=!<path>` git auth pattern with `GIT_ASKPASS`. This file is one
   of four inputs to the `triggers_replace` sha256 hash on
   `terraform_data.deploy_pipeline_fix` (`server.tf:216-221`). Any change to
   `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, or
   `local.hooks_json` requires `terraform apply` to push the new file to the
   existing prod server (which has `lifecycle.ignore_changes = [user_data]` on
   `hcloud_server.web` and therefore never re-runs cloud-init). The drift
   workflow correctly detected the unapplied change at the next 06:00/18:00 UTC
   tick on 2026-04-23 19:14 UTC (#2873) and again on 2026-04-24 08:07 UTC (#2874).
2. **`triggers_replace = (sensitive value)`** — the `local.hooks_json` input to the
   sha256 includes `var.webhook_deploy_secret`, which is `sensitive = true`. Terraform
   redacts the entire derived value in the plan output. This is *not* a missing-secret
   bug (cf. #988 in `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`) —
   exit code is 2 (drift), not 1 (plan error), so all variables resolved cleanly.

The Terraform `terraform_data` bridge resource is the **single intentional path** for
pushing `ci-deploy.sh` updates to the existing server (per the in-file comment at
`server.tf:212-215` referencing #2185). No alternative remediation (e.g., re-bootstrap
cloud-init) is appropriate.

## Network-Outage Hypothesis Check

Not applicable to the *drift* itself — drift is a Terraform state consistency
issue, not a connectivity symptom. However, the **remediation** (Phase 2
apply) does SSH from the operator's workstation to the prod server via
`connection { agent = true }`, so a layer-by-layer pre-flight is recorded
below per `hr-ssh-diagnosis-verify-firewall` in case Phase 2 fails with
a connectivity symptom.

### Network-Outage Deep-Dive (pre-flight status for Phase 2 apply)

| Layer                  | Verification in this plan                                                   | Status / Artifact                                                                                                                                                                                      |
| ---------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| L3 firewall allow-list | Phase 1 step 4: `curl -s ifconfig.me/ip` + `doppler secrets get ADMIN_IPS`. | **Verification prescribed as halt gate.** Operator runs this before authorizing Phase 2. Runbook `admin-ip-drift.md` covers refresh via `skill: soleur:admin-ip-refresh`.                               |
| L3 DNS / routing       | Not verified (not expected to drift for an operator workstation).           | If apply fails with `getaddrinfo` or `No route to host`, halt and diagnose before retrying. Target host: `<hcloud_server.web.ipv4_address>` (resolved by terraform at apply time, not a DNS dependency). |
| L7 TLS / proxy         | Not applicable — provisioner uses raw SSH (port 22), not HTTPS.             | The webhook endpoint verification (Phase 2 step 3) uses HTTPS via Cloudflare Access; gated on CF Access headers from `prd_terraform` Doppler.                                                           |
| L7 application (SSH)   | Phase 1 step 3: `ssh-add -l` + `connection { agent = true }` contract.      | **Explicit.** Passphrase-encrypted key incompatibility is documented in learning `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` — `file(...)` path would fail; `agent = true` works.          |

**Gaps that need closing before Phase 2:** none. All four layers have either a
prescribed verification (L3 firewall, L7 SSH) or an explicit non-applicability
(L3 DNS/routing, L7 TLS).

## Research Reconciliation — Spec vs. Codebase

| Claim                                                              | Reality                                                                                                                                                                                                                                              | Plan response                                                                                                                                                                       |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Likely a non-deterministic input (timestamp, random, content hash that changes between runs)" | **False** — input is a sha256 over four file/string values, all deterministic given identical content. The drift is *intentional* re-replacement after a code change to one of the four inputs (PR #2842 changed `ci-deploy.sh`). | Plan does NOT pursue an "eliminate non-determinism" fix. Plan executes the same `terraform apply` remediation that closed #2618 / #2234 / #1899 / #1505. |
| "Consider whether the resource is still needed."                   | **Yes, still needed.** `hcloud_server.web` has `lifecycle.ignore_changes = [user_data]` (server.tf:48). Cloud-init never re-runs on the existing server, so the `terraform_data` bridge is the sole mechanism for pushing script updates (#2205 comment at server.tf:204-208). | Plan does NOT remove the resource. Removal would silently strand future `ci-deploy.sh`/`webhook.service`/`cat-deploy-state.sh`/`hooks.json` updates on disk-but-not-server.        |
| "Fix it permanently so future drift scans pass clean."             | **Not achievable without behavioral change.** Future PRs that touch the four trigger files WILL re-trigger drift unless the `/ship` workflow is gated on running `terraform apply` post-merge. This is a known structural gap (see #1505 learning). | Phase 3 documents the prevention proposal and files a tracking issue. Implementing it is **explicitly out of scope** for this PR.                                                  |

## Files to Edit

**None.** This is an ops-only remediation against production state.

## Files to Create

**None** — except the plan artifact itself
(`knowledge-base/project/plans/2026-04-24-fix-infra-drift-deploy-pipeline-fix-2873-2874-plan.md`)
and the Phase 3 deferral issue (created via `gh issue create`, not a file).

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open --limit 200` and
searched for `apps/web-platform/infra/server.tf` and
`apps/web-platform/infra/ci-deploy.sh` in the bodies of all open scope-outs at
2026-04-24. No matches.

## Implementation Phases

### Phase 1 — Pre-apply verification (read-only)

Goal: confirm the drift before mutating prod state. All commands are read-only.

1. **Confirm git working tree is clean and on `feat-one-shot-fix-infra-drift-2873-2874`:**

   ```bash
   git -C /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-infra-drift-2873-2874 status --short
   git -C /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-infra-drift-2873-2874 branch --show-current
   ```

2. **Verify the four trigger inputs match what's in HEAD** (no uncommitted edits to
   the trigger files would invalidate the plan):

   ```bash
   git -C <worktree> diff HEAD -- \
     apps/web-platform/infra/ci-deploy.sh \
     apps/web-platform/infra/webhook.service \
     apps/web-platform/infra/cat-deploy-state.sh \
     apps/web-platform/infra/hooks.json.tmpl
   ```

   Expected: empty output (no diff).

3. **Verify SSH agent has the prod deploy key loaded** (required by the
   `terraform_data.deploy_pipeline_fix` `connection { agent = true }` block;
   per learning `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`,
   passphrase-encrypted keys cannot be loaded via `private_key = file(...)` —
   `agent = true` is the supported path):

   ```bash
   ssh-add -l
   ```

   Expected: at least one key listed (the prod deploy key). If empty, run
   `ssh-add ~/.ssh/<deploy-key>` and re-verify before proceeding.

4. **Verify operator IP is on the prod SSH allowlist** (per
   `hr-ssh-diagnosis-verify-firewall`, contingency check before any prod SSH-touching
   operation):

   ```bash
   curl -s ifconfig.me/ip
   doppler secrets get ADMIN_IPS -p soleur -c prd --plain
   ```

   Expected: operator IP appears in `ADMIN_IPS`. If not, run
   `skill: soleur:admin-ip-refresh` BEFORE Phase 2 — the apply's SSH provisioner
   will hang/fail otherwise.

5. **Run a fresh, local `terraform plan` to confirm drift is still present and
   matches issue bodies:**

   ```bash
   cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-infra-drift-2873-2874/apps/web-platform/infra
   doppler run -p soleur -c prd_terraform -- terraform init -input=false
   doppler run -p soleur -c prd_terraform -- terraform plan -no-color -input=false 2>&1 | tee /tmp/drift-plan-$(date -u +%Y%m%dT%H%M%SZ).txt
   ```

   **Expected output (matches #2873 and #2874):**

   ```text
   Plan: 1 to add, 0 to change, 1 to destroy.

     # terraform_data.deploy_pipeline_fix must be replaced
   -/+ resource "terraform_data" "deploy_pipeline_fix" {
         ~ id               = "..." -> (known after apply)
         ~ triggers_replace = (sensitive value) # forces replacement
       }
   ```

   **Halt conditions:**
   - If plan returns `1 to add, 0 to change, 0 to destroy` (no destroy line) →
     unexpected; investigate before Phase 2.
   - If plan shows additional drifted resources beyond `deploy_pipeline_fix` →
     unexpected; halt and update this plan inline before Phase 2.
   - If plan exits 1 with "missing variable" / "Doppler secret not found" →
     this is the #988 class (plan-error masquerading as drift). Investigate the
     missing Doppler key in `prd_terraform` config; do NOT apply.
   - Plan exit 2 with the matching destroy-and-create line is the green light.

6. **Pause for explicit user authorization to proceed to Phase 2.** Per
   `hr-menu-option-ack-not-prod-write-auth` and learning
   `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`, present
   the exact apply command (Phase 2 step 1) and wait for per-command go-ahead.
   No menu options. No `-auto-approve`.

### Phase 2 — Apply (destructive prod write, per-command authorized)

Goal: replace `terraform_data.deploy_pipeline_fix`, push the latest
`ci-deploy.sh` (and the other three trigger files, all unchanged in this
window) to the prod server, restart the webhook service, and confirm exit-code-0
plan.

1. **Run the apply with `-target` to scope the change** (defense-in-depth: even
   though Phase 1 step 5 confirmed only one resource drifted, `-target` makes
   the blast radius explicit and prevents picking up any unexpected drift that
   appeared between plan and apply):

   ```bash
   cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-infra-drift-2873-2874/apps/web-platform/infra
   doppler run -p soleur -c prd_terraform -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=true
   ```

   **Critical: do NOT pass `-auto-approve`.** Terraform's interactive `yes`
   prompt is the load-bearing safety net. Per the rule and learning, omitting
   it surfaces the prompt; passing it is a workflow violation.

   **Expected output (matches #2618 successful apply):**

   ```text
   terraform_data.deploy_pipeline_fix: Destroying... [id=260c00b0-...]
   terraform_data.deploy_pipeline_fix: Destruction complete after 0s
   terraform_data.deploy_pipeline_fix: Creating...
   terraform_data.deploy_pipeline_fix: Provisioning with 'file'... (x4)
   terraform_data.deploy_pipeline_fix: Provisioning with 'remote-exec'...
   terraform_data.deploy_pipeline_fix: Creation complete after ~10-15s [id=<new-uuid>]

   Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
   ```

2. **Failure-mode handling** (per `cq-terraform-failed-apply-orphaned-state` and
   `hr-when-a-command-exits-non-zero-or-prints`):

   - **SSH connection refused / timeout** → check operator IP allowlist
     (`skill: soleur:admin-ip-refresh`); do NOT retry blindly.
   - **`ssh: parse error in message type 0`** → SSH agent missing key;
     `ssh-add` the deploy key; retry.
   - **Provisioner partial-failure (file uploaded but `remote-exec` failed)** →
     run `terraform state list | grep deploy_pipeline_fix` to detect
     orphaned state; if present, `terraform state rm
     terraform_data.deploy_pipeline_fix` and re-plan to a clean
     "1 to add, 0 to destroy" before re-applying.
   - **Apply exits clean but `terraform plan` still shows drift** → unexpected;
     halt and gather logs before any further action.

3. **Post-apply verification (read-only):**

   ```bash
   # Confirm zero drift
   doppler run -p soleur -c prd_terraform -- terraform plan -detailed-exitcode -no-color -input=false ; echo "EXIT=$?"
   # Confirm webhook is healthy (deploy-status endpoint is the canonical liveness probe)
   WEBHOOK_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET -p soleur -c prd_terraform --plain)
   CF_ID=$(doppler secrets get CF_ACCESS_CLIENT_ID -p soleur -c prd_terraform --plain)
   CF_SECRET=$(doppler secrets get CF_ACCESS_CLIENT_SECRET -p soleur -c prd_terraform --plain)
   SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -hex | awk '{print $NF}')
   curl -sS -o /dev/null -w '%{http_code}\n' \
     -H "CF-Access-Client-Id: $CF_ID" \
     -H "CF-Access-Client-Secret: $CF_SECRET" \
     -H "X-Signature-256: sha256=$SIG" \
     https://deploy.soleur.ai/hooks/deploy-status
   ```

   **Expected:** plan exit code `0`; deploy-status returns HTTP `200`. Per
   `cq-deploy-webhook-observability-debug`, secrets live in `prd_terraform`,
   not `prd`.

### Phase 3 — Document and prevent recurrence (deferral, not implementation)

Goal: capture the recurring nature, file a tracking issue for the structural fix,
and update the AGENTS.md / `/ship` skill mention if warranted.

1. **Comment on #2873 and #2874 with the apply outcome and link to this plan.**
   Use `gh issue comment` with a brief summary (resolution timestamp, new
   resource UUID, plan-exit-0 confirmation, deploy-status HTTP 200).

2. **Close #2873 and #2874** with `gh issue close <N> --reason completed`.

3. **File a deferral issue** for the structural prevention work:

   - **Title:** `infra: prevent recurring terraform_data.deploy_pipeline_fix drift via /ship post-merge gate`
   - **Body:** what (a `/ship` Phase N gate that detects PRs touching
     `apps/web-platform/infra/{ci-deploy.sh,webhook.service,cat-deploy-state.sh,hooks.json.tmpl}`
     and warns / requires `terraform apply` confirmation before merge), why
     (8th occurrence in ~6 weeks: #988, #994, #1412, #1505, #1899, #2234,
     #2618, #2873/#2874 — pattern is structural, not coincidental),
     re-evaluation criteria (file when 2 more occurrences happen, or when
     remote `claude-code-action` workflows can run terraform with prod creds).
   - **Labels:** `domain/engineering`, `priority/p2-medium`, `type/chore`,
     `infra-drift-prevention`.
   - **Milestone:** `Post-MVP / Later` (per existing issue convention).

4. **Do NOT add an AGENTS.md rule** for this. Per
   `wg-every-session-error-must-produce-either` discoverability exit: the drift
   workflow IS the discovery mechanism — it filed the issue and produced the
   exact plan output. The constraint is not hidden. A learning file from this
   PR (covering "the 8th occurrence — pattern is structural") + the deferral
   issue is the right artifact set.

5. **Write a learning file** to
   `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`
   summarizing: (a) the drift is expected by design, (b) the `terraform_data`
   bridge is intentional, (c) the recurring resolution pattern (`terraform apply
   -target=...` against `prd_terraform`), (d) the deferred prevention work tracking
   issue from step 3.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Plan artifact committed to
      `knowledge-base/project/plans/2026-04-24-fix-infra-drift-deploy-pipeline-fix-2873-2874-plan.md`.
- [ ] Learning file committed to
      `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`.
- [ ] Deferral issue created (Phase 3 step 3) and linked from PR body.
- [ ] PR body includes `Ref #2873` and `Ref #2874` (NOT `Closes` — issues close post-apply in Phase 3 step 2, per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] No source code edits in `apps/` (this is ops-only).

### Post-merge (operator)

- [ ] Phase 1 read-only verification completed; drift confirmed matches issue body.
- [ ] User explicitly authorized the exact `terraform apply` command (no menu
      ack, no `-auto-approve`).
- [ ] Phase 2 apply completed with `Apply complete! Resources: 1 added, 0 changed, 1 destroyed.`.
- [ ] `terraform plan -detailed-exitcode` returns `0`.
- [ ] `https://deploy.soleur.ai/hooks/deploy-status` (signed GET) returns HTTP `200`.
- [ ] Issues #2873 and #2874 closed with apply timestamp + new resource UUID
      in the closing comment.
- [ ] Next scheduled drift workflow run (06:00 / 18:00 UTC) returns exit code 0
      (no new issue auto-created).

## Test Scenarios

### Scenario 1 — Happy path (drift matches expectation)

1. Phase 1 plan returns exit 2 with the single `deploy_pipeline_fix` destroy line.
2. Operator authorizes the exact apply command.
3. Phase 2 apply succeeds in ~10-15s.
4. Phase 2 step 3 verification: plan exit 0, deploy-status HTTP 200.
5. Phase 3 closes both issues and files the deferral.

**Expected outcome:** clean state, both issues closed, prevention issue tracked.

### Scenario 2 — Plan exit 1 (missing secret, #988-class)

1. Phase 1 plan exits 1 with `Failed to get secret <KEY>`.

**Expected outcome:** halt. Do NOT apply. Diagnose the missing Doppler key,
add it to `prd_terraform`, re-run Phase 1 step 5. Update plan inline if a new
sub-phase is required.

### Scenario 3 — SSH allowlist drift (admin-IP rotated)

1. Phase 1 step 4 shows operator IP not in `ADMIN_IPS`.

**Expected outcome:** halt before any apply. Run
`skill: soleur:admin-ip-refresh` per the runbook, then resume from Phase 1
step 5.

### Scenario 4 — Apply succeeds but plan still shows drift

1. Phase 2 step 1 reports `Apply complete!`.
2. Phase 2 step 3 plan-detailed-exitcode returns 2 (still drifted).

**Expected outcome:** halt. Capture full apply log + new plan output. This
suggests an undocumented secondary trigger (e.g., a new resource with
non-deterministic `triggers_replace` not yet documented). File a separate
issue rather than retrying.

## Risks

- **Production webhook downtime during apply window** — `systemctl restart webhook`
  in the `remote-exec` provisioner causes a brief unavailability (sub-second).
  Acceptable; deploys are not in-flight (operator schedules the apply).
  Per `hr-menu-option-ack-not-prod-write-auth`, the explicit per-command
  authorization gives the operator a chance to schedule for a quiet window.
- **`-auto-approve` accidentally added** — would bypass terraform's prompt and
  violate the rule. **Mitigation:** the
  `hr-menu-option-ack-not-prod-write-auth`-derived hook proposal in the prior
  learning blocks this if the hook is installed. Without the hook, the planner
  asserts the rule explicitly in Phase 2 step 1.
- **Orphaned state from partial apply** — if `remote-exec` fails after `file`
  uploads succeeded, state can be inconsistent. **Mitigation:** Phase 2 step 2
  documents the `state rm` recovery (per `cq-terraform-failed-apply-orphaned-state`).
- **Recurrence within hours** — if a new PR touches the four trigger files
  before this remediation completes, the drift workflow will fire again on the
  next 12h tick. **Mitigation:** none from this PR; the deferral issue tracks
  the structural fix.

## Non-Goals / Out of Scope

- **Eliminating the `triggers_replace` re-replacement behavior.** It is by
  design — see Research Reconciliation row 1.
- **Implementing the `/ship` post-merge gate that prevents recurrence.** Tracked
  in the Phase 3 step 3 deferral issue.
- **Adding an AGENTS.md rule about this drift class.** Per
  `wg-every-session-error-must-produce-either` discoverability exit, the drift
  workflow IS the discovery mechanism. Rule would be net-negative against the
  37k AGENTS.md byte budget (`cq-agents-md-why-single-line`).
- **Refactoring the `terraform_data.deploy_pipeline_fix` resource.** Removal
  would silently strand future trigger-file changes (Research Reconciliation
  row 2).

## Domain Review

**Domains relevant:** none (CTO-adjacent, but the work is pure-ops remediation
of an existing intentional design — no architectural decision).

No cross-domain implications detected — infrastructure-only ops remediation
with no user-facing surface, no copy, no pricing, no legal exposure.

## Alternative Approaches Considered

| Approach                                                                                              | Why rejected                                                                                                                                                                                                                                                          |
| ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Remove `terraform_data.deploy_pipeline_fix` entirely                                                  | Would strand all future updates to `ci-deploy.sh`/`webhook.service`/`cat-deploy-state.sh`/`hooks.json` on disk-only with no path to the existing prod server (which has `lifecycle.ignore_changes = [user_data]`). See server.tf:212-215 + cloud-init.yml:130/139.  |
| Replace sha256 hash with `null` / no-op trigger (suppress drift detection)                            | Same problem as removal — file content changes would never propagate to prod. Drift detection is doing its job.                                                                                                                                                       |
| Drop `lifecycle.ignore_changes = [user_data]` from `hcloud_server.web` and let cloud-init re-run     | Would force-replace the production server (cloud-init is a create-time attribute that has diverged from current via interpolation drift, per server.tf:43-49 + #967). Catastrophic blast radius vs. the 10-15s `terraform_data` apply.                                |
| Add `-auto-approve` to a CI workflow that auto-applies on every PR merge                              | (a) Violates `hr-menu-option-ack-not-prod-write-auth` design intent — removes terraform's safety net. (b) CI uses dummy SSH keys per `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`; the SSH provisioner would fail. (c) Tracked in deferral issue with safer design. |
| Skip Phase 3 — just apply and close issues                                                            | Pattern is recurring (8 instances in ~6 weeks). Without a tracking issue for the structural fix, the next occurrence wastes another planning + remediation cycle. `wg-when-deferring-a-capability-create-a` requires a tracking issue.                                |

## Research Insights

- **Recurring pattern (8 instances in ~6 weeks):** #988 (2026-03-21) → #994 →
  #1412 → #1505 → #1899 → #2234 (2026-04-15) → #2618 (2026-04-19) → #2873/#2874
  (2026-04-23/24). Each was resolved by `terraform apply` against `prd_terraform`.
- **Prior remediation pattern (#2618 closing comment, 2026-04-19):**
  > Drift was `terraform_data.deploy_pipeline_fix` — its `triggers_replace` hash
  > diverged because PR #2187 added `cat-deploy-state.sh` and modified
  > `hooks.json.tmpl`. Apply: 1 added, 1 destroyed in ~11s. Endpoint live.
- **Trigger files (`server.tf:216-221`):** sha256 over
  `ci-deploy.sh` + `webhook.service` + `cat-deploy-state.sh` + `local.hooks_json`.
- **`local.hooks_json` (`server.tf:5-7`):** `templatefile("hooks.json.tmpl",
  { webhook_deploy_secret = var.webhook_deploy_secret })`. Sensitive variable
  → derived hash is sensitive → plan output redacts the value (`(sensitive value)`).
- **Why no cloud-init re-run:** `hcloud_server.web` has
  `lifecycle.ignore_changes = [user_data, ssh_keys, image]` (server.tf:48) per
  #967 — protects against import-artifact-driven server replacement. The
  `terraform_data.deploy_pipeline_fix` bridge is the explicit remediation
  for that constraint (server.tf:213-215, #2185).
- **`connection { agent = true }`:** per learning
  `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`, this is
  the supported path for passphrase-encrypted local keys; `private_key =
  file(...)` would fail with `ssh: parse error in message type 0`.
- **Doppler config for backend + provider creds:** `prd_terraform` (per
  `cq-deploy-webhook-observability-debug` — secrets live there, not `prd`).
- **CLI verification:** `terraform plan -detailed-exitcode` and `terraform apply
  -target=<resource>` are documented in HashiCorp's CLI reference
  (https://developer.hashicorp.com/terraform/cli/commands/plan and .../apply).
  `doppler run --` is verified via `doppler run --help` locally;
  `doppler secrets get --plain` is verified via `doppler secrets get --help`.
  No fabricated tokens.

## Self-Review (deepen pass findings)

**Architecture / strategy review:**

- ✅ Plan does NOT propose refactoring `terraform_data.deploy_pipeline_fix` — the
  resource is intentional per `server.tf:212-215` (refs #2185) and sync-comments
  in `cloud-init.yml:130,139`.
- ✅ Plan does NOT drop `lifecycle.ignore_changes = [user_data]` from
  `hcloud_server.web` — that would force catastrophic server replacement per
  `server.tf:43-49` (refs #967).
- ✅ Plan does NOT add an AGENTS.md rule — discoverability exit applies.

**Simplicity review (YAGNI):**

- ✅ Phase 1 is all read-only verification. No speculative checks.
- ✅ Phase 2 has exactly one destructive step scoped via `-target`.
- ✅ Phase 3 defers prevention to a separate issue. Avoids scope-creep into the
  structural `/ship` gate inside this PR.

**Security review:**

- ✅ No `-auto-approve` anywhere in the plan. Terraform's interactive prompt
  is the load-bearing safety net per `hr-menu-option-ack-not-prod-write-auth`.
- ✅ Webhook verification uses HMAC-signed empty-body GET per
  `cq-deploy-webhook-observability-debug`. Secrets fetched from
  `prd_terraform` Doppler config, not `prd`.
- ✅ SSH via agent-only (no `private_key = file(...)` which would require an
  unencrypted key on disk). Documented in
  `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`.
- ✅ Operator IP allowlist verified as Phase 1 step 4 before any prod-touching
  operation.

**Deployment-verification review:**

- ✅ Phase 2 step 3 probes `/hooks/deploy-status` for HTTP 200 — the canonical
  liveness signal for the webhook service that was restarted by the provisioner.
- ✅ Phase 2 step 3 also re-runs `terraform plan -detailed-exitcode` → exit
  `0` as the structural confirmation.
- ✅ Acceptance criteria includes the "next scheduled drift workflow run
  returns exit 0" check — closes the loop with the CI system that filed the
  issues.

**Pattern-recognition review:**

- ✅ Plan explicitly recognizes the 8-instance recurrence and files a deferral
  issue for the structural fix. Does NOT treat this as a one-off.
- ✅ Plan does NOT propagate the #988-class exit-1-masking-drift bug pattern;
  Phase 1 step 5 halt conditions distinguish exit 1 from exit 2.

**Data-integrity review:**

- ✅ No data migrations, no schema changes, no fixture seeding.
- ✅ `-target` scoping prevents unintentional state mutation of other
  resources (via "picked up new drift that appeared between plan and apply").
- ✅ Orphan-state recovery documented per `cq-terraform-failed-apply-orphaned-state`.

**Test-design review:**

- ✅ Four test scenarios cover: happy path, plan-error class, firewall drift
  class, post-apply drift persistence. No test gap for the drift-workflow
  loop-close.
- ⚠️ **No automated pre-merge test** — by design, since the remediation is
  pure-ops against prod and the verification is human-authorized. This is
  accepted: the `/ship` post-merge gate (tracked in the deferral issue) is
  where automated pre-verification would live.

## References

- Issues: #2873, #2874 (open); #2618, #2234, #1899, #1505, #1412, #994, #988 (closed, same class)
- Files: `apps/web-platform/infra/server.tf:209-269` (resource definition),
  `apps/web-platform/infra/server.tf:5-7` (local.hooks_json),
  `apps/web-platform/infra/server.tf:43-49` (ignore_changes on user_data),
  `apps/web-platform/infra/cloud-init.yml:130,139` (sync comments),
  `apps/web-platform/infra/hooks.json.tmpl` (template inputs)
- Recent triggering PR: #2842 (commit `61c637c8`, 2026-04-23 — modified ci-deploy.sh)
- Learnings:
  `knowledge-base/project/learnings/2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`,
  `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`,
  `knowledge-base/project/learnings/2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`
- Workflow: `.github/workflows/scheduled-terraform-drift.yml` (cron `0 6,18 * * *`)
- Runbook contingency: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`
- AGENTS.md rules invoked:
  - `hr-menu-option-ack-not-prod-write-auth` (no `-auto-approve` against prd*)
  - `hr-all-infrastructure-provisioning-servers` (Terraform-only path)
  - `hr-when-a-command-exits-non-zero-or-prints` (halt-and-investigate gates)
  - `hr-ssh-diagnosis-verify-firewall` (Phase 1 step 4 contingency)
  - `cq-deploy-webhook-observability-debug` (verification secrets in `prd_terraform`)
  - `cq-terraform-failed-apply-orphaned-state` (Phase 2 step 2 recovery)
  - `wg-when-deferring-a-capability-create-a` (Phase 3 step 3 deferral issue)
  - `wg-every-session-error-must-produce-either` (no AGENTS.md rule, learning + deferral)
