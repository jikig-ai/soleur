---
title: "Command-string-scanning PreToolUse hooks must skip glob/regex-metachar tokens"
date: 2026-06-08
category: best-practices
module: .claude/hooks
tags: [hooks, pretooluse, false-positive, bash, kb-domain-allowlist-guard]
pr: 5013
---

# Learning: a path-extracting Bash hook conflates *mentioned* paths with *written* paths

## Problem

`kb-domain-allowlist-guard.sh` (a PreToolUse `ask`-tier advisory) raised a spurious
approval prompt on routine commands like:

```bash
# verify no broken knowledge-base/*.md citations in the plan
grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' "$PLAN"
git add knowledge-base/project/plans/ knowledge-base/project/specs/x/tasks.md
```

The guard scans the **entire Bash command string** for the *first*
`knowledge-base/([^/[:space:]\"\']+)` substring and treats the captured token as the
write target's top-level segment. The first match here is the **comment**
(`knowledge-base/*.md` → segment `*.md`), not the real `git add` write under the
sanctioned `project/` domain. `*.md` is neither sanctioned nor on disk → false-positive
`ask`. A standalone grep pattern yields segment `[A-Za-z0-9` the same way. The guard
penalized the exact KB-citation-verification command the workflow recommends.

## Solution

Skip (`exit 0`, pass-through) when the extracted segment contains a glob/regex
metacharacter — `*`, `?`, `[`, or `]` — inserted right after the `BASH_REMATCH`
assignment, before the sanctioned-dir checks:

```bash
if [[ "$SEGMENT" == *['*?[]']* ]]; then
  exit 0
fi
```

Real KB path segments (directory names like `project`, files like `INDEX.md`) are
`[A-Za-z0-9._-]` only — they never contain those four chars. A metachar-bearing segment
is the **signature** of a comment or grep/regex pattern that merely *mentions* a
`knowledge-base/<glob>` path, not a real write target. The bracket expression `['*?[]']`
lists the four metacharacters as literal members (`]` via the leading-`]` `[]']` form);
it reuses the file's existing `[[ == ]]` glob idiom — no subprocess, `set -euo pipefail`-safe.

Proven by TDD: T11 (the reported comment-plus-real-write command) and T12 (a bare grep
pattern) both fired `ask` before the fix (RED: 10 passed, 2 failed) and pass through after
(GREEN: 12 passed, 0 failed). T1/T2/T8 — genuine new-domain creation (`observability`,
re-added `security`, `mkdir observability`) — still fire `ask`, so detection is intact.

## Key Insight

When a hook detects "a path that gets written" by substring-scanning a raw Bash command
(to catch `mkdir`/`cat >`/`mv`/`tee` without a full parser), it cannot distinguish a
**written** path from a **mentioned** one. The cheapest discriminator is the token's own
character class: a captured segment carrying a glob/regex metacharacter (`* ? [ ]`) came
from a comment or pattern, never from a real filesystem write target. Skip those rather
than widening the extraction regex (which would also have to model quoting and word
boundaries). This is advisory-drift tooling, not a security boundary — adversarial
metachar dirnames are explicitly out of scope per the guard's header.

## Session Errors

1. **Monitor armed on the wrong file.** Ran `bash scripts/test-all.sh > /tmp/test-all.log
   2>&1; echo "EXIT=$?"` as a backgrounded command, then armed a Monitor grepping
   `/tmp/test-all.log` for `EXIT=`. The `EXIT=` line is echoed *after* the redirect, so it
   lands in the **background-task output file**, not `/tmp/test-all.log` — the monitor
   would never have matched. **Recovery:** `TaskStop` the monitor, re-arm it against the
   task output file path. **Prevention:** when a backgrounded command redirects the
   payload (`> file.log`) but echoes its exit status separately, the status sink is the
   task output file — monitor that, or fold the status into the same redirect.
2. **Status probe exited 2.** A `git status --porcelain` probe chained `ls` on a
   not-yet-created `specs/` dir, which returned exit 2. Cosmetic — the porcelain output I
   needed printed first. **Prevention:** guard optional `ls` targets with `2>/dev/null ||
   true` in status-probe one-liners.

## Tags
category: best-practices
module: .claude/hooks
