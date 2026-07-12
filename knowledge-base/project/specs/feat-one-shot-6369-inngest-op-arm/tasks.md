# Tasks — feat(infra): no-SSH op=arm for the inngest cutover Doppler arm-flip (#6369)

lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-07-12-feat-inngest-op-arm-no-ssh-doppler-arm-flip-plan.md

> Authoritative source is the plan. The `## Deepen-Plan Findings & Required Changes` (D1-D7) SUPERSEDE the earlier phase/AC text where they conflict — encode the deepen versions.

## Phase 0 — Preconditions (verify, no code)
- [x] 0.1 Verify the Doppler read-path: can the workflow's prd_terraform `DOPPLER_TOKEN` read the source values? Decide read-through vs. mirror-into-readable-config for HEARTBEAT_URL. Record the verified path in the spec.
- [x] 0.2 Confirm the `iac-routing-ack` opt-out for op=arm YAML + runbook edits (they contain the Doppler-write literal). Every such Write/Edit carries `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`.
- [x] 0.3 Confirm `doppler_project.inngest` + `doppler_environment.inngest_prd` are in tfstate (create-only `-target` no-op).

## Phase 1 — Terraform: write token + GitHub Environment secret (D5)
- [x] 1.1 Create `apps/web-platform/infra/inngest-arm-write-token.tf`: `doppler_service_token.inngest_arm_write` (read/write, by-reference project/config, name `inngest-cutover-arm`) + `github_repository_environment "inngest_cutover"` (required reviewer) + `github_actions_environment_secret.doppler_token_inngest_arm` (NOT repo-wide). No `ignore_changes`. Header documents blast-radius (incl. armed prod DSN), rotation, transitivity note (precedent `.inngest`, re-provision ordering), post-cutover revoke.
- [x] 1.2 Add `-target=` lines for the token + env secret (+ env resource) to the per-merge default allow-list in `.github/workflows/apply-web-platform-infra.yml` (near :356-357). NOT the `inngest_host` set; NOT any `OPERATOR_APPLIED_*_EXCLUSIONS`.
- [x] 1.3 `terraform validate` (confirm the github provider exposes `github_repository_environment`/`github_actions_environment_secret`) + `terraform plan` (canonical triplet + raw R2 exports) → create-only, `0 change, 0 destroy`, no transitive host/project/env create.
- [x] 1.4 Confirm `plugins/soleur/test/terraform-target-parity.test.ts` passes UNMODIFIED + destroy-guard counter unchanged.

## Phase 2 — POSTGRES_URI source seed (one-time, narrow) (D6)
- [x] 2.1 Document the one-time seed of `INNGEST_POSTGRES_URI_PROD` into a NARROW CI-readable config (NOT prd_terraform), via Doppler-write stdin — not a TF resource. Only human secret step, pre-window.
- [x] 2.2 Add the rotation co-update (password rotation must re-seed) + a value-silent pre-window freshness assertion (seed == target).
- [x] 2.3 HEARTBEAT_URL: prefer read-through; fallback mirror lands in the CI-readable config (not soleur-inngest/prd).

## Phase 3 — op=arm workflow verb, FORWARD-ONLY (D1-D4)
- [x] 3.1 Add `arm` to the `op` choice options (:22-32). NO `flip_state` input.
- [x] 3.2 Job env conditional `DOPPLER_TOKEN_INNGEST_ARM: ${{ inputs.op == 'arm' && secrets.DOPPLER_TOKEN_INNGEST_ARM || '' }}` + `environment: inngest-cutover` on the job (D5).
- [x] 3.3 `arm)` case (template op=quiesce-web; pure Doppler, no webhook): G1 pre-write FSM-state guard (refuse unless ∈ {unset,empty,aborted,rolled-back}) → G2 read+mask each value on its own line → G3 positive prod-URI assertion (PG != dark, contains prod host, reject empty/:6543, value-silent) → G4 write POSTGRES_URI then HEARTBEAT_URL (stdin, exit-gated) → G5 write `armed` last → G6 time-bounded single-state-token Better Stack confirm, branch on done/aborted/rolled-back/timeout.
- [x] 3.4 Update `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: non-empty awk range assert; no value-echo; no `jq .` raw-row; no `set -x`; `::add-mask::` per value; `-p soleur-inngest -c prd`; stdin form; no ssh; G1+G3 present; conditional env + `environment:`.

## Phase 4 — SEAM removal + rollback write in op=rollback + runbook (D1, D6)
- [x] 4.1 op=execute SEAM (:607-611) → point 2.2b/2.3 to `op=arm`; keep 2.2a/2.4; update :602-604 comment.
- [x] 4.2 Fold `INNGEST_CUTOVER_FLIP=rollback` write into existing `op=rollback` (:890) with G1' guard (∈ {flipping,flushed,done}) + conditional env + environment gate + time-bounded `rolled-back` confirm; update :614 SEAM text. Rollback writes ONLY the flip value.
- [x] 4.3 Runbook `inngest-server.md`: rewrite 2.2b/2.3 SEAM to op=arm; add one-time seed precondition + rotation co-update; add post-cutover token-revoke + seed-delete; update SEAM/operator marker count.

## Phase 5 — End-to-end assembly + dry-run
- [x] 5.1 Assemble the full no-SSH op order in the runbook; flag 2.2a + 2.4 as the ONLY non-dispatch steps.
- [x] 5.2 Dry-run validation (no live cutover): op reachability + op=arm read/mask/guard against dark/scratch key (no `armed` write) + time-bounded confirm parses a fresh synthetic `done` and rejects a stale one.
- [x] 5.3 Note: live prod cutover is operator-gated, NOT an autonomous /work step.

## Phase 6 — ADR + C4
- [x] 6.1 Amend ADR-100 with Decision 6b (boundary delta = first CI read/write token into soleur-inngest; both reconciliations; dispatch+environment IS the ack, no interactive value confirmation; ordinal = amendment).
- [x] 6.2 C4: read all three .c4 files; record the no-edit enumeration (or add the ci→doppler edge + run c4 tests if the ADR reviewer judges it material).

## Acceptance gate
- [x] All AC1-AC14 (pre-merge) green; AC15-AC17 documented as post-merge/operator. CPO sign-off obtained (requires_cpo_signoff). Test scenarios T1-T11 + T-D2..T-D5 implemented.
