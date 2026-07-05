---
title: "Tasks — fix bot synthetic check-names drift (#6049)"
plan: knowledge-base/project/plans/2026-07-05-fix-bot-synthetic-check-names-drift-plan.md
issue: 6049
lane: single-domain
brand_survival_threshold: single-user incident
---

# Tasks — bot synthetic check-runs vs CI Required ruleset (#6049)

## Phase 0 — Preconditions
- [ ] 0.1 Re-confirm live CI Required (17 contexts) via `gh api repos/:owner/:repo/rulesets/14145388`.
- [ ] 0.2 Confirm `origin/main:infra/github/ruleset-ci-required.tf` lacks `adr-ordinals`.
- [ ] 0.3 Read T-rsc-9 in `tests/scripts/test-audit-ruleset-bypass.sh` (`.tf`↔canonical lockstep shape).
- [ ] 0.4 Lift `GITLEAKS_VERSION`/SHA256 pin from `.github/workflows/secret-scan.yml:82-84`.
- [ ] 0.5 Confirm CODEOWNERS gates `infra/github/**` (@deruelle → PR needs code-owner approval).

## Phase 1 — IaC reconciliation (adr-ordinals)
- [ ] 1.1 Add `required_check { context = "adr-ordinals"; integration_id = var.actions_integration_id }` to `infra/github/ruleset-ci-required.tf`.
- [ ] 1.2 Add `{ "context": "adr-ordinals", "integration_id": 15368 }` to `scripts/ci-required-ruleset-canonical-required-status-checks.json`.
- [ ] 1.3 `terraform -chdir=infra/github validate`; confirm plan is a no-op vs live (documented, not applied).

## Phase 2 — Complete the synthetic SSOT
- [ ] 2.1 Add the 10 missing contexts to `scripts/required-checks.txt` (gitleaks scan, lint fixture content, allowlist-diff (.gitleaks.toml paths surface), rename-guard (allowlist destinations), waiver discipline (issue:#NNN trailer), Bash fixture tests for guard scripts, lockfile-sync, service-role-allowlist-gate, tc-document-sha-guard, adr-ordinals), grouped/commented like existing entries.
- [ ] 2.2 Preserve the `CodeQL` intentional-omission comment block verbatim.

## Phase 3 — Action derives CHECK_NAMES from the SSOT
- [ ] 3.1 Replace hardcoded `CHECK_NAMES=(...)` (`action.yml:168`) with a read of `scripts/required-checks.txt` reusing the `lint-bot-synthetic-completeness.sh:42-57` parser (leading/trailing trim only, single-quote strip, multi-word safe).
- [ ] 3.2 Post one 15368 check-run per name; `case` special-cases `cla-check`/`cla-evidence` custom outputs; no double-post.
- [ ] 3.3 Update the action `CHANGELOG.md` (v3).

## Phase 4 — Secret-safety ceiling (Tier 2, CORE)
- [ ] 4.1 Add a real-gitleaks step (pinned == secret-scan.yml, repo `.gitleaks.toml`, `--redact`) over the staged/committed diff before posting; hit → fail loud, no PR, no synthetics.
- [ ] 4.2 Assert every `add-paths` entry is within a `knowledge-base/**` markdown safe-surface allowlist; escape → fail loud.
- [ ] 4.3 Guard the gitleaks pin against divergence (cross-site parity: secret-scan.yml + ci.yml test-scripts + action).
- [ ] 4.4 (If security-sentinel/advisor downgrade to Tier 1) swap the real-gitleaks step for allowlist + push-protection note; keep 4.2.

## Phase 5 — Drift-proof tests
- [ ] 5.1 New `plugins/soleur/test/required-checks-canonical-parity.test.sh`: `required-checks.txt` CI-subset ≡ canonical contexts filtered to `integration_id == 15368` (jq, not a `CodeQL` literal), asserted BOTH ⊆ and ⊇ (set compare, multi-word safe, regex-escaped).
- [ ] 5.2 Close the composite blind spot: extend `lint-bot-synthetic-completeness.sh` (assert the action reads `required-checks.txt`) + add a regression case to `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh`.
- [ ] 5.3 Confirm `scripts/test-all.sh` picks up the new `.test.sh` in the `ci.yml` `test-scripts` job.

## Phase 6 — ADR + C4
- [ ] 6.1 Amend `ADR-032-github-branch-protection-as-iac.md` (drift-chain contract, adr-ordinals reconcile, SSOT-derived CHECK_NAMES, real-gitleaks ceiling).
- [ ] 6.2 C4 completeness read (model.c4/views.c4/spec.c4) → record "no C4 impact" with the external-actor/system/access enumeration.

## Verification
- [ ] V1 `bash scripts/lint-bot-synthetic-completeness.sh` green.
- [ ] V2 Full `scripts/test-all.sh` (or the `test-scripts` shard) green incl. new parity test + T-rsc-9.
- [ ] V3 `terraform -chdir=infra/github validate` green; no-op plan documented.
- [ ] V4 Confirm no `apps/web-platform/**` files changed (typecheck N/A).
- [ ] V5 PR body `Closes #6049`; pre/post-merge AC split; @deruelle code-owner review noted.
