---
status: pending
priority: p2
issue_id: 864
tags: [code-review, security, infrastructure]
dependencies: []
---

# Deploy workflow uses root SSH user

## Problem Statement

The telegram-bridge deploy workflow SSHes into the production server as `root`. This violates least-privilege principle — a compromised GitHub Actions runner or supply-chain attack on `appleboy/ssh-action` would gain full root access to the server.

## Findings

- **Flagged by:** security-sentinel (MEDIUM, pre-existing), architecture-strategist
- **Location:** `.github/workflows/telegram-bridge-release.yml:44-45`
- **Pre-existing:** Yes — not introduced by PR #867

## Proposed Solutions

### Option A: Dedicated deploy user (Recommended)
Create a `deploy` user with docker group membership and write access to `/mnt/data/.env`.
- **Pros:** Limits blast radius, follows security best practices
- **Cons:** Requires server-side user provisioning
- **Effort:** Medium (Terraform + workflow update)
- **Risk:** Low

### Option B: Accept current pattern
Keep root for simplicity on single-operator infra.
- **Pros:** No changes needed
- **Cons:** Security risk persists
- **Effort:** None
- **Risk:** Ongoing

## Recommended Action

(To be filled during triage)

## Technical Details

- **Affected files:** `.github/workflows/telegram-bridge-release.yml`, server infra (Terraform)
- **Components:** CI/CD deploy pipeline, server access control

## Acceptance Criteria

- [ ] Deploy uses non-root user
- [ ] User has minimal required permissions (docker, /mnt/data write)
- [ ] Deploy workflow passes CI

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-20 | Created from code review of PR #867 | Pre-existing issue, flagged by security-sentinel |

## Resources

- PR: #867
- Issue: #864
