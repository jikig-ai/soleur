---
status: complete
priority: p3
issue_id: 864
tags: [code-review, quality, types]
dependencies: []
---

# HealthState.cliState typed as string instead of CliState union

## Problem Statement

`health.ts` declares `cliState: string` but the actual values are constrained to `"connecting" | "ready" | "error"` (the `CliState` union in `types.ts`). A new state added to `CliState` would silently pass the health check's `=== "ready"` comparison without a type error.

## Findings

- **Flagged by:** architecture-strategist
- **Location:** `apps/telegram-bridge/src/health.ts:3`
- `types.ts` already defines `CliState` with the correct union
- Importing it in health.ts adds zero npm dependencies (types.ts is pure declarations)

## Proposed Solutions

### Option A: Import CliState in health.ts (Recommended)

**Approach:** `import type { CliState } from "./types"` and change `cliState: string` to `cliState: CliState`.

**Effort:** Small | **Risk:** Low

## Technical Details

**Affected files:** `apps/telegram-bridge/src/health.ts:1-7`

## Acceptance Criteria

- [ ] HealthState uses CliState union type
- [ ] health.ts still has zero npm dependencies
- [ ] Typecheck passes

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-20 | Created from code review of PR #867 | Type-only imports preserve zero-npm-deps property |
