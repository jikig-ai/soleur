---
feature: harness-auto-edit-safety-policy
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-06-feat-harness-auto-edit-safety-detector-plan.md
issue: 6103
---

# Tasks — hard-rule body-weakening gate (minimal v1)

## Phase 0 — Preconditions
- [x] 0.1 Confirm worktree exists + push early (concurrent reaping live this session).
- [x] 0.2 `git ls-files | grep -i lint-rule-ids` → locate the sibling test harness + runner; mirror convention (do NOT hardcode).
- [x] 0.3 Read `scripts/lint-rule-ids.py` §`lint_union` — reuse `[id:]` extraction + cross-sidecar union.
- [x] 0.4 Confirm `TARGET_ALLOW_RE` is exported from `cron-compound-promote.ts` (L63) for the recursion-test import.
- [x] 0.5 Verify CODEOWNERS-review-required is actually enforced on `main` (live ruleset). Record the live path; if not enforced, fallback = required `approvals ≥ 1` + required CI check.

## Phase 1 — Manifest generator + baseline (TDD)
- [x] 1.1 Write the calibration test FIRST: `--check` against HEAD==manifest → zero findings on ~194 rules.
- [x] 1.2 `scripts/lint-rule-bodies.py --write`: union id→body map across `AGENTS.{core,docs,rest}.md` for `hr-*`+`wg-*`; normalize; sha256 per id → `.claude/rule-body-hashes.txt` (`{schema:1,hashes:{}}`).
- [x] 1.3 Decide normalization (trailing whitespace; tag-order — Open Question) and document it in the script header.
- [x] 1.4 Commit the baseline manifest over the current corpus; calibration test green.

## Phase 2 — Body-change gate (`--check --base <merge-base>`)
- [x] 2.1 Base = `git merge-base origin/main HEAD`; build base-side id→body map across all 3 sidecars.
- [x] 2.2 For each hr-*/wg- id at base: body **changed** (hash mismatch) OR **vanished** → require matching per-change ack `<id>|<new-sha256>|<date>|<PR>|<reason>` (sha256 == current body hash). Missing/stale → BLOCK. CI re-derives the hash (TR1).
- [x] 2.3 Security tag on old∪new body of a changed id → mandatory-human-review annotation (ack still required).
- [x] 2.4 Added line under a NEW id carrying a security tag → flag (SF-P2-8).
- [x] 2.5 Fail-closed on parse error / missing manifest / missing base.
- [x] 2.6 Tests: change-no-ack→BLOCK; change+ack→PASS; stale-ack→BLOCK; deletion→BLOCK; new-rule→PASS; tampered-manifest→BLOCK; no-op reformat→PASS; wg- core→rest move+weaken→caught.

## Phase 3 — Required CI check (the real gate)
- [x] 3.1 Add `rule-body-lint` job to `.github/workflows/ci.yml`.
- [x] 3.2 Add `rule-body-lint` context to `scripts/ci-required-ruleset-canonical-required-status-checks.json` + `infra/github/ruleset-ci-required.tf` (CODEOWNERS review expected). Decide standalone vs `test`-aggregator fold.
- [x] 3.3 Enroll `rule-body-lint` in the existing required-check drift-guard cron.
- [x] 3.4 Audit bot-PR-creating workflows for synthetic-check updates (new required context can wedge them).

## Phase 4 — CODEOWNERS + recursion test + ADR
- [x] 4.1 CODEOWNERS explicit rows: `AGENTS.{core,rest,docs}.md`, `scripts/lint-rule-bodies.py`, `.claude/rule-body-hashes.txt`, `.claude/rule-weakening-acks.txt`.
- [x] 4.2 Recursion test: `import { TARGET_ALLOW_RE }`; assert new load-bearing files (incl. acks.txt) ∉ allowlist; assert a synthetic core.md weakening/tag-drop IS caught (real property, not the ∉ tautology).
- [x] 4.3 `/soleur:architecture create` ADR-092 (Provisional): additive-only boundary + gate + recursion invariant + Lineage (ADR-054/069/027-stateless) + revisit trigger (~2026-08-05). List lexer/LLM-judge/C4 as deferred.
- [x] 4.4 Add `AP-017 → ADR-092` row to `knowledge-base/engineering/architecture/principles-register.md`.

## Phase 5 — Verify + ship prep
- [x] 5.1 Full suite green (typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; repo test runner per `package.json`).
- [ ] 5.2 PR body: `Closes #6103`; `Ref #6038`.
- [ ] 5.3 Comment on #6038 enumerating deferred-into-build items (lexer, LLM-judge, C4 component, lefthook mirror, soak follow-through).
