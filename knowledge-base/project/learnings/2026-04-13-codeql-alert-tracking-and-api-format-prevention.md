---
title: CodeQL Alert Tracking and GitHub API Format Prevention
date: 2026-04-13
category: security
tags: [codeql, github-api, automation, testing]
symptoms: "Security alerts surfaced only via email; API calls failed with 422 on wrong parameter format; file read attempts used wrong paths"
---

# CodeQL Alert Tracking and GitHub API Format Prevention

## Problem
CodeQL alerts routed to email without GitHub issue tracking. Two manually dismissed alerts (one mitigated, one stale) were never recorded. Auto-workflow created but test gaps remain.

## Prevention Strategies

### 1. Alert Lifecycle Tracking (Main Problem)
- **Add to constitution.md**: "When a security tool (CodeQL, Dependabot, SAST) emails alerts without auto-creating issues, create a workflow that emits GitHub issues or creates GitHub Security Advisories. Email-only tracking is not auditable."
- **Test case**: Mock CodeQL email alerts → verify auto-issue creation in `CODEQL_ALERTS.test.yml`
- **Workaround**: Add `gh secret set GITHUB_TOKEN` gate in next codeql-scan-to-issues PR before merging

### 2. GitHub API Format Violations (session error #1)
- **Learning**: GitHub API dismissal endpoint requires `dismissed_reason` as single spaced word (e.g., `"not vulnerable"`, `"used in tests"`), not snake_case. HTTP 422 without clear error message.
- **Prevention**: Add test fixture in `plugins/soleur/security/` with hardcoded valid/invalid reason strings. Schema validation before API call.
- **Code pattern**: Grep for `gh api` calls with `dismissed_reason` → validate against whitelist before execution.

### 3. Path Resolution in Worktrees (session error #2)
- **Rule addition to AGENTS.md**: "When debugging in a worktree, never read from bare repo path (`/home/.../soleur/<file>`) — use `git show HEAD:<file>` or `Read` tool with worktree path only. Bare repos have no working tree; reads return stale content."
- **Test**: Session-start audit script that detects bare repo CWD + Read tool call → warn/block

### 4. Git Operations on Non-Repos (session error #3)
- **Guard**: Validate `git rev-parse --git-dir` before `git -C` operations in CI/scripts. Fail fast with "Not a git repository" instead of silent failure.
- **Pattern**: `if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then exit 1; fi`

## Test Cases
1. **Mock CodeQL workflow** → emits alert email → verify auto-issue created with correct label + body
2. **API format regression** → call endpoint with snake_case reason → confirm 422 error + validation message
3. **Bare repo guard** → run `git -C /tmp` without repo check → verify exit 1 + error message
4. **Worktree path audit** → session-start script flags bare-repo Read attempts
