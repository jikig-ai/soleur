# Tasks: feat-one-shot-mattpocock-audit-record-founder-decisions

Plan: `knowledge-base/project/plans/2026-09-24-docs-mattpocock-audit-record-founder-decisions-plan.md`

Draft PR #8648 already exists. Do not open another PR.

## 1. Setup

- [ ] 1.1 Re-run `gh issue view N --json state` for every issue on the audit record's
  `**Open issues from the bundles:**` line, and re-read the `plugins/soleur/NOTICE` "Bundle 6"
  paragraph.

## 2. Audit record (`knowledge-base/product/competitive-intelligence.md`)

- [ ] 2.1 Dating: `last_updated`, the reconciliation-intro sentence, the status column header
  (plan §1). Keep the `#### Reconciliation status (2026-09-23)` heading.
- [ ] 2.2 T1: no change to Key Takeaway 4 (plan §2).
- [ ] 2.3 T2: B5 row, open-issues line, `**Closed since:**` line (plan §3).
- [ ] 2.4 T3: first-half narrowing of the `G1, G5, B9, B12` row; replace the B4 and B10 rows; add the
  B12 (second half) row (plan §4).
- [ ] 2.5 T3 sibling sites: Tier 1 row span, Scope note clause, §5 banner (plan §4).
- [ ] 2.6 T4: the `setup-pre-commit` verdict (plan §5).
- [ ] 2.7 Inspire-only declines block after the open-issues paragraph (plan §6).

## 3. Dissent record and archive

- [ ] 3.1 Add the four `**Founder decision 2026-09-23:**` lines to
  `specs/feat-ci-mattpocock-skills-audit/decision-challenges.md` (plan §7).
- [ ] 3.2 Dry-run, then run, `archive-kb.sh ci-mattpocock-skills-audit` and
  `archive-kb.sh mattpocock-skills-audit` (plan §8).
- [ ] 3.3 Run the §8 reference sweep and repoint any hit.

## 4. Verification

- [ ] 4.1 Run AC1 to AC15 from the plan.
- [ ] 4.2 `bash scripts/markdown-lint.sh knowledge-base/product/competitive-intelligence.md`.
