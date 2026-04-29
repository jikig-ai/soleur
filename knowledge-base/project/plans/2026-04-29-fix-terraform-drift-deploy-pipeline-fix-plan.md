---
type: ops-remediation
classification: ops-only-prod-write
issue: "#3019"
related_issues: ["#2881", "#2874", "#2618", "#2234", "#1899", "#1505", "#1412", "#994", "#988"]
related_prs: ["#3014", "#2880", "#2842"]
requires_cpo_signoff: false
---

# Fix: Reconcile recurring `terraform_data.deploy_pipeline_fix` drift (#3019)

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** Overview, Pre-flight, Implementation Phases, Risks, Network-Outage Deep-Dive (added)
**Research applied:** Terraform `-target` apply semantics (HashiCorp docs), R2-as-S3 backend constraints, `terraform_data` provisioner replacement semantics, institutional learning `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`, runbook `admin-ip-drift.md`, prior-apply pattern from #2874 resolution comment.

### Key Improvements

1. **Network-Outage Deep-Dive added** (Phase 4.5 enforcement): explicit L3 firewall + DNS verification before SSH provisioner runs, with the exact `curl ifconfig.me/ip` + Doppler `ADMIN_IPS` cross-check baked into Phase 2.3.
2. **R2 backend lock semantics documented**: `use_lockfile = false` in `main.tf` means concurrent applies are NOT prevented at the backend layer — operator must serialize manually (no parallel CI drift run during the apply window).
3. **`-target` apply caveat added**: Terraform docs explicitly warn `-target` is "for exceptional circumstances"; the post-apply full-graph plan (Phase 4.1) is mandatory to prove no other resources were skipped.
4. **Provisioner replay risk surfaced**: file provisioner re-uploads are not idempotent at the network layer — the `chmod`/`chown`/`systemctl restart webhook` `remote-exec` IS idempotent, so partial-failure replay is safe.
5. **Pinned tool versions verified**: `terraform 1.10.5` (workflow), `cloudflare ~> 4.0` (4.52.7 lock), `hcloud ~> 1.49` (lock); no provider drift between drift-detection run and operator's local apply.

### New Considerations Discovered

- **Concurrency hazard:** the drift workflow cron runs at 06:00 and 18:00 UTC. Operator apply MUST land outside a ±5min window from those times, otherwise the workflow's `terraform plan` may interleave with the apply's state write and surface a transient lock error (R2 has no conditional writes; `use_lockfile = false`).
- **No-rollback property:** `terraform apply -target=terraform_data.deploy_pipeline_fix` always runs the destroy-then-create cycle (provisioners re-run). If the new ci-deploy.sh has a syntax error, the next deploy webhook hits the broken script. Phase 4.2 webhook smoke-test catches this; mitigations are run-tests-locally first (Phase 1.4 below) and have a roll-forward plan ready.

## Overview

The scheduled drift detection workflow (`.github/workflows/scheduled-terraform-drift.yml`, cron `0 6,18 * * *`) detected on 2026-04-29 08:22 UTC that `terraform_data.deploy_pipeline_fix` is flagged for replacement (`Plan: 1 to add, 0 to change, 1 to destroy`). All other 50+ resources are clean.

