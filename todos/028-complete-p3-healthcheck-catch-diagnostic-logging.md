---
status: complete
priority: p3
issue_id: 818
tags: [code-review, docker, observability]
dependencies: []
---

# Add diagnostic logging to HEALTHCHECK .catch() handler

## Problem Statement

The `.catch(() => process.exit(1))` in the web-platform Dockerfile HEALTHCHECK discards all error details. When health checks fail, `docker inspect --format='{{json .State.Health}}'` shows no diagnostic output, making it harder to distinguish between connection refused, DNS failure, and timeout.

## Findings

- Security review agent flagged this as LOW severity, optional improvement
- The current behavior is correct (exit code 1 = unhealthy) but provides no debugging context
- Docker captures stdout/stderr from HEALTHCHECK commands in the health log

## Proposed Solutions

### Option A: Add console.error to .catch() (Recommended)

Change `.catch(() => process.exit(1))` to `.catch(e=>{console.error(e.message);process.exit(1)})`

- **Pros:** Populates Docker health logs with error reason, zero runtime cost
- **Cons:** Slightly longer one-liner
- **Effort:** Small
- **Risk:** None

## Recommended Action

(To be filled during triage)

## Technical Details

- **File:** `apps/web-platform/Dockerfile:38`

## Acceptance Criteria

- [ ] `docker inspect` health log shows error message on failure
- [ ] Exit code 1 behavior preserved

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-20 | Created from code review of PR #822 | Security agent finding #4 |

## Resources

- PR #822
- Issue #818
