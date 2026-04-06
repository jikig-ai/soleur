---
status: pending
priority: p3
issue_id: "807"
tags: [code-review, architecture]
dependencies: []
---

# Add scripts/ exclusion for forward-compatibility

## Problem Statement

The web-platform `.dockerignore` does not exclude `scripts/`, because `apps/web-platform/scripts/` doesn't currently exist. If scripts are added later, they'll leak into the Docker image.

## Findings

- Zero-cost defensive measure for forward-compatibility

## Proposed Solutions

### Option A: Add scripts/ exclusion (Recommended)
Add `scripts/` to the .dockerignore
- Pros: Defensive forward-compatibility measure
- Cons: Pattern matches nothing today
- Effort: Small
- Risk: Low

## Technical Details

- Affected files: `apps/web-platform/.dockerignore`

## Acceptance Criteria

- [ ] `scripts/` added to .dockerignore
