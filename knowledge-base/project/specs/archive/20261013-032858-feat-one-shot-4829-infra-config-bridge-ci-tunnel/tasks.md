---
title: "Tasks — infra: CI-automate the infra-config handler bridge via Cloudflare Tunnel SSH"
issue: 4829
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-infra-ci-automate-infra-config-handler-bridge-via-tunnel-ssh-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — feat-one-shot-4829-infra-config-bridge-ci-tunnel

Derived from the finalized (deepened) plan. Implement in order — Phase 0 is load-bearing
(the bootstrap-ordering precondition + CLI/contract probes gate the rest).

## Phase 0 — Preconditions (verify before any edit)

- [ ] 0.1 Confirm tunnel SSH infra exists on `origin/main`: `git show origin/main:apps/web-platform/infra/tunnel.tf | grep -E 'access_application" "ssh"|service_token" "ci_ssh"|ssh://localhost:22'` → 3 matches.
- [ ] 0.2 Confirm `CI_SSH_ACCESS_TOKEN_ID/_SECRET` synced to Doppler (read-only): non-empty value. If empty, the bridge degrades to the operator-local fallback until apply-web-platform-infra.yml:397-432 has run.
- [ ] 0.3 Probe `cloudflared access tcp --help` and pin verified flags (`--hostname`, `--url`) + service-token env-var names (`TUNNEL_SERVICE_TOKEN_ID/_SECRET`) into the workflow step (CLI-verification gate).
- [ ] 0.4 **(P0 bootstrap-ordering)** Confirm the live host trusts the current CI key: `tls_private_key.ci_ssh` in state + `DEPLOY_SSH_PRIVATE_KEY` non-empty in Doppler. If the key rotated since the last full apply, the host has a stale pubkey → first CI apply fails `Permission denied (publickey)`. Not auto-healable from CI. Document as a one-time PR-body precondition (AC17).
- [ ] 0.5 Read `apps/web-platform/infra/server.tf:300-442` + `variables.tf` in full before editing.

## Phase 1 — Terraform: dual-context connection (RED→GREEN)

- [ ] 1.1 Add `variable "ci_ssh_private_key"` to `variables.tf` (type string, default null, sensitive). [AC2]
- [ ] 1.2 Rewrite the bridge `connection` block (server.tf:362-367): add `private_key = var.ci_ssh_private_key` + `agent = var.ci_ssh_private_key == null`. NOVEL pattern — no sibling precedent; `terraform validate` is the gate. [AC1]
- [ ] 1.3 Rewrite the two comment blocks (server.tf:339-342 RUNNER-EGRESS CAVEAT; server.tf:461-470 deploy_pipeline_fix depends_on rationale) to describe tunnel-based CI access. Do NOT add a `depends_on` on the bridge. [AC7]
- [ ] 1.4 `terraform fmt` + `terraform init -backend=false` + `terraform validate`. Confirm operator-local path (var unset → private_key=null + agent=true) is byte-equivalent to today's behavior via a dry `terraform plan`. [AC10]

## Phase 2 — Workflow: cloudflared + iptables bridge

- [ ] 2.1 Resolve `SERVER_IP` via `terraform output -raw server_ip` (output exists, outputs.tf:1). Fail-closed if empty (security: never run an unscoped iptables REDIRECT).
- [ ] 2.2 Decode `DEPLOY_SSH_PRIVATE_KEY` from Doppler, `add-mask`, write to `TF_VAR_ci_ssh_private_key` env (NOT on the command line). [AC6]
- [ ] 2.3 Install `cloudflared`; open `cloudflared access tcp --hostname ssh.${APP_DOMAIN_BASE} --url 127.0.0.1:2222` in background carrying the service token; bounded wait (≤30s) for 127.0.0.1:2222, fail-loud on timeout. [AC3]
- [ ] 2.4 `sudo iptables -t nat -A OUTPUT -d "$SERVER_IP" -p tcp --dport 22 -j REDIRECT --to-ports 2222` (scoped to `-d SERVER_IP`). [AC3]
- [ ] 2.5 Add `-target=terraform_data.infra_config_handler_bootstrap` to BOTH plan + apply steps. [AC5]
- [ ] 2.6 `if: always()` teardown: delete the iptables rule + kill cloudflared. [AC4]
- [ ] 2.7 Add `apps/web-platform/infra/infra-config-install.sh` to the workflow `paths:` filter. [AC: Phase 4 / install-helper auto-fire]

## Phase 3 — Ship skill: remove operator-only framing + in-session detection

- [ ] 3.1 In ship/SKILL.md Deploy Pipeline Fix Drift Gate, add `infra_config_handler_bootstrap` to the auto-apply narrative (now CI-applied, no longer operator-only). [AC11]
- [ ] 3.2 Add in-session-apply detection: `[[ -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" ]]` AND `ssh-add -l` lists the deploy key → apply in-session (interactive terraform prompt, NOT `-auto-approve`) + no-host-login `/hooks/infra-config-status` verify. Rare-fallback only. [AC11, AC12, AC13]
- [ ] 3.3 **Gate-array audit:** decide whether to add `infra-config-install.sh` to `DEPLOY_PIPELINE_FIX_TRIGGERS` (SKILL.md:626-637) + `DPF_REGEX` + `ship-deploy-pipeline-fix-gate.test.ts` `TRIGGER_FILES`. If added, keep all four + server.tf in lockstep in the same commit (test auto-detects drift, #3068).

## Phase 4 — Verification

- [ ] 4.1 `cd apps/web-platform/infra && terraform fmt -check && terraform validate`. [AC10]
- [ ] 4.2 `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` green (update fixture only if 3.3 added the helper). 
- [ ] 4.3 `actionlint .github/workflows/apply-deploy-pipeline-fix.yml`; `bash -c '<extracted run snippet>'` for new shell steps (NOT `bash -n` on the .yml).
- [ ] 4.4 Run AC1–AC13 + AC17 verification greps; confirm `git diff origin/main...HEAD -- apps/web-platform/infra/firewall.tf` is empty (AC8) and `grep -c 'target=...infra_config_handler_bootstrap' apply-web-platform-infra.yml` == 0 (AC9).

## Phase 5 — Ship

- [ ] 5.1 PR body: `Closes #4829`; remove `deferred-automation` label at merge; state the AC17 bootstrap-ordering precondition. [AC16, AC17]
- [ ] 5.2 Post-merge (automated): `apply-deploy-pipeline-fix.yml` fires, opens the tunnel, applies the bridge; verify the run is green + `files_written == files_total` + the bridge's remote-exec assertions pass. [AC14, AC15]
