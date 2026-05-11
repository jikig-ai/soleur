---
title: Tasks — ops(ci) sync create-ci-required-ruleset.sh with live ruleset state
plan: knowledge-base/project/plans/2026-05-11-ops-sync-create-ci-required-ruleset-with-live-state-plan.md
issue: 3547
branch: feat-one-shot-3547-create-ruleset-sync
---

# Tasks

## Phase 0 — Pre-flight (no code)

- [ ] 0.1 Confirm live ruleset shape: `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks'` returns 5 entries with the 2026-05-11 snapshot table.
- [ ] 0.2 Confirm `scripts/lib/canonicalize-bypass-actors.sh` exists; new lib will follow same shape.
- [ ] 0.3 Confirm `tests/scripts/test-audit-ruleset-bypass.sh` exists; new T-cases will follow `_run/_report/_mode/_label/_detail` shape.
- [ ] 0.4 Verify GitHub labels `ci/auth-broken`, `ci/guard-broken`, `compliance/critical` exist (workflow defensively creates them — confirm only).

## Phase 1 — Extract canonical JSON (contract-first)

- [ ] 1.1 Write `scripts/ci-required-ruleset-canonical-required-status-checks.json` with 5 entries sorted by context. Preserve heterogeneous integration_id (15368 ×4, 57789 ×1 for CodeQL).
- [ ] 1.2 Write `scripts/lib/canonicalize-required-status-checks.sh` exporting `CANONICALIZE_REQUIRED_STATUS_CHECKS_JQ` via `map({context, integration_id}) | sort_by(.context, (.integration_id | tostring))`.

## Phase 2 — Refactor `create-ci-required-ruleset.sh`

- [ ] 2.1 Add `CANONICAL_RSC_FILE` constant + existence + array-shape pre-flight checks (mirror lines 27-34 of bypass pattern).
- [ ] 2.2 Replace heredoc `required_status_checks` array with placeholder `[]`; chain `jq --slurpfile bypass --slurpfile rsc` in a single pass.
- [ ] 2.3 Add `--dry-run` flag — early-exit before POST, prints synthesized payload to stdout.
- [ ] 2.4 Rewrite header comment block: name both canonical files, point operators at the JSON files as source of truth, remove specific check names from prose.

## Phase 3 — Extend `update-ci-required-ruleset.sh` post-PUT fast-path

- [ ] 3.1 Source `scripts/lib/canonicalize-required-status-checks.sh`.
- [ ] 3.2 Add `CANONICAL_RSC_FILE` constant.
- [ ] 3.3 After bypass-actors fast-path (around line 239), add symmetric required-status-checks fast-path — diff `$CANONICALIZE_REQUIRED_STATUS_CHECKS_JQ` of canonical vs after-PUT live; on drift, `echo "::error::..."` + `drift=1`.
- [ ] 3.4 Document in header that a new check requires editing the canonical FIRST (the existing exit-2 drift convention enforces this).

## Phase 4 — Extend `audit-ruleset-bypass.sh`

- [ ] 4.1 Source `scripts/lib/canonicalize-required-status-checks.sh`.
- [ ] 4.2 Rename internal `CANONICAL_FILE` → `CANONICAL_BYPASS_FILE` (4 sites in audit + 1 in test); KEEP env var `AUDIT_CANONICAL_FILE_OVERRIDE` for backcompat.
- [ ] 4.3 Add `CANONICAL_RSC_FILE` constant + `AUDIT_CANONICAL_RSC_FILE_OVERRIDE` test-only env var; document in header.
- [ ] 4.4 Add second canonical-diff block in sequence with the bypass one; emit `failure_mode=required_status_checks_drift` routed to `ci/auth-broken` + `compliance/critical`.
- [ ] 4.5 Add `canonical_rsc_file_missing` and `canonical_rsc_file_malformed` failure-modes routed to `ci/guard-broken`.

## Phase 5 — Extend audit workflow YAML

- [ ] 5.1 `sparse-checkout` list: add `scripts/ci-required-ruleset-canonical-required-status-checks.json` and `scripts/lib/canonicalize-required-status-checks.sh`.
- [ ] 5.2 Update workflow `name:` to "Scheduled: Canonical Ruleset Audit (bypass_actors + required_status_checks)". KEEP filename `scheduled-ruleset-bypass-audit.yml`.
- [ ] 5.3 Update header comment block — refresh to name both audit surfaces, add `#3547` to Ref line.
- [ ] 5.4 Failure-routing case statement: add `required_status_checks_drift` → `ci/auth-broken` + `compliance/critical`; `canonical_rsc_*` → `ci/guard-broken`.

