# Learning: security_reminder_hook blocks workflow file edits

## Problem
When editing `.github/workflows/*.yml` files, the `PreToolUse:Edit` hook (`security_reminder_hook.py`) returns an error-formatted response that can cause the Edit tool to treat the operation as blocked. The first edit attempt to `build-web-platform.yml` did not apply despite the hook being informational (warning about injection risks, not blocking for cause).

## Solution
Re-attempt the edit after the hook warning. The hook is advisory — it warns about GitHub Actions injection patterns (untrusted input in `run:` blocks) but does not actually prevent the edit. The error format in the hook response can mislead the agent into thinking the edit failed.

## Key Insight
The security_reminder_hook's error-formatted output creates ambiguity about whether the edit was applied. When editing workflow files for security-improving changes (like SHA pinning), expect the hook warning and verify the edit applied by re-reading the file.

## Tags
category: integration-issues
module: hooks
