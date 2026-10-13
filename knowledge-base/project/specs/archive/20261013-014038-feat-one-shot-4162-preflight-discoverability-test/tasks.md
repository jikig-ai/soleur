---
date: 2026-05-20
branch: feat-one-shot-4162-preflight-discoverability-test
issue: 4162
lane: single-domain
plan: knowledge-base/project/plans/2026-05-20-feat-preflight-discoverability-test-execution-plan.md
---

# Tasks — Preflight Check 10: Execute discoverability_test.command

## Phase 0: Preconditions

- [ ] 0.1. Verify Phase 0 Step 0.1 cache helper exists in `preflight/SKILL.md` (`PREFLIGHT_TMP`)
- [ ] 0.2. Verify canonical sensitive-path regex is byte-identical between `preflight/SKILL.md:398` and `deepen-plan/SKILL.md:348`
- [ ] 0.3. Verify Check 6 Step 6.3 plan-file resolution (lines ~422-448): awk fenced-code strip, perl HTML-comment strip, plan-link grep pattern
- [ ] 0.4. Run live preflight baseline against this branch; record PASS/SKIP profile in `session-state.md`
- [ ] 0.5. Live-falsify: `dig +short web-platform.soleur.ai` (empty), `dig +short app.soleur.ai` (IP), `curl https://app.soleur.ai/api/inngest` (200/401). Record in `session-state.md`.
- [ ] 0.6. Open Code-Review Overlap query (plan §"Open Code-Review Overlap"); record results.

## Phase 1: Refactor Check 6 Step 6.3 into Shared Plan-File Resolution

- [ ] 1.1. Insert new sub-section `### Shared Plan-File Resolution` in `preflight/SKILL.md` right after the `Assertion: Not-Bare-Repo` block (before Check 1)
- [ ] 1.2. The sub-section emits a single output `$COMBINED` (mktemp path) plus `$PLAN_PATH`, trap-cleaned
- [ ] 1.3. Edit Check 6 Step 6.3 to call the shared sub-section; delete the duplicated awk/perl/grep blocks
- [ ] 1.4. Add sync-pointer comment in the shared block listing consumers (Check 6 Step 6.4 + Check 10 Step 10.3)
- [ ] 1.5. Run the refactored Check 6 against this branch's PR; ensure same PASS/SKIP outcome as baseline

## Phase 2: Add Check 10 (Discoverability Test Execution)

- [ ] 2.1. Insert `### Check 10: Discoverability Test Execution` AFTER Check 9 in `preflight/SKILL.md`
- [ ] 2.2. Body matches plan §"Check 10 Body" structure (Steps 10.1–10.8)
- [ ] 2.3. Step 10.1 uses canonical `SENSITIVE_PATH_RE` byte-identical to Check 6
- [ ] 2.4. Step 10.2 calls Shared Plan-File Resolution
- [ ] 2.5. Step 10.3 extracts `## Observability` block via awk; FAIL if absent
- [ ] 2.6. Step 10.4 parser supports Form A (`expected_output:` YAML) AND Form B (fenced block + `Expected output:` prose)
- [ ] 2.7. Step 10.5 sanitizes for `ssh ` reject and `$()` / backtick / `<(` / `>(` substitution reject
- [ ] 2.8. Step 10.5 executes with `timeout 15s bash -c "$CMD"`, captures rc + sanitized stdout
- [ ] 2.9. Step 10.6 8-state decision matrix exists with exactly one PASS terminal
- [ ] 2.10. Step 10.7 / 10.8 headless / interactive behaviour documented
- [ ] 2.11. Add row to fast-path SKIP table (line ~44)
- [ ] 2.12. Add row to Phase 2 aggregate table (line ~647)
- [ ] 2.13. Update Phase 1 opening sentence to drop the (already-stale) "six checks" count

## Phase 3: Tests

- [ ] 3.1. Create `plugins/soleur/test/preflight-discoverability-test.test.ts` (bun:test)
- [ ] 3.2. Test asserts SSOT regex byte-equal to Check 6 (read `preflight/SKILL.md` once, grep both blocks)
- [ ] 3.3. Test asserts Phase 2 table row exists + fast-path table row exists + 8-state matrix exists
- [ ] 3.4. Test asserts `ssh ` reject regex + substitution-token reject regex present in Check 10
- [ ] 3.5. Create `plugins/soleur/test/lib/discoverability-test-parser.ts` — pure functions: `extractObservabilityBlock`, `parseCommand`, `parseExpected`, `matchExpected`, `classifyResult`
- [ ] 3.6. Create fixture `01-no-plan-link.md` (PR body with no plan reference)
- [ ] 3.7. Create fixture `02-no-observability-block.md`
- [ ] 3.8. Create fixture `03-no-command-field.md`
- [ ] 3.9. Create fixture `04-dns-fail.md` — snapshot of PR #4148's plan Observability block (literal `web-platform.soleur.ai`)
- [ ] 3.10. Create fixture `05-timeout.md`
- [ ] 3.11. Create fixture `06-mismatch.md`
- [ ] 3.12. Create fixture `07-auth-gated.md`
- [ ] 3.13. Create fixture `08-pass.md`
- [ ] 3.14. Implement 8 tests + 1 regression test (PR #4148) using injected stub executor (no live network)
- [ ] 3.15. Run `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` → 9 pass

## Phase 4: Documentation Sweep

- [ ] 4.1. Append Sharp Edges bullets to `preflight/SKILL.md` (triple-SSOT, parser duality, TS-is-reference, substitution reject, expected-substring trap, 15 s timeout cap, per-preflight semantics)
- [ ] 4.2. Append Re-evaluation footnote to `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md`
- [ ] 4.3. Create companion learning at `knowledge-base/project/learnings/best-practices/<date>-preflight-check-10-discoverability-test-execution.md` covering the 5-gate bypass, the typo'd-hostname pattern class, Form A vs B parser duality, invariant-gate framing, cross-references

## Phase 5: Acceptance Validation

- [ ] 5.1. `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` exits 0
- [ ] 5.2. `bun test plugins/soleur/test/components.test.ts` exits 0
- [ ] 5.3. `python3 scripts/lint-agents-rule-budget.py` exits 0
- [ ] 5.4. `python3 scripts/lint-rule-ids.py` exits 0
- [ ] 5.5. Triple-SSOT grep: `grep -nE 'SENSITIVE_PATH_RE' plugins/soleur/skills/preflight/SKILL.md plugins/soleur/skills/deepen-plan/SKILL.md` shows 3+ matches with byte-identical literals
- [ ] 5.6. Live `/soleur:preflight --headless` against this PR returns Check 10 PASS

## Phase 6: Ship Hand-off

- [ ] 6.1. Plan + tasks.md committed and pushed (covered by Save Tasks step of plan skill)
- [ ] 6.2. /work begins from Phase 0
- [ ] 6.3. PR body Acceptance Criteria mirrors plan §"Acceptance Criteria"
