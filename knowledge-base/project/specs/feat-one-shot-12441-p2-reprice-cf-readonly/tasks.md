# Tasks: feat-one-shot-12441-p2-reprice-cf-readonly

Plan: `knowledge-base/project/plans/2026-11-15-chore-reprice-cloudflare-readonly-suite-weight-plan.md`
Issue: #12441 (Ref only, never closed by this PR). PR: #12778. Follow-up: #12780.

## 1. Setup

- [ ] 1.1 Confirm the row on `origin/main` is still `plugins/soleur/test/cloudflare-readonly.test.sh<TAB>1261<TAB>floor` (rebase if main moved the TSV).

## 2. Core Implementation

- [ ] 2.1 Edit tool: replace that one row with `plugins/soleur/test/cloudflare-readonly.test.sh<TAB>155229<TAB>measured`. Leave every other byte alone: headers, other rows and `scripts/suite-shard-legs.tsv`.
- [ ] 2.2 Never run `regenerate-shard-manifest.py --write` against committed paths. Never touch #12698.

## 3. Testing

- [ ] 3.1 `bash plugins/soleur/test/scripts-shard-manifest.test.sh`
- [ ] 3.2 `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`
- [ ] 3.3 `bash scripts/test-all-corpus-weight-budget.test.sh`
- [ ] 3.4 `bash scripts/test-all-fast-tier-budget.test.sh`
- [ ] 3.5 AC1 diff checks (numstat is `1 1 scripts/suite-durations.tsv` only; exactly the two `-`/`+` lines).

## 4. Ship

- [ ] 4.1 Commit `chore(ci): re-price cloudflare-readonly suite weight to measured (Ref #12441)` with the ruling and evidence (runs 43325786672/43324336862/43315786965 = 192026/186106/129838 ms; #12698 5-run median 155229). The message must contain no closing keyword.
- [ ] 4.2 `soleur:ship`: PR #12778 body says `Ref #12441`, has no closing keyword anywhere and `closingIssuesReferences: []` (AC2 commands).
- [ ] 4.3 CI `test-scripts` legs green on #12778 (AC3).
