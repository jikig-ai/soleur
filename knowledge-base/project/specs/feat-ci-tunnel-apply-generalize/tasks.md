---
feature: ci-tunnel-apply-generalize
issue: 4844
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-02-feat-ci-tunnel-apply-generalize-plan.md
---

# Tasks — Generalize CF Tunnel CI-apply (parts 1+2, #4844)

## Phase 0 — Preconditions (no edits)
- [x] 0.1 Confirm `var.ci_ssh_private_key` declared + unencrypted (used by `infra_config_handler_bootstrap`) — variables.tf:121 (sensitive=true, default=null)
- [x] 0.2 Confirm test discovery: `scripts/test-all.sh` runs `bun test plugins/soleur/`
- [x] 0.3 Re-confirm the 7 sibling connection-block line numbers before editing — all match (76-81,114-119,151-156,226-231,572-577,608-613,635-640); all byte-identical `agent = true`

## Phase 1 — Composite action (contract)
- [x] 1.1 Create `.github/actions/cf-tunnel-ssh-bridge/action.yml` (`using: composite`), setup steps extracted from `apply-deploy-pipeline-fix.yml` L182-309
- [x] 1.2 Declare secrets as `inputs:` (`doppler-token`, `infra-dir`, `cloudflared-version`, `cloudflared-sha256`); re-export to `env:` per step
- [x] 1.3 Export `SERVER_IP`/`CLOUDFLARED_PID`/`TF_VAR_ci_ssh_private_key`/`TUNNEL_SERVICE_TOKEN_ID/_SECRET` to `$GITHUB_ENV`
- [x] 1.4 Header comments: SHA-recompute discipline + caller-side `if: always()` teardown contract with `-n` guards (NO README)

## Phase 2 — Rewire apply-deploy-pipeline-fix.yml (no behavior change)
- [x] 2.1 Replace inline bridge (L182-309) with `uses: ./.github/actions/cf-tunnel-ssh-bridge` + input forwards
- [x] 2.2 Keep the existing `if: always()` teardown (L339-363)
- [x] 2.3 Fix the now-stale CAVEAT comment (L46-54) — apparmor publickey failure resolved by Phase 3
- [x] 2.4 Change concurrency group to the IDENTICAL literal `terraform-apply-web-platform-host` (must byte-match Phase 4.6) — this is the SOLE state serializer since `main.tf:13` `use_lockfile = false` (no R2 lock); keep `cancel-in-progress: false`; add load-bearing comment
- [x] 2.5 In `apps/web-platform/infra/main.tf` add a comment at the `use_lockfile = false` line: shared GHA concurrency group is the load-bearing serializer (no backend lock)
- [x] 2.6 Verify in `action.yml`: `inputs.doppler-token`/SSH-key/CF-token inputs used ONLY in `env:` mappings, never `run:`/`name:` (not auto-masked like secrets.*)

## Phase 3 — server.tf dual-context retrofit (contract)
- [x] 3.1 For each of the 7 sibling connection blocks (L76-81, 114-119, 151-156, 226-231, 572-577, 608-613, 635-640): add `private_key = var.ci_ssh_private_key`, change `agent = true` → `agent = var.ci_ssh_private_key == null`

## Phase 4 — apply-web-platform-infra.yml two-apply token-gated (shape B)
- [x] 4.1 Keep main plan (80 non-SSH targets) + saved-tfplan apply UNCHANGED — do NOT add the 7 here
- [x] 4.2 Add token-presence gate step AFTER post-apply token sync (L397-432): `doppler secrets get CI_SSH_ACCESS_TOKEN_ID` → set `ssh_apply_skip`
- [x] 4.3 Add token-gated SSH-apply step (`if ssh_apply_skip != 'true'`): `uses:` bridge → AWS creds export → `doppler run --name-transformer tf-var -- terraform apply -target=<7 SSH>`
- [x] 4.4 Caller-side `if: always()` teardown with `[[ -n "${SERVER_IP:-}" ]]` / `[[ -n "${CLOUDFLARED_PID:-}" ]]` guards
- [x] 4.4b Comment on the SSH `-target` apply: no destroy-guard needed (jq is Cloudflare-scoped; `terraform_data` has no `when=destroy` provisioner)
- [x] 4.5 Fix stale header comment (L16-27)
- [x] 4.6 Set concurrency group to the IDENTICAL literal `terraform-apply-web-platform-host` (byte-match Phase 2.4 — divergent strings silently fail to serialize); keep `cancel-in-progress: false`

## Phase 5 — Parity-guard test
- [x] 5.1 Create `plugins/soleur/test/terraform-target-parity.test.ts` (`bun:test`)
- [x] 5.2 Glob ALL `apps/web-platform/infra/*.tf`; strip `#` comments before matching (server.tf:305 hazard)
- [x] 5.3 Assert each SSH-provisioned `terraform_data.*` ∈ (web-platform-infra targets ∪ deploy-pipeline-fix targets ∪ `root_authorized_keys` allowlist); sentinel `≥ 9`
- [x] 5.4 Header note: one-directional limitation (stale/typo'd -target uncaught)
- [x] 5.5 Negative test via synthetic in-test fixture string

## Phase 6 — CODEOWNERS
- [x] 6.1 Add `/.github/actions/cf-tunnel-ssh-bridge/ @deruelle` row

## Phase 7 — Verify
- [x] 7.1 `bash scripts/test-all.sh` green (parity + destroy-guard + ship-gate)
- [x] 7.2 `actionlint` the two workflows (NOT action.yml); `bash -c` extracted `run:` snippets
- [x] 7.3 Operator-local `terraform plan` (key var unset) shows no connection-block diff

## Acceptance verification (pre-merge)
- [x] AC1-AC11 per plan (grep/run-checkable). Key: AC7 identical-literal concurrency group in BOTH workflows; AC8 doppler-token only in `env:`; AC9 destroy-guard-omission documented; AC11 confirm `main` branch protection requires CODEOWNERS review (cite ruleset in PR body)

## Post-merge (CI)
- [ ] AC12 `gh run list --workflow=apply-web-platform-infra.yml` conclusion=success
- [ ] AC14 PR body `Ref #4844`; `gh issue close 4844` after AC12
