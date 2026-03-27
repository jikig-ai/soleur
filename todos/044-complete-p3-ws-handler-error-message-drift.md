---
status: pending
priority: p3
issue_id: 1195
tags: [code-review, security]
dependencies: []
---

# Hardcoded error message in ws-handler could drift from error-sanitizer

## Problem Statement

The Layer 1 guard in `ws-handler.ts` hardcodes `"Invalid selection. Please choose one of the offered options."` -- the same string that `error-sanitizer.ts` maps from `"Invalid review gate selection"`. If the sanitized message changes, these will drift, creating inconsistent client error messages.

## Findings

- **Source:** security-sentinel (F3)
- **File:** `apps/web-platform/server/ws-handler.ts:240-244`
- **Severity:** P3 (cosmetic information leakage, no functional impact)

## Proposed Solutions

1. Extract the user-facing string to a shared constant
2. Throw an Error and let the catch block run `sanitizeErrorForClient`

## Acceptance Criteria

- [ ] Both validation layers produce identical client-facing error messages from a single source of truth
