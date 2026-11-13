---
title: "feat(infra): build the new inngest write path (epic #9927 step D2-2; Ref #12158)"
date: 2026-11-13
slug: inngest-new-write-path-12158
branch: feat-one-shot-9927-d2-2-new-write-path
issue: 12158
---

## Overview

Epic #9927 sequence step **D2-2**: build and prove the new write path for `op=rollback` and `op=resume`, per the authoritative design `knowledge-base/project/specs/archive/20261106-103523-feat-one-shot-9927-record-owner-decisions-a6-refresh/arm-token-replacement-design-12158.md` and CTO rulings D1, D1b, D1c, D2 (recorded in `decision-challenges.md` of the same folder). Neither verb is retired. The arm token (`doppler_service_token.inngest_arm_write`, repo secret `DOPPLER_TOKEN_INNGEST_ARM`) stays live and in config until step 4's owner-gated revoke change — nothing is removed or revoked here.

The design, verbatim in effect:

- A **new Terraform-declared read/write `doppler_service_token`** on the isolated `soleur-inngest/prd` config, name distinct from `inngest-cutover-arm`, project/config by reference exactly as the arm and flip-read tokens do.
- Its key is **not** a `github_actions_secret` or `github_actions_environment_secret` (the TF GitHub App cannot write environment secrets — the 403 the file already records). It surfaces only as a `sensitive = true` Terraform output.
- A **staged relay script** (operator-bootstrap contract, ADR-264) copies the key with `terraform output -raw` into the `inngest-cutover` GitHub **environment secret** `DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE` over stdin — never echoed, xtrace refused.
- `cutover-inngest.yml` exports that environment secret **only** on the `rollback`/`resume` dispatch arms (the same `if:`/ternary pin shape as the arm token), and a first credential step does an authenticated Doppler read that refuses `verdict=write_token_stale` when the secret is unset or stale (fail closed; a `-replace` mints a new key and strands the environment secret, so the runbook says replace-then-relay).
- `scripts/cutover-inngest.sh` consumes `DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE` for all eight authenticated call sites in the `rollback)`/`resume)` arms.
- The Tier-B census gains an **environment-scoped-name clause**: the new name appears only in `cutover-inngest.yml`, only in steps limited to rollback or resume, never in `.github/actions/infra-credentials/action.yml`, and joins the env-secret registry so any job naming it without a Tier-B `environment:` reads red.
- The new token gets its own **revisit coverage** (tracker #12738 + a date-only config probe mirroring `arm-token-revisit-12229.sh`, enrolled post-merge); the existing probe keeps watching only the arm token.
- The **ADR-241 amendment log** gains an entry: the environment secret conforms to D2 and removes the advisory deviation class the repo-scoped arm/flip-read secrets carry.
- The **runbook** records the stale-secret recovery (a `-replace` strands the environment secret: re-run the relay, then re-dispatch) and the new delivery path.

## Pre-conditions verified

- Host replace + `op=resume` completed 2026-11-13 on iid=175859399 (apply runs 43115757996, 43265237672; resume run 43265987806) — the design's step 1 is done, so step 2 may land (the dispatch-SHA concern no longer blocks: the window passed).
- `DOPPLER_TOKEN_INFRA_PRIVILEGED` is present on the `inngest-cutover` environment (verified by `gh api .../environments/inngest-cutover/secrets` on 2026-11-13 — the design's "check at build" item).
- The census/credential-tiers record does not require every environment secret registered by name; the census classifies Tier-B by `secrets.<ENV_SECRETS member>` reference, so registering the new name there IS the required clause.
- The apply on merge creates the token resource — the owner-authorized act for this step (owner go granted in-session for D2 step 2).

## Acceptance Criteria

1. `doppler_service_token.inngest_cutover_write` (`name = "inngest-cutover-write"`, `access = "read/write"`, project/config by reference) exists in `inngest-arm-write-token.tf` with a `sensitive = true` output `inngest_cutover_write_token`, and a `-target` line in `apply-web-platform-infra.yml` beside the arm-token lines.
2. No `github_actions_secret` or `github_actions_environment_secret` resource carries the new key (static grep pin).
3. `cutover-inngest.yml`: `secrets.DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE` appears exactly once (the scoped env ternary), only on an `if: inputs.op == 'rollback' || inputs.op == 'resume'` step; the write-token freshness check step runs an authenticated Doppler read before the run step and refuses with `write_token_stale` on empty or failed auth. The Tier-B loader step stays `if: inputs.op == 'backup'`; no op arm combines the loader with the new secret. The arm export step is unchanged (dropped only at step 4).
4. `scripts/cutover-inngest.sh` `rollback)`/`resume)` arms use `DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE` for every authenticated call; the empty-token refusals name the environment secret and the relay remedy.
5. The relay script exists at `knowledge-base/project/specs/feat-one-shot-9927-d2-2-new-write-path/relay-inngest-write-token.sh`, carries the generated-operator-script v2 contract (xtrace refusal above everything, `--list` static, staged read/write classes), reads `terraform output -raw inngest_cutover_write_token`, and pipes to `gh secret set --env inngest-cutover` on stdin with no echo; a registered test pins the script text.
6. The census (`tests/scripts/test-infra-privileged-tier-census.sh`) registers the new name as environment-scoped and pins its confinement (only `cutover-inngest.yml`, only rollback/resume-gated steps, never the loader); `DOPPLER_TOKEN_INNGEST_ARM` stays in `REPO_SCOPED_PRIV` until the revoke change.
7. `cutover-inngest-workflow.test.sh` pins the new secret's consumption and the staleness check; `_EXACT_FLOOR` is bumped by the measured delta.
8. `scripts/followthroughs/inngest-write-token-revisit-12738.sh` + its `.test.sh` exist (date-only config probe; members: the `-target` line and the `resource "doppler_service_token" "inngest_cutover_write"` declaration; exits 2/3/5, never 0/1), registered per D3-r2a (run_suite + shard-legs + durations rows only).
9. ADR-241 amendment log gains the D2-conformance entry; `inngest-server.md` records the delivery path and the replace-then-relay recovery.
10. After merge: the apply run's plan/apply output names `doppler_service_token.inngest_cutover_write` as created (resource names only, never a value), and tracker #12738 gets its directive + follow-through label.

## Operator Constraints

- The merge-apply that mints the token is owner-authorized (in-session go for D2 step 2).
- Running the relay script (seeds the environment secret) and any live proof (a gated `op=resume`/`op=rollback` run, or an authenticated read/write API check) are the NEXT owner-go asks — this PR stops at merge.
- No removal/revoke of the arm token, its secret, its `-target` lines or its export step (step 4).
- Never print token values; resource and secret names only.

## Test plan

- `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`
- `bash tests/scripts/test-infra-privileged-tier-census.sh`
- `bash scripts/followthroughs/inngest-write-token-revisit-12738.test.sh`
- `bash tests/scripts/test-relay-inngest-write-token-12158.sh`
- `npx tsx plugins/soleur/test/terraform-target-parity.test.ts` (or the repo's runner)
- `bash scripts/test-all.sh --print-selection` on the diff to confirm suite coverage, then the affected set.
