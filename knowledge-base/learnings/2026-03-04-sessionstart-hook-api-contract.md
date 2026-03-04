---
title: "SessionStart hook API contract: matcher values, hookEventName, and additionalContext"
date: 2026-03-04
category: integration-issues
tags: [claude-code, hooks, sessionstart, api]
module: plugins/soleur/hooks
---

# Learning: SessionStart hook API contract

## Problem

When implementing a SessionStart welcome hook, multiple review agents flagged the `matcher: "startup"` value and `hookEventName` field as unverified or incorrect. One agent cited an internal migration plan that recommended omitting `hookEventName`, while another flagged `matcher: "startup"` as undocumented. Both claims were wrong — the upstream spec documents both fields.

## Solution

Verified against the official Claude Code hooks reference at code.claude.com/docs/en/hooks:

1. **SessionStart matcher values** are documented: `startup`, `resume`, `clear`, `compact`. The matcher filters on "how the session started."
2. **`hookEventName`** is a required field inside `hookSpecificOutput`. The docs state: "It requires a `hookEventName` field set to the event name."
3. **`additionalContext`** (not `systemMessage`) is the correct field for injecting context that Claude can see. `systemMessage` shows a warning to the user.
4. **Exit codes**: 0 = success (stdout parsed for JSON), 2 = blocking error (stderr shown), other = non-blocking error.

Correct JSON output for a SessionStart hook:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Context text that Claude will see."
  }
}
```

## Key Insight

Internal migration plans and review agent suggestions about external APIs must be verified against the upstream spec before acting. The pattern-recognition agent cited a codebase-internal document as authority over the external API, leading to an incorrect edit that had to be reverted. Always treat internal docs about external APIs as hypotheses to verify.

## Tags
category: integration-issues
module: plugins/soleur/hooks
