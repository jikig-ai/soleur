---
feature: ci-tunnel-apply-generalize
issue: 4844
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-02-feat-ci-tunnel-apply-generalize-plan.md
---

# Tasks — Generalize CF Tunnel CI-apply (parts 1+2, #4844)

## Phase 0 — Preconditions (no edits)
- [ ] 0.1 Confirm `var.ci_ssh_private_key` declared + unencrypted (used by `infra_config_handler_bootstrap`)
- [ ] 0.2 Confirm test discovery: `scripts/test-all.sh:168` runs `bun test plugins/soleur/`
- [ ] 0.3 Re-confirm the 7 sibling connection-block line numbers before editing

## Phase 1 — Composite action (contract)
- [ ] 1.1 Create `.github/actions/cf-tunnel-ssh-bridge/action.yml` (`using: composite`), setup steps extracted from `apply-deploy-pipeline-fix.yml` L182-309
- [ ] 1.2 Declare secrets as `inputs:` (`doppler-token`, `infra-dir`, `cloudflared-version`, `cloudflared-sha256`); re-export to `env:` per step
- [ ] 1.3 Export `SERVER_IP`/`CLOUDFLARED_PID`/`TF_VAR_ci_ssh_private_key`/`TUNNEL_SERVICE_TOKEN_ID/_SECRET` to `$GITHUB_ENV`
- [ ] 1.4 Header comments: SHA-recompute discipline + caller-side `if: always()` teardown contract with `-n` guards (NO README)

## Phase 2 — Rewire apply-deploy-pipeline-fix.yml (no behavior change)
- [ ] 2.1 Replace inline bridge (L182-309) with `uses: ./.github/actions/cf-tunnel-ssh-bridge` + input forwards
- [ ] 2.2 Keep the existing `if: always()` teardown (L339-363)
- [ ] 2.3 Fix the now-stale CAVEAT comment (L46-54) — apparmor publickey failure resolved by Phase 3
- [ ] 2.4 Add shared concurrency group (5a) `terraform-apply-web-platform-host`

## Phase 3 — server.tf dual-context retrofit (contract)
- [ ] 3.1 For each of the 7 sibling connection blocks (L76-81, 114-119, 151-156, 226-231, 572-577, 608-613, 635-640): add `private_key = var.ci_ssh_private_key`, change `agent = true` → `agent = var.ci_ssh_private_key == null`

## Phase 4 — apply-web-platform-infra.yml two-apply token-gated (shape B)
- [ ] 4.1 Keep main plan (80 non-SSH targets) + saved-tfplan apply UNCHANGED — do NOT add the 7 here
- [ ] 4.2 Add token-presence gate step AFTER post-apply token sync (L397-432): `doppler secrets get CI_SSH_ACCESS_TOKEN_ID` → set `ssh_apply_skip`
- [ ] 4.3 Add token-gated SSH-apply step (`if ssh_apply_skip != 'true'`): `uses:` bridge → AWS creds export → `doppler run --name-transformer tf-var -- terraform apply -target=<7 SSH>`
- [ ] 4.4 Caller-side `if: always()` teardown with `[[ -n "${SERVER_IP:-}" ]]` / `[[ -n "${CLOUDFLARED_PID:-}" ]]` guards
- [ ] 4.5 Fix stale header comment (L16-27)
- [ ] 4.6 Add shared concurrency group (5a) matching Phase 2.4

## Phase 5 — Parity-guard test
- [ ] 5.1 Create `plugins/soleur/test/terraform-target-parity.test.ts` (`bun:test`)
- [ ] 5.2 Glob ALL `apps/web-platform/infra/*.tf`; strip `#` comments before matching (server.tf:305 hazard)
- [ ] 5.3 Assert each SSH-provisioned `terraform_data.*` ∈ (web-platform-infra targets ∪ deploy-pipeline-fix targets ∪ `root_authorized_keys` allowlist); sentinel `≥ 9`
- [ ] 5.4 Header note: one-directional limitation (stale/typo'd -target uncaught)
- [ ] 5.5 Negative test via synthetic in-test fixture string

## Phase 6 — CODEOWNERS
- [ ] 6.1 Add `/.github/actions/cf-tunnel-ssh-bridge/ @deruelle` row

## Phase 7 — Verify
- [ ] 7.1 `bash scripts/test-all.sh` green (parity + destroy-guard + ship-gate)
- [ ] 7.2 `actionlint` the two workflows (NOT action.yml); `bash -c` extracted `run:` snippets
- [ ] 7.3 Operator-local `terraform plan` (key var unset) shows no connection-block diff

## Acceptance verification (pre-merge)
- [ ] AC1-AC7 per plan (grep/run-checkable)

## Post-merge (CI)
- [ ] AC8 `gh run list --workflow=apply-web-platform-infra.yml` conclusion=success
- [ ] AC10 PR body `Ref #4844`; `gh issue close 4844` after AC8
