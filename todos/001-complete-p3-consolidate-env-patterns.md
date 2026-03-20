---
status: pending
priority: p3
issue_id: "807"
tags: [code-review, security, simplification]
dependencies: []
---

# Consolidate .env exclusion patterns in .dockerignore

## Problem Statement

The `.dockerignore` uses three separate lines for env file exclusions (`.env`, `.env.example`, `.env*.local`) when a single `.env*` glob would cover all cases more defensively. The current patterns miss `.env.production` and `.env.staging` files.

## Findings

- All three review agents (security, architecture, simplicity) independently recommended this consolidation
- Docker's filepath.Match supports `*` globbing on `.env*`
- No `.env.production` or `.env.staging` files are needed in the Docker image since all env vars are injected at runtime via `--env-file`

## Proposed Solutions

### Option A: Single .env* glob (Recommended)
Replace three lines with: `.env*`
- Pros: Simpler, broader coverage, catches future env file variants
- Cons: Would also catch a hypothetical `.envrc` file (direnv) - but this is desirable
- Effort: Small
- Risk: Low

## Technical Details

- Affected files: `apps/web-platform/.dockerignore` lines 5-7
- Replace `.env`, `.env.example`, `.env*.local` with single `.env*`

## Acceptance Criteria

- [ ] Single `.env*` pattern replaces three separate env patterns
- [ ] Docker build still succeeds
