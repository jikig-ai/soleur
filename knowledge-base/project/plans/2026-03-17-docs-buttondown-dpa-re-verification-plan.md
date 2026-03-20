---
title: "Update Buttondown DPA verification and legal docs after March 16 refresh"
type: docs
date: 2026-03-17
---

# Update Buttondown DPA Verification and Legal Docs

## Overview

Buttondown refreshed their legal documents on March 16, 2026, addressing 3 of 5 gaps identified in our March 11 DPA review. The brainstorm, verification memo, and legal docs have already been updated in the worktree with confirmed facts (data types, sub-processor list). This plan covers committing, auditing for consistency, updating the PR, and preparing the follow-up email.

## Acceptance Criteria

- [x] All modified files committed and pushed to PR #528
- [ ] Legal-compliance-auditor run confirms cross-document consistency
- [ ] Pre-existing audit findings filed as GitHub issues
- [x] PR #528 title and body updated (no longer WIP)
- [x] SCCs/transfer mechanism claims updated — now substantiated by DPA Section 8 (Decision 2021/914, Module 2)
- [x] Free-tier DPA coverage confirmed — DPA applies to all plans
- [ ] #501 closed after DPA signed

## Context

### Files Already Modified (uncommitted)

1. `docs/legal/privacy-policy.md` — Section 4.6 data types expanded, Section 5.3 sub-processor list URL added
2. `docs/legal/gdpr-policy.md` — Section 4.2 data types expanded, Section 10 sub-processor list URL added
3. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — Section 2.3(e) data types expanded, Section 4.2 sub-processor detail added
4. `knowledge-base/project/brainstorms/2026-03-11-buttondown-dpa-review-brainstorm.md` — March 16 update section added
5. `knowledge-base/project/specs/feat-buttondown-dpa-review/dpa-verification-memo.md` — Full re-assessment, new compliance matrix, follow-up email draft

### What NOT to Change

- Privacy Policy Section 5.3: "International data transfers are covered by Standard Contractual Clauses (SCCs)" — this claim remains **unsupported** until Buttondown confirms SCCs execution. Do not update until resolved.
- GDPR Policy Section 10: "SCCs in place" — same, hold until confirmed.

### Remaining Buttondown Gaps

| Gap | Status | Blocks signing? |
|-----|--------|----------------|
| SCCs execution (Module 2) | RESOLVED — DPA Section 8 incorporates SCCs (Decision 2021/914, Module 2) | No |
| Free tier DPA applicability | RESOLVED — Steph confirmed DPA covers all plans | No |
| Art. 28(3) instruction-infringement notification | Missing — low severity | No |
| Breach notification 72h timeline | "Without undue delay" only | No |

## Implementation Steps

### Phase 1: Commit and Push

1. Stage all 5 modified files
2. Commit with message: `docs: update legal docs after Buttondown March 16 DPA refresh`
3. Push to origin

### Phase 2: Cross-Document Consistency Audit

1. Run legal-compliance-auditor agent against the three legal documents
2. Review findings — separate new issues (introduced by this PR) from pre-existing issues
3. Fix any new inconsistencies introduced by this PR
4. File GitHub issues for any pre-existing inconsistencies found

### Phase 3: Update PR #528

1. Update PR title from "WIP: feat-buttondown-dpa-review" to "docs: update legal docs after Buttondown DPA refresh"
2. Update PR body with summary of changes, remaining gaps, and note that SCCs claims are intentionally held
3. #501 stays open — DPA not yet signed (2 blocking gaps remain)

### Phase 4: Email (Manual)

1. Jean reviews and sends follow-up email from verification memo Section 8b

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-11-buttondown-dpa-review-brainstorm.md`
- Verification memo: `knowledge-base/project/specs/feat-buttondown-dpa-review/dpa-verification-memo.md`
- Buttondown blog post: https://buttondown.com/blog/2026-03-16-legal-docs-refresh
- Related issue: #501 (Newsletter)
- PR: #528
- Precedent: `knowledge-base/project/learnings/2026-03-11-third-party-dpa-gap-analysis-pattern.md`
- Precedent: `knowledge-base/project/learnings/2026-02-21-github-dpa-free-plan-scope-limitation.md`
