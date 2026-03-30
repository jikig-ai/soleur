---
status: complete
priority: p3
tags: [code-review, consistency]
---

# hookEventName field inconsistency between hook files

guardrails.sh omits `hookEventName` in deny JSON; pre-merge-rebase.sh includes it. Pre-existing cross-file inconsistency, not introduced by this branch. Both formats are accepted by the Claude Code harness.

**Resolution:** Pre-existing, not in scope for this PR. Track as minor cleanup.
