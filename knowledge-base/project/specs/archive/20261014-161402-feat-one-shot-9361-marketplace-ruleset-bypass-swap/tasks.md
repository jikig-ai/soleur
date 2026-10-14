# Tasks: marketplace ruleset bypass actor swap to soleur-infra (#9361)

Plan: `knowledge-base/project/plans/2026-10-04-fix-marketplace-ruleset-bypass-actor-swap-to-soleur-infra-plan.md`
Branch: `feat-one-shot-9361-marketplace-ruleset-bypass-swap` | Draft PR: #9466 | Refs #9361, #8209 (never Closes)

## Phase 1: Setup (RED first)

- 1.1 `scripts/marketplace-ruleset-canonical-bypass-actors.json`: third actor `3261325` to `5118911`.
- 1.2 `scripts/verify-marketplace-ruleset.test.sh`
  - 1.2.1 baseline fixture third actor `5118911`.
  - 1.2.2 G1.2d value to `166065653` (installation-id typo class).
  - 1.2.3 add G1.2f (soleur-ai added as a 4th actor is rejected); `MIN_ASSERTIONS` 27 to 28, literal stays directly above its `if`.
- 1.3 `tests/scripts/test-audit-ruleset-bypass.sh`: add `T-mp-1d` (4 mutants + real-file positive control + multi-line extra-member must-PASS), register it next to `T-mp-1b`/`T-mp-1c`; fix the stale "soleur-ai Integration" comment.
- 1.4 Run `bash tests/scripts/test-audit-ruleset-bypass.sh`; record that `T-mp-1b` and `T-mp-1d` are RED.

## Phase 2: Core implementation

- 2.1 `infra/github/ruleset-marketplace-pr-required.tf`
  - 2.1.1 third `bypass_actors` block to `5118911` (same position, `Integration`, `always`); comment names soleur-infra, APP id vs installation id 166065653.
  - 2.1.2 `commit_author` / `commit_email` to `soleur-infra[bot]` forms.
  - 2.1.3 `depends_on = [github_repository_ruleset.marketplace_pr_required]` on `github_repository_file.marketplace_manifest`, with the in-place-update ordering comment.
  - 2.1.4 refresh header table, "HONEST STRENGTH CLAIM" (state the residual once: soleur-ai and soleur-infra both hold `administration:write`; Tier-B reach), bypass comment, drop the false "appears twice" `122213433` sentence.
- 2.2 `infra/github/main.tf`: remove the legacy arm (`id`, `installation_id`, `pem_file` read `var.github_infra_app_*` directly); rewrite the two comments; "same modes minus legacy".
- 2.3 `infra/github/README.md`: Phase 0 auth paragraph, one-line "Resolved" known-gap note, rewrite the "coupled by the bypass actor, not by ordering" paragraph, fix the two `TF_VAR_github_app_*` mentions. Small hunks only.
- 2.4 Confirm `T-mp-1b`, `T-mp-1d` and the verifier suite are green.

## Phase 3: Architecture, docs

- 3.1 ADR-241 short dated Amendment-log entry (D5 row unchanged, evidence pending).
- 3.2 `model.c4`: `soleurMarketplace` description and `github -> soleurMarketplace` edge (drop KNOWN GAP and legacy-mode clause); `bash scripts/regenerate-c4-model.sh`.
- 3.3 `infra-credential-tiers-8209.md`: update the dated #9360 note.

## Phase 4: Testing and verification

- 4.1 `terraform -chdir=infra/github init -backend=false -input=false -lockfile=readonly`, `validate`, `fmt -check`.
- 4.2 Scratch probe (INFRA-mode dummy values fail only at PEM parsing; nothing set fails with `app_auth.id must be set...`); paste outputs in the PR body.
- 4.3 Targeted suites only: `scripts/verify-marketplace-ruleset.test.sh`, `tests/scripts/test-audit-ruleset-bypass.sh`, `plugins/soleur/test/c4-model-freshness.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`, `scripts/guard-vacuity-floor.test.sh`.
- 4.4 Confirm no change to `ruleset-ci-required.tf`, `variables.tf`, any `.github/workflows/*`.

## Phase 5: Ship prerequisites

- 5.1 File deferral issues: (1) legacy-mode residue (variables, ADR-032, article-30, other roots); (2) remove `known-gap-9361` annotation (workflow, no agent admin merge); (3) narrow soleur-ai `administration:write` on the marketplace repo; (4) narrow the loader's `GITHUB_INFRA_APP_PRIVATE_KEY` export.
- 5.2 PR body: `Refs #8209`, `Refs #9361`; quote the owner authorization ("ack for all", covering #9361); `User-Impact:` line; installation-permission output; deferral links.
- 5.3 Pre-merge gate: `infra-validation` plan comment, re-read after the last rebase, lists exactly the ruleset and file as in-place updates, 0 destroys.
- 5.4 Merge only without agent `--admin`; do not dispatch any workflow.

## Phase 6: Post-merge (owner-visible)

- 6.1 Run Post-Merge Verification checks 1-5 (run selection by ancestry of the merge SHA; wait with `gh run watch --exit-status`).
- 6.2 Comment evidence on #9361 and #8209; close #9361 only after checks 1-5 pass. #8211 untouched.
- 6.3 On failure follow the plan's recovery decision table (no revert on a post-swap 409; owner go-ahead for any dispatch).
