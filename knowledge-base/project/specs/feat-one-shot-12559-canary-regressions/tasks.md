# Tasks — fix(ci): canary #12557 exposes two main-line regressions from #12521

Plan: `knowledge-base/project/plans/2026-11-10-fix-ci-canary-regressions-plan.md`
Issue: #12559 | Branch: `feat-one-shot-12559-canary-regressions`

## 1. Baseline rows (regression 1)

- [ ] 1.1 Run `bash scripts/test-affected-kb-consumers.test.sh --write-baseline` in this worktree.
- [ ] 1.2 Verify `git diff scripts/test-affected-kb-consumers.baseline.txt` shows exactly five added two-column rows (`scripts/ci-oracle-review<TAB>knowledge-base`, `…/engineering/architecture/diagrams`, `…/project`, `…/project/learnings`, `…/project/specs`) and no removed/modified lines. Stop and surface if `--write-baseline` emits anything else.
- [ ] 1.3 Carry the false-positive rationale in the commit message (argv-code baseline rows have no classification column): naming `scripts/ci-oracle-lane.*` in comments/stub docs is not a read; the kb strings are lane fixture/pattern data.

## 2. ADR-276 blank line (regression 2)

- [ ] 2.1 Insert one blank line between the `Notes:` paragraph (line 693) and the `- 2026-11-09 S4 retired, verdict NO-GO …` bullet (line 694) in `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`. No other edits.

## 3. Verification

- [ ] 3.1 `bash scripts/test-affected-kb-consumers.test.sh` exits 0 (real worktree; allow several minutes under box contention — a timeout is unresolved coverage, not a pass).
- [ ] 3.2 `bash scripts/markdown-lint.sh --repo-sweep` exits 0.
- [ ] 3.3 Spot-check: `node_modules/.bin/markdownlint -c .markdownlint.json knowledge-base/engineering/architecture/decisions/ADR-276-….md` reports zero findings.