**This is the 9th occurrence of the same drift pattern in ~6 weeks** (#988 → #994 → #1412 → #1505 → #1899 → #2234 → #2618 → #2874 → #3019). The pattern is structural and intentional — see learning `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` and meta-issue #2881 (the `/ship` post-merge gate that would prevent the recurrence is gated on a 10th occurrence trigger; this incident IS the 10th cycle counting #2873 + #2874 as one apply).

**Triggering change identified:** PR #3014 (commit `b2fed080`, merged after the 2026-04-24 apply that resolved #2874) modified `apps/web-platform/infra/ci-deploy.sh` to add `/dashboard`, `/login`, and error-sentinel canary probes. This file is one of the four trigger inputs to `terraform_data.deploy_pipeline_fix.triggers_replace` (per `apps/web-platform/infra/server.tf:216-221`), so any edit to it forces resource replacement on the next apply, which pushes the new `ci-deploy.sh` to the existing prod server.

**The drift is intentional, not accidental.** The fix is the documented remediation: an operator-authorized targeted `terraform apply` against the `prd_terraform` Doppler config.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #3019 body) | Reality | Plan response |
|---|---|---|
| "Plan: 1 to add, 1 to destroy" | Confirmed via plan output in issue body — only `terraform_data.deploy_pipeline_fix` is replaced; all 50+ other resources are clean (`Refreshing state...` only) | Targeted apply with `-target=terraform_data.deploy_pipeline_fix` is sufficient and minimizes blast radius |
| "Investigate whether intentional or accidental" | git log shows PR #3014 (`b2fed080`, merged 2026-04-29) is the only commit since the last apply (2026-04-24) that touches any of the four trigger files (`ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `hooks.json.tmpl`); diff confirms `ci-deploy.sh` was modified | Drift is intentional — apply, do not revert |
| "Work goes through Terraform per the infra rule" | Confirmed by AGENTS.md `hr-all-infrastructure-provisioning-servers` and the resource design in `server.tf:209-269` — this `terraform_data` block IS the Terraform-native path for pushing trigger-file edits to the existing server (server has `lifecycle.ignore_changes = [user_data]` per #967) | Plan uses `terraform apply -target=...` exclusively; no SSH, no vendor APIs |
| "Use per-command ack flow for any `terraform apply`" | Required by AGENTS.md `hr-menu-option-ack-not-prod-write-auth`; pattern documented in PR #2880 | Plan presents exact command for explicit per-command operator approval before executing with `-auto-approve` |

## User-Brand Impact

**If this lands broken, the user experiences:** A failed `terraform apply` could leave the existing prod server with a stale `ci-deploy.sh` (no `/dashboard` + `/login` canary probes from #3014), so the next deploy webhook trigger would skip the layered post-deploy health gate that #3014 added — observability gap continues until next remediation.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. This is a state-reconciliation operation; no new credentials are introduced. The trigger files (`ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `hooks.json.tmpl`) and `webhook_deploy_secret` are already in place — they reach the server via the same SSH agent + Hetzner firewall path that the previous 8 applies used.

**Brand-survival threshold:** none

Reason: ops-remediation that re-applies an existing Terraform resource against an unchanged prod server. No new attack surface, no credential rotation, no schema change, no new vendor dependency. The full apply replaces a single `terraform_data` resource that exists solely to push four files via SSH provisioner and restart the webhook service — operations the previous 8 applies have validated as safe.

## Hypotheses (and decision)

1. **Intentional drift (chosen):** PR #3014 modified `ci-deploy.sh` deliberately to add canary probes; the drift detector is correctly flagging the gap between Terraform state and current source files. **Decision: apply.**
2. **Accidental state divergence:** Possible if someone edited `ci-deploy.sh` on the server out-of-band, or if a previous apply was incomplete. Ruled out — file content matches HEAD; no out-of-band ops in the window.
3. **State corruption / hash drift:** Possible if Terraform's hash function changed across versions, but TERRAFORM_VERSION is pinned at `1.10.5` in the workflow and unchanged.

## Network-Outage Deep-Dive (Phase 4.5 enforcement)

The plan invokes the SSH/firewall trigger pattern (terraform provisioner uses `connection { type = "ssh"; agent = true }`). Per `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`, verify L3 → L7 in order before any apply step:

| Layer | Verification | Plan reference |
|---|---|---|
| **L3 firewall allow-list** (Hetzner `hcloud_firewall.web`) | `curl -s ifconfig.me/ip` → cross-check against `doppler secrets get ADMIN_IPS --plain -p soleur -c prd_terraform`. If `hcloud` CLI authed: `hcloud firewall describe web` and grep for `22/tcp` rule covering operator's IP. | Pre-flight Check 5 + Phase 2.3 |
| **L3 DNS / routing** (Hetzner public IP for `hcloud_server.web`) | `terraform output server_ipv4` (or read from `outputs.tf`); `nc -vz <ip> 22 -w 5` from operator's network. | Phase 2 augmented (see edit below) |
| **L7 TLS / proxy** (N/A for SSH provisioner) | Not applicable — SSH provisioner is direct TCP/22 to Hetzner public IP, not proxied via Cloudflare Tunnel. | — |
| **L7 application** (sshd reachable, agent loaded) | `ssh-add -l` non-empty; `ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new root@<ip> 'echo ok'`. | Pre-flight Check 4 |

**Status: All four layers covered by Pre-flight Checks 4–5 and Phase 2 dry-plan. No gaps. The dry-plan in Phase 2.4 does NOT exercise the SSH provisioner (Terraform skips provisioner code in `plan` mode), so Phase 2.6 below is added to bridge this gap.**

If the operator's IP has drifted off the allowlist, route to `/soleur:admin-ip-refresh` (per `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`) BEFORE attempting Phase 3. This was the root cause of #2654 and the trigger for AGENTS.md `hr-ssh-diagnosis-verify-firewall`.

## Pre-flight Checks

Before the apply, verify:

1. **Branch state:** Confirm we are on `feat-one-shot-3019-terraform-drift-deploy-pipeline-fix` and main is up-to-date (`git fetch origin main && git log --oneline origin/main -5`).
2. **Doppler context for backend creds:** `prd_terraform` config (per `.github/workflows/scheduled-terraform-drift.yml` lines 60-66 — `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for the R2 backend live there).
3. **Doppler context for resource secrets:** `prd_terraform` config (used via `doppler run --name-transformer tf-var --` per the same workflow).
4. **SSH agent loaded with operator key:** `ssh-add -l` must show the key whose pubkey corresponds to the prod server's `~/.ssh/authorized_keys`. The provisioner uses `agent = true` (server.tf:227).
5. **Hetzner firewall allowlist includes operator's egress IP:** Per AGENTS.md `hr-ssh-diagnosis-verify-firewall`. Operator's current IP at plan-time: `82.67.29.121`. **Verify before the apply step:**
   - `curl -s ifconfig.me/ip` (should match the IP in Doppler's `ADMIN_IPS` for `prd_terraform`).
   - If `hcloud` CLI is authenticated: `hcloud firewall describe web` and confirm a `22/tcp` rule covering the operator's IP.
   - If the IP has drifted, run `/soleur:admin-ip-refresh` BEFORE the apply (per the same skill's runbook).
6. **`terraform plan -target=terraform_data.deploy_pipeline_fix` matches the issue body exactly:** Run dry plan with the same backend + var args as the workflow, confirm only that resource is in the action list.

## Implementation Phases

### Phase 1 — Confirm drift cause (read-only)

1. `git log --since="2026-04-24" --oneline -- apps/web-platform/infra/ci-deploy.sh apps/web-platform/infra/webhook.service apps/web-platform/infra/cat-deploy-state.sh apps/web-platform/infra/hooks.json.tmpl`
   - **Expected:** one commit, `b2fed080` (PR #3014).
2. `git show --stat b2fed080 -- apps/web-platform/infra/ci-deploy.sh`
   - **Expected:** non-empty diffstat (canary probe additions).
3. Document in PR body: "Drift cause confirmed — PR #3014 modified `ci-deploy.sh` (canary probe additions). Intentional; remediation is targeted apply."

### Phase 1.4 — Run ci-deploy.sh tests locally (no-rollback safeguard)

**Why:** A `terraform_data` provisioner replacement is destroy-then-create. Provisioners always re-run, and there is no rollback — if the new `ci-deploy.sh` has a regression, the next webhook deploy hits the broken script. The Enhancement Summary's "no-rollback property" risk is mitigated here.

```bash
cd apps/web-platform/infra && bash ci-deploy.test.sh
```

**Expected:** `66 ci-deploy` cases pass (per PR #3014 commit message: "2263 unit + 617 component + 66 ci-deploy: all green"). If any case fails, HALT — investigate before applying. `bun test apps/web-platform/infra/audit-bwrap-uid.test.sh apps/web-platform/infra/disk-monitor.test.sh apps/web-platform/infra/orphan-reaper.test.sh apps/web-platform/infra/resource-monitor.test.sh apps/web-platform/infra/mu1-runbook-cleanup.test.sh` is optional but recommended (sibling provisioner scripts).

### Phase 2 — Pre-flight (read-only)

1. `cd apps/web-platform/infra && terraform init -input=false`
   - Requires `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from Doppler `prd_terraform` for the R2 backend. Extract via:
     ```bash
     export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain -p soleur -c prd_terraform)
     export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain -p soleur -c prd_terraform)
     ```
2. `ssh-keygen -t ed25519 -f /tmp/ci_ssh_key -N "" -q` then `export TF_VAR_ssh_key_path=/tmp/ci_ssh_key.pub` (mirrors workflow behaviour for the dummy `ssh_key_path` var; the `lifecycle.ignore_changes = [public_key]` on `hcloud_ssh_key.default` makes this safe).
3. `curl -s ifconfig.me/ip` and verify against `doppler secrets get ADMIN_IPS --plain -p soleur -c prd_terraform`.
4. `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -detailed-exitcode -target=terraform_data.deploy_pipeline_fix -var="ssh_key_path=/tmp/ci_ssh_key.pub" -no-color -input=false`
   - **Expected exit code:** `2` (changes pending).
   - **Expected plan body:** identical replacement block from issue #3019 (one resource: `terraform_data.deploy_pipeline_fix`).
5. **Concurrency check:** the drift workflow runs at `0 6,18 * * *` UTC. Confirm current UTC time is at least 5 minutes away from those windows. If close, wait or proceed knowing R2 has no conditional writes (`use_lockfile = false` in `main.tf:13`).
6. **Live SSH reachability** (Network-Outage Deep-Dive L3/L7 bridge — `terraform plan` does NOT exercise provisioners):
   ```bash
   SERVER_IP=$(doppler run -p soleur -c prd_terraform -- terraform output -raw server_ipv4 2>/dev/null) || \
     SERVER_IP=$(doppler run -p soleur -c prd_terraform -- terraform state show hcloud_server.web | awk '/ipv4_address/ {gsub(/"/,"",$3); print $3; exit}')
   nc -vz "$SERVER_IP" 22 -w 5
   ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new root@"$SERVER_IP" 'echo ok'
   ```
   - **Expected:** `nc` reports `succeeded`; ssh returns `ok`. If either fails, HALT and run `/soleur:admin-ip-refresh`.

### Phase 3 — Apply (per-command ack)

This is the destructive write. Per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`, the operator MUST read and explicitly approve the exact command BEFORE it runs. The agent shell has no TTY, so `terraform apply` cannot prompt — `-auto-approve` is the non-interactive equivalent and is gated by the per-command human ack.

**Exact command awaiting per-command ack:**

```bash
cd apps/web-platform/infra && \
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply -target=terraform_data.deploy_pipeline_fix \
      -var="ssh_key_path=/tmp/ci_ssh_key.pub" \
      -auto-approve -input=false
```

**Expected output:** `Apply complete! Resources: 1 added, 0 changed, 1 destroyed.` and a new resource id (UUID).

### Phase 4 — Post-apply verification

1. Full-graph drift re-check (must be exit `0`):
   ```bash
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform plan -detailed-exitcode -var="ssh_key_path=/tmp/ci_ssh_key.pub" \
     -no-color -input=false
   ```
   - **Expected:** `No changes. Your infrastructure matches the configuration.` and exit code `0`.
2. Webhook health probe (smoke-test the new `ci-deploy.sh` reached the server and webhook restarted cleanly):
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' https://deploy.soleur.ai/hooks/deploy-status \
     -H "X-Signature-256: sha256=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" -hex | awk '{print $2}')"
   ```
   - **Expected:** HTTP `200`. (Mirrors the smoke-test from #2874's resolution comment.)
3. Confirm new resource id (record in PR body / closing comment):
   ```bash
   doppler run -p soleur -c prd_terraform -- \
     terraform state show terraform_data.deploy_pipeline_fix | head -5
   ```

### Phase 5 — Close-out

1. Post resolution comment on #3019 with: triggering PR (#3014), old/new resource ids, full-graph plan exit code, webhook smoke-test result.
2. `gh issue close 3019` (after the apply succeeds — this is `type: ops-remediation`, so PR uses `Ref #3019`, not `Closes #3019`, per AGENTS.md sharp edge).
3. Update meta-issue #2881 with a comment noting this is the 9th occurrence (counting #2873 + #2874 as one cycle); per #2881's re-evaluation criterion (#1), the threshold for implementing the `/ship` post-merge gate is now met.

## Files to Edit

- None. This is a state-reconciliation apply — no source-file edits in the PR.

## Files to Create

- `knowledge-base/project/plans/2026-04-29-fix-terraform-drift-deploy-pipeline-fix-plan.md` (this file).
- `knowledge-base/project/specs/feat-one-shot-3019-terraform-drift-deploy-pipeline-fix/tasks.md` (post plan-review).

## Open Code-Review Overlap

None. Verified: this PR introduces no source-file edits, so there are no `Files to Edit` paths to cross-reference against the open `code-review` issue list.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] PR body cites this plan and includes `Ref #3019` (NOT `Closes #3019` — apply runs before merge).
- [ ] PR body cites #2881 as the structural-prevention tracking issue (re-evaluation threshold met).
- [ ] Plan-review run completed; findings either fixed inline or recorded in the PR body.
- [x] Operator confirms via per-command ack that they have read the exact `terraform apply` command (the apply is allowed to run before merge — this is `ops-only-prod-write` and the apply IS the resolution).

### Post-merge (operator)

- [x] `terraform plan -detailed-exitcode` (full graph, no `-target`) returns exit code `0` against `prd_terraform`.
- [x] `terraform state show terraform_data.deploy_pipeline_fix` reports a resource id distinct from `74675a53-97fa-3535-934c-3c709d0fc325` (the pre-drift id from issue #3019 body). New id: `97b8f475-5838-a6b9-d6ff-cfe0b026bf42`.
- [x] Server-side `/usr/local/bin/ci-deploy.sh` SHA256 matches local HEAD (`fc224806…`); `webhook.service` active. (Webhook HTTP probe returns 403 from Cloudflare Access — runbook to be updated; file+systemd check is stronger.)
- [x] Resolution comment posted on #3019 with: triggering PR, old/new resource ids, full-graph plan exit code, webhook smoke-test status.
- [x] `gh issue close 3019` after the resolution comment is posted.
- [x] Comment on #2881 noting threshold reached (9th occurrence), so the `/ship` post-merge gate implementation can be unblocked from re-evaluation criteria.

## Test Strategy

No new automated tests. This is an ops-remediation against a Terraform `terraform_data` provisioner — its correctness is validated by:

1. The pre-apply targeted `terraform plan` matching the issue body exactly (Phase 2.4).
2. The post-apply full-graph `terraform plan` returning exit code `0` (Phase 4.1).
3. The webhook smoke-test (Phase 4.2).
4. The next scheduled drift cron tick (`0 6,18 * * *`) NOT filing a new issue.

The existing `apps/web-platform/infra/ci-deploy.test.sh` (66 cases per PR #3014's commit message) covers the canary-probe behaviour that PR #3014 added; that test suite ran green at #3014 merge.

## Risks

1. **SSH agent forwarding fails mid-apply.** The provisioner uses `agent = true`. If `ssh-add -l` is empty at apply time, the file provisioners hang. **Mitigation:** Phase 2.4 dry-plan does not exercise the provisioner; verify `ssh-add -l` in Phase 2 explicitly.
2. **Operator IP not in Hetzner firewall allowlist.** A drifted ADMIN_IP would cause the SSH provisioner to time out. **Mitigation:** Phase 2.3 verifies, and the runbook routes to `/soleur:admin-ip-refresh` if drift is detected.
3. **Webhook restart brief outage.** The provisioner runs `systemctl restart webhook` after writing the new files. Deploy hooks fired during this <2s window get connection-refused. **Mitigation:** time the apply outside known deploy windows. Acceptable per #2874's resolution (no incidents reported across the previous 8 applies).
4. **`-target` apply skips dependency graph.** `terraform_data.deploy_pipeline_fix` declares `depends_on = [terraform_data.apparmor_bwrap_profile]`. **Mitigation:** apparmor is unchanged; dependency is stable. Phase 4.1's full-graph plan confirms no other resource needs reconciliation.
5. **`hooks.json.tmpl` interpolates `webhook_deploy_secret`.** The plan output marks `triggers_replace` as `(sensitive value)` because the template includes secrets. **Mitigation:** secret is sourced from `prd_terraform` Doppler at apply time — same path the previous 8 applies used; no new secret handling.
6. **No-rollback property.** `terraform apply -target=terraform_data.deploy_pipeline_fix` always replays provisioners; if the new `ci-deploy.sh` has a regression, the next deploy webhook hits the broken script. **Mitigation:** Phase 1.4 runs `ci-deploy.test.sh` (66 cases) locally before the apply; Phase 4.2 webhook smoke-test catches post-apply syntax/runtime breakage; if smoke-test fails, the roll-forward path is editing `ci-deploy.sh`, committing, and re-applying (the same `-target` apply is idempotent for source recovery).
7. **Concurrency with drift cron (`0 6,18 * * *` UTC).** R2 has no S3 conditional writes (`use_lockfile = false` per `main.tf:13`). If the apply window overlaps the drift cron, both jobs may write state — last-writer-wins. **Mitigation:** Phase 2.5 verifies the operator is ≥5 minutes outside the cron windows. If unavoidable, disable the workflow temporarily: `gh workflow disable scheduled-terraform-drift.yml`, apply, then `gh workflow enable scheduled-terraform-drift.yml`.
8. **Targeted apply skips full graph.** HashiCorp docs warn `-target` is "for exceptional circumstances." **Mitigation:** Phase 4.1 mandates a full-graph plan with exit code 0 — this is the load-bearing acceptance criterion that proves no other resources were silently skipped.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with an explicit non-empty reason; preflight Check 6 will pass.
- This is `type: ops-remediation` / `classification: ops-only-prod-write`. Per AGENTS.md: PR body uses `Ref #3019`, NOT `Closes #3019`, because the resolution runs post-merge (`gh issue close 3019` is a separate operator step). `Closes` would auto-close at merge before the apply ran, producing a false-resolved state.
- This plan is the 10th cycle counting #2873 + #2874 as one apply. #2881's re-evaluation criterion #1 (two more drifts after #2873/#2874) is met. The PR body should explicitly mention this so #2881 unblocks for implementation.
- `terraform plan` and `terraform apply` MUST run with `-detailed-exitcode` (or for apply, simply observe the summary line). `terraform_wrapper: false` is required for exit-code 2 to surface (the workflow learned this the hard way — see `.github/workflows/scheduled-terraform-drift.yml` lines 36-39).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure state-reconciliation. No code, no UI, no content, no legal, no schema, no marketing surface.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Revert PR #3014 to clear the drift | PR #3014 fixes a separate observability gap (`/dashboard` error.tsx outage gates). Reverting to silence drift would re-open that gap. The drift IS the intended push path for `ci-deploy.sh` updates per `lifecycle.ignore_changes = [user_data]` (#967, #2185). |
| Refactor `terraform_data.deploy_pipeline_fix` to use `null_resource` with explicit `lifecycle.replace_triggered_by` | Would not eliminate drift — same hash function applies. Would also lose the `terraform_data` simplification benefit. |
| Replace SSH provisioner approach with a cloud-init re-run | `hcloud_server.web` has `keep_disk = true` and `ignore_changes = [user_data]` for stable identity (per #967). Re-applying user_data would reformat the disk and lose the workspaces volume mount. |
| Eliminate drift by removing `ignore_changes = [user_data]` | Would force server replacement on every cloud-init edit — destroys `/mnt/data`, kills active sessions, breaks the app. |
| Implement #2881's `/ship` post-merge gate now | Out of scope for this issue — #2881 is a structural prevention. This issue (#3019) is the 9th remediation cycle that proves the threshold for #2881 implementation is reached. Filing #2881 work is the post-merge follow-up, not the in-PR action. |

## Research Insights

**Terraform `-target` apply semantics (HashiCorp docs):**

- `-target` is documented as "intended for exceptional circumstances" and "not part of the routine workflow." Mandatory follow-up: a full-graph `terraform plan` (Phase 4.1) to confirm no other resources were silently skipped or left in a pending state.
- `-target=terraform_data.deploy_pipeline_fix` includes the resource AND its `depends_on` (here: `terraform_data.apparmor_bwrap_profile`). If apparmor needed reconciliation, it would be applied first. Verified clean via plan output (#3019 body shows apparmor `Refreshing state...` only).
- Provisioners ALWAYS run on resource creation. `terraform_data` resource replacement = destroy old, create new = re-run all 4 file provisioners + 1 remote-exec block.

**R2-as-S3 Terraform backend constraints (per `main.tf:5-15`):**

- `use_lockfile = false` because Cloudflare R2 lacks S3 conditional writes (PutObject with `If-Match`). Concurrent applies are NOT prevented at the backend layer. The drift cron at 06:00/18:00 UTC + operator's local apply must serialize manually.
- `skip_s3_checksum = true`, `use_path_style = true` are R2 compatibility shims; do not modify.
- AWS env vars (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) are extracted via `doppler secrets get --plain` (NOT through `--name-transformer tf-var`) — the workflow uses two separate Doppler invocations specifically because tf-var name-transform would mangle them into `TF_VAR_AWS_ACCESS_KEY_ID` and break S3 auth.

**`terraform_data` provisioner idempotency:**

- File provisioners (4× `provisioner "file"`) overwrite destination — idempotent.
- `remote-exec` inline (`server.tf:250-267`): `chmod`, `chown`, `systemctl daemon-reload`, `systemctl restart webhook`, `rm -f /mnt/data/.env`. All idempotent (chmod/chown set absolute mode/owner; daemon-reload + restart are safe to repeat; `rm -f` no-ops on missing file). Partial-failure replay is safe — but the resource id will already have been replaced in state, so the next apply with no source change will be a no-op.
- The `grep -q DOPPLER_CONFIG_DIR /etc/default/webhook-deploy ||` guard (line 261) is the only conditional — idempotent.

**Provider versions verified pinned (`apps/web-platform/infra/.terraform.lock.hcl`):**

- `cloudflare/cloudflare 4.52.7` (constraint `~> 4.0`).
- `hetznercloud/hcloud ~> 1.49`.
- `hashicorp/random 3.8.1` (constraint `~> 3.0`).
- Workflow pins `terraform 1.10.5` with `terraform_wrapper: false` (load-bearing for `-detailed-exitcode` to surface 2 instead of being squashed to 1 by setup-terraform's wrapper).

**Institutional learning applied (`2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`):**

- This is the 9th occurrence of the same drift pattern; the resolution is identical to #2618, #2234, #1899, etc. The learning explicitly characterizes this drift as "a feature" — a deliberate consequence of `lifecycle.ignore_changes = [user_data]` on `hcloud_server.web` plus the `terraform_data` bridge resource.
- The runbook says: targeted apply, post-apply full-graph plan, webhook smoke-test, close issue with old/new resource ids. The plan above follows that runbook exactly.
- #2881's re-evaluation criterion #1 ("two more `infra-drift` issues land with the same `deploy_pipeline_fix` pattern") is met by this incident plus #2873/#2874 (counted as one apply). PR body must call this out explicitly so #2881 unblocks.

**References:**

- HashiCorp `-target` flag docs: <https://developer.hashicorp.com/terraform/cli/commands/plan#resource-targeting>
- Terraform `terraform_data` resource: <https://developer.hashicorp.com/terraform/language/resources/terraform-data>
- R2 + Terraform backend constraints: `apps/web-platform/infra/main.tf:5-15` (inline comment cites lack of S3 conditional writes)
- Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`
- Learning: `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`
- Prior apply pattern (load-bearing reference): #2874 resolution comment (`terraform apply -target=terraform_data.deploy_pipeline_fix`, full-graph plan exit 0, webhook 200).

## Implementation Notes

- The bare repo / worktree convention applies: this work happens on branch `feat-one-shot-3019-terraform-drift-deploy-pipeline-fix` in worktree `.worktrees/feat-one-shot-3019-terraform-drift-deploy-pipeline-fix/`.
- Per AGENTS.md `hr-the-bash-tool-runs-in-a-non-interactive`, agent shells cannot satisfy interactive `terraform apply` confirmation. `-auto-approve` is gated by per-command operator ack (the load-bearing safety net). Operator reads the exact command in Phase 3, types "yes" in chat, agent runs.
- The `/soleur:work` skill should NOT TDD this plan — `cq-write-failing-tests-before` exempts infrastructure-only tasks (config, CI, scaffolding). This is an ops-remediation against existing tested infra.
