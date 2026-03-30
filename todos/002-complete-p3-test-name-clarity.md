---
status: complete
priority: p3
issue_id: 1047
tags: [code-review, quality]
dependencies: []
---

# Clarify /proc test name to mention defense layer

## Problem Statement

The test name "denies Read of /proc/1/environ (cross-tenant info leak)" does not indicate which defense layer is being tested (hook layer vs bubblewrap OS-level). A reader unfamiliar with the architecture might think this is the only defense.

## Findings

- Source: test-design-reviewer review of PR #1282
- Test Quality Score: 8.4/10 (Grade B)
- The test exercises the same code path as existing outside-workspace tests

## Proposed Solutions

### Option A: Update test name (recommended)

Change to: `"denies Read of /proc/1/environ at hook layer (defense-in-depth against cross-tenant info leak)"`

- Pros: Makes layered security model visible in test suite
- Cons: Longer test name
- Effort: Small
- Risk: None

## Technical Details

- File: `apps/web-platform/test/sandbox-hook.test.ts:54`

## Acceptance Criteria

- [ ] Test name mentions "hook layer" or "defense-in-depth"
