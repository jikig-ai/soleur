# Spec: Fix Security Scanning Alerts + CI Gate

**Issue:** #2417
**Branch:** feat-fix-security-scanning-alerts
**PR:** #2416

## Problem Statement

21 open CodeQL alerts (6 critical, 12 high, 3 medium) in the GitHub Security tab create
noise and block adoption of CodeQL as a required CI check. All alerts are false positives
-- the flagged code has proper defenses. PRs can currently merge with new security
findings because CodeQL is not a required status check.

## Goals

1. Zero open critical/high CodeQL alerts on main
2. PRs blocked from merging if CodeQL finds new critical/high alerts
3. Per-alert dismissal with documented reasoning for audit trail

## Non-Goals

- Adding inline CodeQL suppression comments
- Custom CodeQL workflow (default setup is sufficient)
- Additional SAST tools (semgrep, etc.)
- Switching CodeQL threat model (deferred follow-up)

## Functional Requirements

- **FR1:** All 21 open CodeQL alerts dismissed via GitHub API with per-alert reasoning
- **FR2:** CodeQL added as required status check in the "CI Required" repository ruleset
- **FR3:** Dismissal reasons use correct GitHub API format (space-separated, not snake_case)

## Technical Requirements

- **TR1:** API dismissals categorize test/tooling alerts as `"used in tests"` and
  production alerts as `"false positive"`
- **TR2:** Each dismissal includes a comment explaining the specific defense present
- **TR3:** Ruleset update adds CodeQL check alongside existing `test`, `dependency-review`,
  `e2e` checks
- **TR4:** Verification that the gate works by confirming CodeQL check appears on PRs

## Acceptance Criteria

- [ ] `gh api repos/jikig-ai/soleur/code-scanning/alerts --jq '[.[] | select(.state == "open") | select(.rule.security_severity_level == "critical" or .rule.security_severity_level == "high")] | length'` returns `0`
- [ ] "CI Required" ruleset includes CodeQL status check
- [ ] Next PR to main shows CodeQL as a required check
