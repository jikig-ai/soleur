---
title: "Tasks — fix bot synthetic check-names drift (#6049)"
plan: knowledge-base/project/plans/2026-07-05-fix-bot-synthetic-check-names-drift-plan.md
issue: 6049
lane: single-domain
brand_survival_threshold: single-user incident
---

# Tasks — bot synthetic check-runs vs CI Required ruleset (#6049)

## Phase 0 — Preconditions
- [x] 0.1 Re-confirm live CI Required (17 contexts) via `gh api repos/:owner/:repo/rulesets/14145388`.
- [x] 0.2 Confirm `origin/main:infra/github/ruleset-ci-required.tf` lacks `adr-ordinals`.
- [x] 0.3 Read T-rsc-9 in `tests/scripts/test-audit-ruleset-bypass.sh` (`.tf`↔canonical lockstep shape).
- [x] 0.4 Lift `GITLEAKS_VERSION`/SHA256 pin from `.github/workflows/secret-scan.yml:82-84`.
- [x] 0.5 Confirm CODEOWNERS gates `infra/github/**` (@deruelle → PR needs code-owner approval).

## Phase 1 — IaC reconciliation (adr-ordinals)
- [x] 1.1 Add `required_check { context = "adr-ordinals"; integration_id = var.actions_integration_id }` to `infra/github/ruleset-ci-required.tf` (15368, NOT codeql id).
- [x] 1.2 Add `{ "context": "adr-ordinals", "integration_id": 15368 }` to `scripts/ci-required-ruleset-canonical-required-status-checks.json`.
- [x] 1.3 Bump hardcoded count 16→17: `tests/scripts/test-audit-ruleset-bypass.sh:634` (T-rsc-7 `"16"`) + its `:618-621` prose + `ruleset-ci-required.tf:18` prose.
- [x] 1.4 `terraform -chdir=infra/github validate`; confirm plan is a no-op vs live (documented, not applied).

## Phase 2 — Complete the synthetic SSOT
- [x] 2.1 Add the 10 missing contexts to `scripts/required-checks.txt` (gitleaks scan, lint fixture content, allowlist-diff (.gitleaks.toml paths surface), rename-guard (allowlist destinations), waiver discipline (issue:#NNN trailer), Bash fixture tests for guard scripts, lockfile-sync, service-role-allowlist-gate, tc-document-sha-guard, adr-ordinals), grouped/commented like existing entries.
- [x] 2.2 Preserve the `CodeQL` intentional-omission comment block verbatim.
- [x] 2.3 Add the auto-fabrication guard comment to the file header (adding a name auto-fabricates a green for bot PRs; content gates must be reproduced in Phase 4 or excluded via non-15368 id).

## Phase 3 — Action derives CHECK_NAMES from the SSOT
- [x] 3.1 Replace hardcoded `CHECK_NAMES=(...)` (`action.yml:168`) with a read of `scripts/required-checks.txt` reusing the fixed `lint-bot-synthetic-completeness.sh` parser (see 5.1 — leading-`#`-only comment rule); fail loud if file absent (checkout precondition).
- [x] 3.2 Post one 15368 check-run per name; `case` special-cases `cla-check`/`cla-evidence` custom outputs; no double-post.
- [x] 3.3 Update the action `CHANGELOG.md` (v3).

## Phase 4 — Secret-safety ceiling (Tier 2, MANDATORY)
- [x] 4.1 Reproduce BOTH content gates over the staged diff before posting: real gitleaks (pinned == secret-scan.yml, `.gitleaks.toml`, `--redact`) AND `node apps/web-platform/scripts/lint-fixture-content.mjs`; any finding → fail loud, no PR, no synthetics.
- [x] 4.2 Safe-surface allowlist = explicit enumeration: `add-paths` ∈ {`knowledge-base/project/weakness-digest.md`, `knowledge-base/project/rule-metrics.json`}; REJECT `plans/`/`specs/`/`references/`/`learnings/` sub-trees (gitleaks-blind); NOT a bare "markdown" predicate.
- [x] 4.3 Add the action's own pinned gitleaks install (3rd site). Do NOT extract/refactor secret-scan.yml. Pin-parity assertion added in 5.4.

## Phase 5 — Drift-proof tests
- [x] 5.1 Fix the shared parser comment rule (`lint-bot-synthetic-completeness.sh`) to leading-`#`-only; regression case in its `.test.sh` that `waiver discipline (issue:#NNN trailer)` round-trips intact.
- [x] 5.2 New `plugins/soleur/test/required-checks-canonical-parity.test.sh`: `required-checks.txt` CI-subset (exclude named CLA set `{cla-check,cla-evidence}`) ≡ canonical contexts `jq select(.integration_id==15368)`, asserted BOTH ⊆ and ⊇ (set compare, multi-word safe, regex-escaped).
- [x] 5.3 Mandatory-minimal composite guard: `grep -q` that `action.yml` references `scripts/required-checks.txt` (future re-hardcode caught).
- [x] 5.4 Pin-parity assertion: `GITLEAKS_VERSION`+SHA256 equal across secret-scan.yml, ci.yml test-scripts, action.
- [x] 5.5 Confirm `scripts/test-all.sh` picks up the new `.test.sh` in the `ci.yml` `test-scripts` job.

## Phase 6 — ADR + C4
- [x] 6.1 Amend `ADR-032-github-branch-protection-as-iac.md` (drift-chain contract, adr-ordinals reconcile, SSOT-derived CHECK_NAMES, real-gitleaks ceiling).
- [x] 6.2 C4 completeness read (model.c4/views.c4/spec.c4) → record "no C4 impact" with the external-actor/system/access enumeration.

## Verification
- [x] V1 `bash scripts/lint-bot-synthetic-completeness.sh` green.
- [x] V2 Full `scripts/test-all.sh` (or the `test-scripts` shard) green incl. new parity test + T-rsc-9.
- [x] V3 `terraform -chdir=infra/github validate` green; no-op plan documented.
- [x] V4 Confirm no `apps/web-platform/**` files changed (typecheck N/A).
- [ ] V5 PR body `Closes #6049`; pre/post-merge AC split; @deruelle code-owner review noted.
