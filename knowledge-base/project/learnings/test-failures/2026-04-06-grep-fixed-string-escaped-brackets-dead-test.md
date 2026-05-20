---
title: grep -qF with escaped brackets creates dead test branches
date: 2026-04-06
category: shell-scripting
tags: [grep, shell-testing, dead-code, test-coverage]
symptoms: [grep -qF with escaped brackets created dead test branch, test_critical_email_subject always fell through to fallback]
module: System
synced_to: []
component: testing_framework
problem_type: test_failure
resolution_type: test_fix
root_cause: logic_error
severity: low
---

# Learning: grep -qF with escaped brackets creates dead test branches

## Problem

When writing a shell test to verify `[CRITICAL]` appeared in curl args, `grep -qF '\\[CRITICAL\\]'` was used. With `-F` (fixed-string mode), grep treats all characters literally — including backslashes. The pattern searched for the literal string `\[CRITICAL\]` (with backslashes), which never appears in the actual JSON payload containing `[CRITICAL]`. The first branch was dead code, and the fallback (checking for plain `CRITICAL`) always ran, duplicating an existing test.

## Solution

Removed the duplicate `test_critical_email_subject` entirely. The existing `test_critical_threshold` already verified CRITICAL appeared in curl args with the Resend API URL. No additional bracket-checking test was needed.

## Key Insight

`grep -F` disables ALL regex interpretation — brackets, dots, stars, AND backslashes are all literal. When you want to match a literal `[` character, `-F` already treats `[` literally, so no escaping is needed: `grep -qF '[CRITICAL]'` matches `[CRITICAL]`. Adding backslash escapes in `-F` mode searches for actual backslash characters in the input, creating silently dead conditions.

## Session Errors

**Dead grep branch in test_critical_email_subject** — The test appeared to pass (via fallback) but the primary assertion never executed. Caught by code-simplicity-reviewer during post-implementation review. **Prevention:** When writing grep assertions in shell tests, verify the primary branch matches by temporarily removing the fallback and confirming the test still passes.

## See Also

- `knowledge-base/project/learnings/integration-issues/2026-04-05-shell-mock-testing-and-disk-monitoring-provisioning.md` — related shell mock testing patterns

## Tags

category: test-failures
module: System
