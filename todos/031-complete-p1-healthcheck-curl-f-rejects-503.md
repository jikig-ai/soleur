---
status: complete
priority: p1
issue_id: 864
tags: [code-review, infrastructure, docker]
dependencies: []
---

# Dockerfile HEALTHCHECK curl -f rejects 503, causing potential restart loops

## Problem Statement

This PR reduces `--start-period` from 120s to 10s, but `curl -f` treats HTTP 503 as failure (exit code 22). The health endpoint returns 503 ("degraded") during the ~120s grammY module resolution. Docker starts counting failures after 10s, marks unhealthy after ~100s (10s start + 3 retries x 30s), and may restart the container before the app finishes loading.

## Findings

- **Flagged by:** performance-oracle, security-sentinel
- **Location:** `apps/telegram-bridge/Dockerfile:28-29`
- **Introduced by:** This PR (reduced start-period from 120s to 10s without fixing curl -f)
- The CI deploy script correctly accepts 503 (`telegram-bridge-release.yml:87`), but Docker's own HEALTHCHECK does not
- On the old 120s start-period, failures during grammY loading were ignored; now they count

## Proposed Solutions

### Option A: Accept 503 in HEALTHCHECK (Recommended)

**Approach:** Replace `curl -f` with a status-code check that accepts both 200 and 503.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health | grep -qE '^(200|503)$' || exit 1
```

**Pros:** Health endpoint responding (even degraded) proves container is alive. Matches CI deploy script behavior.
**Cons:** Docker never marks container unhealthy during slow loading (acceptable — it will transition to 200 eventually, or the error state catch handles permanent failure).
**Effort:** Small
**Risk:** Low

### Option B: Increase start-period to 180s

**Approach:** Keep `curl -f`, increase `--start-period` to 180s.

**Pros:** Zero code change to curl command.
**Cons:** Wasteful — the whole point of the PR is that health responds immediately. Reverts to the timeout-increase pattern that failed 3 times before.
**Effort:** Small
**Risk:** Low

## Recommended Action

Option A — accept 503 in HEALTHCHECK.

## Technical Details

**Affected files:**
- `apps/telegram-bridge/Dockerfile:28-29`

## Acceptance Criteria

- [ ] HEALTHCHECK treats both 200 and 503 as healthy
- [ ] `--start-period=10s` is preserved
- [ ] Container is not marked unhealthy during normal slow boot

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-20 | Created from code review of PR #867 | 2 review agents flagged independently |
