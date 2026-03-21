# Learning: Claude Code Bash tool escapes exclamation marks in all shell contexts

## Problem

When testing a `node -e "if(!r.ok)..."` one-liner via the Bash tool, the `!` character was consistently escaped to `\!`, causing Node.js SyntaxError. This happened in double quotes, single quotes, and even in files written via shell `echo`. The escaping appeared at the byte level (hex `5c 21` instead of `21`).

## Solution

Use the Write tool (not Bash) to create files containing `!` characters. The Write tool bypasses shell processing entirely. For testing:

```bash
# Instead of: node -e "if(!r.ok)..."  (Bash tool escapes ! to \!)
# Write the JS to a file first:
Write tool -> /tmp/test.js -> node /tmp/test.js
```

This is a testing artifact only. Dockerfiles written via the Edit tool contain the correct `!` character, and Docker's `/bin/sh -c` does not perform history expansion.

## Key Insight

The Claude Code Bash tool applies exclamation mark escaping regardless of quoting context. When testing commands that contain `!`, write them to a file first using the Write tool, then execute the file. Do not spend time debugging shell quoting — it is a tool-level behavior, not a shell behavior.

## Tags

category: integration-issues
module: claude-code
