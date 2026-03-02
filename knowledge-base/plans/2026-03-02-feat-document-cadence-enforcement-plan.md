---
title: "feat: Document cadence enforcement for knowledge-base artifacts"
type: feat
date: 2026-03-02
version_bump: PATCH
---

# feat: Document Cadence Enforcement

## Overview

Extend `review-reminder.yml` to enforce periodic review of strategic knowledge-base documents using a `last_reviewed` + `review_cadence` frontmatter model. Fixes a bug in the existing workflow that silently skips overdue documents.

## Problem Statement / Motivation

Strategic documents (brand-guide, business-validation, constitution) go stale without anyone noticing. The Cowork Plugins incident proved this: a competitive threat went undetected for 22 days because `business-validation.md` was never re-reviewed. Downstream agents consume these docs as ground truth and propagate stale information.

A `review-reminder.yml` workflow exists but has three problems:
1. Only scans `knowledge-base/learnings/` (misses strategic docs)
2. Only 3 files use the `next_review` field
3. **Bug:** Silently skips all overdue documents (only flags docs due in 0-7 days)

Closes #334.

## Proposed Solution

Replace `next_review` with `last_reviewed` + `review_cadence`. Widen scan to all of `knowledge-base/`. Fix the overdue-document bug.

## Technical Considerations

### Bug fix: Overdue documents silently skipped

`.github/workflows/review-reminder.yml:66` has:
```bash
if [[ $days_until -lt 0 || $days_until -gt 7 ]]; then
  continue
fi
```

This skips documents where `days_until < 0` (overdue). A document due Feb 15 with a March 1 run gets `-14` and is permanently ignored. The new condition must be:
```bash
if [[ $days_until -gt 7 ]]; then
  continue
fi
```

This flags everything due within 7 days **or already past due**, matching the spec's intent.

### Slug uniqueness with wider scan scope

Current: `slug=$(basename "$file" .md)` produces `brand-guide` from any path.
Risk: If `knowledge-base/overview/expenses.md` and `knowledge-base/ops/expenses.md` both have cadence, they'd collide.

Fix: Use relative path from `knowledge-base/`:
```bash
slug="${file#knowledge-base/}"  # e.g., "overview/brand-guide.md"
slug="${slug%.md}"               # e.g., "overview/brand-guide"
```

Issue title becomes: `Review Reminder: overview/brand-guide`

### Cadence computation

Replace `next_review` parsing with date arithmetic:
```bash
# Extract fields
review_cadence=$(sed -n '/^---$/,/^---$/{ /^review_cadence:/{ s/.*: *//; p; q; } }' "$file")
last_reviewed=$(sed -n '/^---$/,/^---$/{ /^last_reviewed:/{ s/.*: *//; p; q; } }' "$file")

# Map cadence to days
case "$review_cadence" in
  monthly)   cadence_days=30 ;;
  quarterly) cadence_days=90 ;;
  biannual)  cadence_days=180 ;;
  annual)    cadence_days=365 ;;
  *) continue ;;  # unknown cadence, skip
esac

# If no last_reviewed, treat as immediately stale
if [[ -z "$last_reviewed" ]]; then
  days_until=-1
else
  last_epoch=$(date -d "$last_reviewed" +%s 2>/dev/null) || continue
  next_due_epoch=$((last_epoch + cadence_days * 86400))
  days_until=$(( (next_due_epoch - today_epoch) / 86400 ))
fi
```

### Issue body template update

Old: "Update `next_review` in the source document's YAML frontmatter"
New: "Update `last_reviewed` to today's date in the source document's YAML frontmatter"

## Acceptance Criteria

- [ ] Workflow scans all of `knowledge-base/` (not just `learnings/`)
- [ ] Files with `review_cadence` frontmatter are checked; files without are ignored
- [ ] Staleness computed as `last_reviewed + cadence_days` vs `today + 7 days`
- [ ] Overdue documents are flagged (not silently skipped)
- [ ] Issue titles use path-based slugs for uniqueness
- [ ] Issue body references `last_reviewed` (not `next_review`)
- [ ] 3 existing `next_review` files migrated to new model
- [ ] Strategic docs have `last_reviewed` + `review_cadence` frontmatter
- [ ] `constitution.md` has YAML frontmatter added
- [ ] Deterministic issue titles prevent duplicates

## Test Scenarios

- Given a file with `review_cadence: quarterly` and `last_reviewed: 2025-12-01`, when workflow runs on 2026-03-02, then an issue is created (92 days > 90, overdue)
- Given a file with `review_cadence: quarterly` and `last_reviewed: 2026-01-15`, when workflow runs on 2026-03-02, then no issue is created (47 days < 90, not yet due)
- Given a file with `review_cadence: quarterly` and `last_reviewed: 2025-11-01`, when workflow runs on 2026-03-02, then an issue is created (122 days overdue -- must NOT be silently skipped)
- Given a file with `review_cadence: monthly` and no `last_reviewed`, when workflow runs, then an issue is created (immediately stale)
- Given a file without `review_cadence`, when workflow runs, then the file is ignored
- Given `constitution.md` with `review_cadence: quarterly`, when workflow runs, then it is processed correctly despite newly-added frontmatter
- Given two files with same basename in different directories, when both are stale, then two distinct issues are created (no slug collision)
- Given an existing open issue for a stale doc, when workflow runs again, then no duplicate issue is created
- Given `date_override: 2026-06-01`, when workflow_dispatch runs, then staleness is computed against June 1

## Migration Table

| File | Current `next_review` | New `last_reviewed` | New `review_cadence` | Notes |
|------|----------------------|--------------------|--------------------|-------|
| `learnings/2026-02-20-marketingskills-overlap-analysis.md` | 2026-05-20 | 2026-02-20 | quarterly | 89 days ≈ quarterly |
| `learnings/2026-02-27-github-actions-sha-pinning-workflow.md` | 2026-08-27 | 2026-02-27 | biannual | 181 days ≈ biannual |
| `learnings/implementation-patterns/github-actions-audit-methodology.md` | 2026-05-21 | 2026-02-21 | quarterly | 89 days ≈ quarterly |

## Strategic Document Adoption

| File | `last_reviewed` | `review_cadence` | Rationale |
|------|----------------|-----------------|-----------|
| `overview/brand-guide.md` | 2026-03-02 | quarterly | Brand identity shifts with product evolution |
| `overview/business-validation.md` | 2026-03-02 | quarterly | Cowork Plugins incident proved quarterly needed |
| `overview/constitution.md` | 2026-03-02 | quarterly | Conventions evolve with new learnings |

Note: `last_reviewed` set to today (2026-03-02) since this change constitutes a review of these documents' relevance.

## References

- Existing workflow: `.github/workflows/review-reminder.yml`
- Platform risk learning: `knowledge-base/learnings/2026-02-25-platform-risk-cowork-plugins.md`
- Propagation risk: `knowledge-base/learnings/2026-02-22-agent-context-blindness-vision-misalignment.md`
- Brainstorm: `knowledge-base/brainstorms/2026-03-02-document-cadence-brainstorm.md`
- Spec: `knowledge-base/specs/feat-document-cadence/spec.md`
- Issue: #334
