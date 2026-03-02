# Feature: Document Cadence Enforcement

## Problem Statement

Strategic knowledge-base documents (brand-guide.md, business-validation.md, constitution.md) are point-in-time snapshots with no review enforcement. When they go stale, downstream agents consume them as ground truth and propagate errors — the Cowork Plugins incident proved a 22-day detection gap. A `review-reminder.yml` workflow exists but only scans `knowledge-base/learnings/` with a fragile fixed-date `next_review` model that only 3 files use.

## Goals

- Strategic KB documents have `last_reviewed` and `review_cadence` frontmatter
- The review-reminder workflow scans all of `knowledge-base/` and computes staleness from `last_reviewed + review_cadence`
- Documents past their review date surface as GitHub issues automatically
- Existing `next_review` files are migrated to the new model

## Non-Goals

- No new Soleur skill or agent (extend existing workflow only)
- No auto-close of review issues after resolution
- No standardization of `updated` vs `last_updated` field naming (separate cleanup)
- No compound-capture integration to auto-set `review_cadence` on new learnings

## Functional Requirements

### FR1: Frontmatter model

Documents opt in to cadence enforcement by adding two YAML frontmatter fields:
- `last_reviewed: YYYY-MM-DD` — date of last review
- `review_cadence: monthly | quarterly | biannual | annual` — how often to review

### FR2: Workflow scan expansion

`review-reminder.yml` scans all of `knowledge-base/` (recursive) instead of only `knowledge-base/learnings/`. Only files with `review_cadence` frontmatter are processed.

### FR3: Staleness computation

Workflow computes `next_due = last_reviewed + cadence` and creates a GitHub issue if the document is past due or due within 7 days.

### FR4: Migration

Replace `next_review` with `last_reviewed` + `review_cadence` in the 3 existing learnings files. Remove `next_review` support from the workflow.

### FR5: Strategic doc adoption

Add `last_reviewed` and `review_cadence` frontmatter to:
- `knowledge-base/overview/brand-guide.md`
- `knowledge-base/overview/business-validation.md`
- `knowledge-base/overview/constitution.md`

## Technical Requirements

### TR1: Backward compatibility

The workflow must cleanly handle files that have `review_cadence` but no `last_reviewed` (treat as immediately stale). Files without `review_cadence` are ignored.

### TR2: Idempotent issue creation

Maintain the existing deterministic issue title pattern to avoid duplicate issues for the same document.

### TR3: Cadence computation accuracy

- monthly = 30 days
- quarterly = 90 days
- biannual = 180 days
- annual = 365 days
