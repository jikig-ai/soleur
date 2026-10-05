---
title: "A PreToolUse deny aborts the whole compound command — earlier side effects never ran"
date: 2026-10-05
category: workflow-issues
tags: [hooks, issue-filing, compound-commands, guardrails]
symptoms:
  - "gh issue create rejected '--body-file ... this gate cannot read' even though the file was 'just created' in the same command"
  - "cp/mkdir later found to have never executed"
module: .claude/hooks/guardrails.sh (filing gate)
---

# Learning: a PreToolUse deny aborts the whole compound command — earlier side effects never ran

## Problem

Filing two deferral issues for feat-open-web-egress, the command was shaped:

```bash
cp /tmp/body.md spec-dir/ && gh issue create --body-file /absolute/path/spec-dir/body.md --milestone "..."
```

The filing gate blocked the call with "this gate cannot read" the
`--body-file`. Retry with the absolute path produced the SAME error —
because the `cp` had never run: **a PreToolUse deny rejects the entire
command string before any part executes.** Side-effect steps earlier in the
chain are not partial — they are absent.

Compounding it: `/tmp` is not a path the hook can read (hook's filesystem
view differs from the exec sandbox), and relative paths resolve against the
hook's cwd, not the operator's.

## Solution

For hook-gated commands whose inputs must exist on disk:

1. Create the artifact in a separate tool call FIRST (write tool, or a
   standalone `cp`/`mkdir` exec — never bundled with the gated command).
2. Body files must live inside the repo tree (the hook reads through its own
   filesystem view; `/tmp` failed).
3. Absolute paths always.
4. The `User-Impact:` line must contain a taxonomy surface token
   (route/endpoint/page/screen/component/button/form/dashboard/CLI/
   command/email/notification/document/report/invoice/digest —
   `.claude/hooks/lib/user-surface-taxonomy.txt`), and `Fix-Size:` must be
   the literal `N lines / M files` with at least one dimension outside the
   inline threshold (n>100 or m>4; n≤100 AND m≤4 is refused as
   "fix it inline").
5. A `grep` pattern can itself trip a hook — a literal
   `doppler secrets set` inside a grep regex was denied as if it were the
   command; quote/split differently when searching for sensitive tokens.

## Key Insight

Treat every hook-gated command as atomic at the COMMAND level: if any part
fails a gate, NOTHING in that invocation ran. When a follow-up check then
finds the earlier artifact "missing," the explanation is atomicity, not a
race. The recovery pattern is always: side effects first (separate call),
gated command second.
