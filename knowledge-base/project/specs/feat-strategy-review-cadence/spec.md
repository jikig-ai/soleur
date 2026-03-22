---
feature: strategy-review-cadence
status: draft
created: 2026-03-22
---

# Strategy Document Review Cadence Specification

## Problem Statement

Strategy documents in knowledge-base (product, marketing, sales) have no consistent review cadence. Most lack review metadata. Documents go stale silently — the brand guide predates both the PIVOT verdict and critical user research by weeks. When upstream documents change (e.g., business validation), dependent documents (brand guide, roadmap, marketing strategy) are not automatically flagged for review.

## Goals

- G1: Standardize frontmatter schema across all strategy documents (last_updated, last_reviewed, review_cadence, owner, depends_on)
- G2: Create a CI cron workflow that detects overdue documents and creates GitHub issues
- G3: Implement event-driven cascade — when an upstream document changes, dependent documents are flagged for review
- G4: Update business-validation.md with 2026-03-22 user research finding (5+ conversations: plugin rejected, users want native cross-platform)
- G5: Cascade the validation update to dependent documents via parallel domain leader sub-agents

## Non-Goals

- NG1: Covering engineering, ops, or support directories in the first pass (expand later)
- NG2: Auto-updating documents without human review (CI creates issues, humans do the review)
- NG3: Building a dedicated strategy-cascade skill (manual sub-agent spawning is sufficient for now)

## Functional Requirements

- FR1: Define standardized frontmatter schema with 5 fields (last_updated, last_reviewed, review_cadence, owner, depends_on)
- FR2: Add frontmatter to all strategy documents in product/, marketing/, and sales/ directories
- FR3: Create scheduled-strategy-review.yml workflow that runs weekly, scans frontmatter, creates issues for overdue docs
- FR4: Update business-validation.md with user research finding, re-assess affected gates
- FR5: Cascade validation update to dependent docs (brand-guide, roadmap, pricing-strategy, marketing-strategy) via parallel sub-agents
- FR6: Each cascade sub-agent updates its document's `last_reviewed` and `last_updated` fields

## Technical Requirements

- TR1: Scheduled workflow follows existing patterns (workflow_dispatch + schedule, concurrency, SHA-pinned actions)
- TR2: Frontmatter parsing via awk or yq in the workflow script
- TR3: GitHub issue creation with `scheduled-strategy-review` label
- TR4: Domain leader sub-agents spawned via Task tool for cascade
