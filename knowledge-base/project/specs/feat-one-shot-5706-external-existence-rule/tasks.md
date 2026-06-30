# Tasks — extend hr-verify-repo-capability-claim-before-assert to external existence

Plan: `knowledge-base/project/plans/2026-06-29-docs-extend-verify-rule-external-existence-plan.md`
Issue: #5706 · Branch: `feat-one-shot-5706-external-existence-rule` · Lane: procedural

## Phase 1 — Edit
- [x] 1.1 Reword `AGENTS.core.md:47` body of `hr-verify-repo-capability-claim-before-assert`: extend the negative-claim clause to cover "a named external system/model/paper/product is fake/doesn't exist/hallucinated"; add `WebSearch`-before-asserting-fabrication for post-cutoff entities; reword the contradictory `Scope: this-repo artifacts, not general facts.` clause; append `#5706` to `**Why:**` (retain `#4819`).
- [x] 1.2 Keep `[id: ...]` token byte-identical and keep "subagent" before the id (within 400 chars).

## Phase 2 — Byte-measure & verify
- [x] 2.1 Measure reworked line: `sed -n '47p' AGENTS.core.md | tr -d '\n' | wc -c` ≤ 600 (AC4). Result: **470 B** (net −3 vs 473).
- [x] 2.2 Measure B_ALWAYS: `echo $(( $(wc -c < AGENTS.md) + $(wc -c < AGENTS.core.md) ))` ≤ 23000 (AC3). Result: **22976** (≤ 22979).
- [x] 2.3 `python3 scripts/lint-agents-rule-budget.py …` exit 0 (AC5). ✅ (WARN-only, expected).
- [x] 2.4 `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt …` exit 0 (AC6). ✅
- [~] 2.5 `python3 scripts/lint-agents-enforcement-tags.py …` exits **1**, NOT 0 (AC7 expectation revised). The 11 errors are PRE-EXISTING on unrelated rules (identical count before/after this edit); line 47 carries no enforcement tag → adds zero errors. This linter is wired into `lefthook.yml` (`agents-enforcement-tag-lint`, glob `AGENTS.core.md`) — a LOCAL pre-commit gate, already red on those 11 anchors — but is NOT in any `.github/workflows/` CI job (verified), so it does not block merge. Operative AC7 intent (no NEW failure introduced) holds.
- [x] 2.6 `bun test plugins/soleur/test/mandatory-wireframes-hardening.test.ts` passes (AC8). ✅ 13/13.
- [x] 2.7 Grep confirms content extension: line contains `WebSearch` + `external` + `hallucinat` (AC1); `**Why:**` includes `#5706` and `#4819` (AC9). ✅

## Phase 3 — Ship
- [ ] 3.1 PR body: `Closes #5706`, `## Changelog` section, `semver:patch` (doc change).
