---
status: pending
priority: p2
issue_id: "008"
tags: [code-review, architecture, patterns]
dependencies: ["001"]
---

# Consolidate global state and readiness paths

## Problem Statement

10 mutable global variables form an implicit state machine. Three independent paths to `cliState = "ready"` (system/init, initial result, timeout fallback). Duplicated stdin write pattern across 2 functions.

## Findings

- **pattern-recognition-specialist**: "implicit state machine where valid transitions are not enforced"
- **architecture-strategist**: "triple readiness path makes reasoning about startup non-trivial"

## Proposed Solutions

### Consolidate readiness into `markReady(source)`
Single function with idempotency guard, eliminates scattered drainQueue calls.

### Extract `writeToStdin()` helper
Eliminates duplicated try/catch/Promise pattern in `sendPermissionResponse` and `sendUserMessage`.

### Add queue bound
`MAX_QUEUE_SIZE = 20`, reject with user feedback when full.

- **Effort**: Medium
- **Risk**: Low

## Acceptance Criteria
- [ ] Single `markReady()` function handles all ready transitions
- [ ] `writeToStdin()` helper eliminates duplication
- [ ] Queue has max size with user notification

## Work Log
- 2026-02-11: Identified during /soleur:review