## Phase 6 — Tests

- [ ] 6.1 `tests/scripts/test-audit-ruleset-bypass.sh` — add T-rsc-1 (identity).
- [ ] 6.2 Add T-rsc-2 (missing CodeQL drift).
- [ ] 6.3 Add T-rsc-3 (wrong integration_id — CodeQL → 15368 spoof).
- [ ] 6.4 Add T-rsc-4 (string-vs-number integration_id drift).
- [ ] 6.5 Add T-rsc-5 (extra check added via UI).
- [ ] 6.6 Add T-rsc-6 (cosmetic reorder is NOT drift).
- [ ] 6.7 Add T-rsc-7 (canonical_rsc_file_missing → ci/guard-broken).
- [ ] 6.8 Add T-rsc-8 (canonical_rsc_file_malformed → ci/guard-broken).
- [ ] 6.9 Add T-rsc-9 (independence: bypass-only drift, then rsc-only drift, prove they don't cross-fire).
- [ ] 6.10 Write `tests/scripts/test-create-ci-required-ruleset.sh` with 4 T-cases (T-create-1..4) covering `--dry-run` payload synthesis and canonical-missing/malformed error paths.
- [ ] 6.11 Run `bash tests/scripts/test-audit-ruleset-bypass.sh && bash tests/scripts/test-create-ci-required-ruleset.sh` — exit 0.

## Phase 7 — Runbook updates

- [ ] 7.1 `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` — rename title to "CI Required Ruleset Canonical Drift (bypass_actors + required_status_checks)"; add new section for required_status_checks_drift triage (read live, diff vs canonical, decide remediation direction).
- [ ] 7.2 Add "When to widen the canonical" section — 4-step procedure for adding a 6th check.
- [ ] 7.3 `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` — add pre-mutation gate that verifies the canonical JSON contains the new check; refresh script cross-references.

## Phase 8 — Documentation cross-references

- [ ] 8.1 `scripts/required-checks.txt` — refresh comment block to name BOTH canonical files; extend "edit the JSON, not arrays inlined anywhere else" language.

## Phase 9 — Pre-merge verification

- [ ] 9.1 `bash -n scripts/create-ci-required-ruleset.sh scripts/update-ci-required-ruleset.sh scripts/audit-ruleset-bypass.sh scripts/lib/canonicalize-required-status-checks.sh` exits 0.
- [ ] 9.2 `actionlint .github/workflows/scheduled-ruleset-bypass-audit.yml` exits 0. For embedded shell, extract `run:` blocks and `bash -c '<snippet>'` (per 2026-05-11 learning: never `bash -n <file.yml>`).
- [ ] 9.3 `yamllint .github/workflows/scheduled-ruleset-bypass-audit.yml` exits 0.
- [ ] 9.4 Cross-reference grep: `grep -rn 'ci-required-ruleset-canonical-required-status-checks' scripts/ .github/workflows/ knowledge-base/engineering/ops/runbooks/ tests/scripts/` returns expected hits across all 9 sites.
- [ ] 9.5 Sanity: `grep -nF '"context": "test"' scripts/create-ci-required-ruleset.sh` returns 0 hits (hard-coded array fully removed).
- [ ] 9.6 PR body includes `Closes #3547`.

## Phase 10 — Post-merge (operator)

- [ ] 10.1 `gh workflow run scheduled-ruleset-bypass-audit.yml`.
- [ ] 10.2 Poll until completion: `gh run list --workflow=scheduled-ruleset-bypass-audit.yml --limit=1 --json databaseId,status,conclusion`. Conclusion MUST be `success` with no `failure_mode=*_drift` output.
- [ ] 10.3 (Optional) Dry-run cold-create regression test: `scripts/create-ci-required-ruleset.sh --dry-run` payload's `required_status_checks` deep-equals live ruleset (5 entries, both integration_ids).

## Dependencies

- Phase 1 blocks 2, 3, 4 (canonical file + lib must exist before consumers source them).
- Phase 1+2+3+4 block Phase 5 (workflow sparse-checkout references files added in 1; failure-routing references failure_modes emitted in 4).
- Phase 1-5 block Phase 6 (tests assert behavior of 1-5).
- Phase 1-6 block Phase 7+8 (runbook + docs describe shipped behavior).
- Phase 1-8 block Phase 9 (pre-merge verification depends on all changes being in place).
- Phase 9 blocks Phase 10 (post-merge requires PR merged).
