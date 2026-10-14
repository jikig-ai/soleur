---
feature: ci-tunnel-apply-generalize
issue: 4844
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-06-02
brainstorm: knowledge-base/project/brainstorms/2026-06-02-ci-tunnel-apply-generalize-brainstorm.md
---

# Spec — Generalize the CF Tunnel CI-apply pattern to the 7 on-host hardening resources

## Problem Statement

PR #4830 (merged) proved that GitHub CI can SSH to the prod Hetzner host over the existing
Cloudflare Tunnel (via an inline `cloudflared access tcp` + `iptables -t nat OUTPUT REDIRECT`
bridge authenticated by the `ci_ssh` CF Access service token) and auto-apply on-host
`terraform_data.*` provisioners — even though the GitHub runner egress IP is not in
`var.admin_ips`. That bridge currently lives **inline in `apply-deploy-pipeline-fix.yml`** and
only `-target`s 2 resources (`deploy_pipeline_fix`, `infra_config_handler_bootstrap`).

The **7 sibling on-host SSH-provisioned resources** in `apps/web-platform/infra/server.tf`
(`disk_monitor_install`, `resource_monitor_install`, `fail2ban_tuning`, `journald_persistent`,
`docker_seccomp_config`, `apparmor_bwrap_profile`, `orphan_reaper_install`) remain **excluded**
from per-PR CI apply. When one changes, it merges green and **drifts** until the detect-only
`scheduled-terraform-drift.yml` files a GitHub issue telling a human to run `terraform apply`
locally — an action Soleur's non-technical target operator structurally cannot perform. This is
the same admin-applied-not-CI dormancy class that #4827/#4811 exposed.

## Goals

- G1. Eliminate the drift-then-operator-block path for the 7 hardening resources by
  auto-applying them on merge over the tunnel.
- G2. Factor the proven bridge into a reusable, single-source-of-truth composite action so the
  mechanism is maintained in one place (one SHA-pin bump point).
- G3. Close the unguarded `-target` allowlist drift surface so a future resource added to
  `server.tf` cannot silently fail to apply.
- G4. Keep operator-local `terraform apply` byte-equivalent (dual-context connection block).

## Non-Goals

- NG1. **Part 3 (auto-apply drift detector)** — converting `scheduled-terraform-drift.yml` from
  detect-only to apply-over-tunnel. Deferred to a separate PR + ADR (tracked issue).
- NG2. `terraform_data.root_authorized_keys` (`ci-ssh-key.tf`) stays operator-local — it puts
  the CI key on the host and cannot self-heal from CI (firewall chicken-and-egg). One-time
  per-key-rotation bootstrap, not a per-change step.
- NG3. No change to `var.admin_ips` (the firewall) — the tunnel is the access path.
- NG4. No new Doppler tokens (part 2 inherits the existing read + two-token write model).

## Functional Requirements

- FR1. A composite action `.github/actions/cf-tunnel-ssh-bridge/` performs the bridge **setup**:
  SHA-pinned `cloudflared` install, Doppler pull of `CI_SSH_ACCESS_TOKEN_ID/SECRET`, decode of
  the CI key into `TF_VAR_ci_ssh_private_key`, `cloudflared access tcp` 127.0.0.1:2222 forward,
  15s readiness wait, and the `iptables -t nat OUTPUT REDIRECT` rule. Secrets are declared as
  explicit `inputs:` (caller forwards `${{ secrets.X }}`) and re-exported to `env:` inside the
  step. Per-line `::add-mask::` of the SSH key is preserved.
- FR2. The bridge **teardown** remains a caller-side `if: always()` step (deletes the NAT rule,
  kills cloudflared, dumps the log). Its presence is enforced by a workflow lint/test.
- FR3. `apply-deploy-pipeline-fix.yml` is rewired to consume the composite action (no behavior
  change) — proving the extraction before part 2 depends on it.
- FR4. The 7 sibling `terraform_data.*` resources are converted from the agent-only connection
  block to the dual-context shape: `private_key = var.ci_ssh_private_key` +
  `agent = var.ci_ssh_private_key == null`.
- FR5. The 7 resources are appended to `apply-web-platform-infra.yml`'s `-target=` set, with the
  bridge live during **both** the plan and the apply step.
- FR6. A parity-guard test asserts every SSH-provisioned `terraform_data.*` resource in
  `server.tf` appears in the apply workflow's `-target=` set (self-healing direction, modeled on
  `ship-deploy-pipeline-fix-gate.test.ts`).
- FR7. The stale header comment in `apply-web-platform-infra.yml` (the "land via
  apply-deploy-pipeline-fix.yml" claim) is corrected to reflect the new apply path.

## Technical Requirements

- TR1. Bridge mechanism MUST remain iptables `-t nat OUTPUT REDIRECT` — Terraform's Go SSH
  client ignores `~/.ssh/config`/`/etc/hosts`; client-side-config bridges are a dead end.
- TR2. AWS/R2 backend creds MUST be extracted via `doppler secrets get --plain` into env BEFORE
  any `doppler run --name-transformer tf-var` invocation (tf-var transformer clobbers `AWS_*`).
- TR3. `terraform_wrapper: false` MUST be set on any setup-terraform used with `-detailed-exitcode`/
  `doppler run`. Randomize `$GITHUB_OUTPUT` heredoc delimiters.
- TR4. CODEOWNERS MUST cover `.github/workflows/`, `apps/web-platform/infra/*.tf`, and the
  hardening profile files (`seccomp-bwrap.json`, `apparmor-soleur-bwrap.profile`,
  `fail2ban-sshd.local`) — the reviewed merge is the only human checkpoint. Verify; add if absent.
- TR5. Do NOT run `actionlint` against `action.yml` (different schema).
- TR6. The CI SSH key delivered into the dual-context block MUST be unencrypted (passphrase keys
  fail opaquely in Terraform's `private_key = file()` path).
- TR7. The apply path MUST assert the on-host landed-artifact invariant where observable, not
  merely terraform exit-0 (false-success across trigger-and-forget).

## Acceptance Criteria

- AC1. Editing any of the 7 hardening resource files (e.g. `fail2ban-sshd.local`) and merging
  results in the change auto-applying to the prod host with no operator-local `terraform apply`.
- AC2. `apply-deploy-pipeline-fix.yml` still applies `deploy_pipeline_fix` +
  `infra_config_handler_bootstrap` via the extracted composite action (regression-free).
- AC3. The parity-guard test FAILS if a `terraform_data.*` SSH resource is added to `server.tf`
  without a matching `-target=` line.
- AC4. Operator-local `terraform apply` (key var unset) remains byte-equivalent (uses ssh-agent).
- AC5. Multi-agent review passes (single-user-incident threshold class) before merge.

## Risks & Guardrails

- Hardening files become CI-writable → CODEOWNERS + branch protection is the replacement
  checkpoint (TR4). Blast radius is MEDIUM: credential radius is unchanged (root already
  reachable via the live bridge), but the human-at-terminal checkpoint is replaced by the merge.
- `apparmor_bwrap_profile` `depends_on` coupling (server.tf:502) is resolved incidentally by FR4.
- Deferred part 3 carries the x==x tautology + unattended-prod-write risk; see the tracked issue.
