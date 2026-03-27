---
status: pending
priority: p3
issue_id: 1045
tags: [code-review, security, supply-chain]
dependencies: []
---

# No .npmrc with save-exact=true in web-platform

## Problem Statement

Neither `apps/web-platform/` nor the repo root has an `.npmrc` with `save-exact=true`. A future `npm install <new-package>` will default to adding it with a caret prefix, potentially re-introducing range dependencies on security-critical packages.

## Findings

- **Source:** security-sentinel review of PR #1182
- **Location:** `apps/web-platform/.npmrc` (missing)
- **Severity:** P3 (pre-existing, not introduced by this PR)
- **Note:** Adding `save-exact=true` would make the exact-pin policy self-enforcing for future `npm install` commands.

## Proposed Solutions

### Option A: Add .npmrc to apps/web-platform/

- **Pros:** Self-enforcing policy, prevents future caret additions
- **Cons:** Only covers web-platform directory
- **Effort:** Small
- **Risk:** Low

### Option B: Add .npmrc to repo root

- **Pros:** Covers all npm projects in the monorepo
- **Cons:** May be overly strict for non-security-critical dependencies
- **Effort:** Small
- **Risk:** Low

## Recommended Action

(To be filled during triage)

## Acceptance Criteria

- [ ] `.npmrc` with `save-exact=true` exists in appropriate location
- [ ] `npm install <test-package>` adds it without caret prefix
