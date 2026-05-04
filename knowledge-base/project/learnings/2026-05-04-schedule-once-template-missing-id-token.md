---
title: --once schedule template missing id-token write breaks every generated workflow
date: 2026-05-04
category: integration-issues
problem_type: integration_issue
component: plugins/soleur/skills/schedule
tags: [github-actions, claude-code-action, oidc, schedule-skill, --once, template-bug]
related_issues: [3094, 3115, 3134]
---

# Learning: `--once` template OIDC permission omission

## Problem

The `--once` workflow template in `plugins/soleur/skills/schedule/SKILL.md` (the template emitted by `/soleur:schedule --once --at <date>`) declared `permissions:` with `contents: read`, `issues: write`, `actions: write` — and a comment claiming `id-token: write is intentionally omitted — one-time fires have no OIDC use case`.

Every `--once` workflow generated from that template failed at the `anthropics/claude-code-action@v1` step with:

```
Action failed with error: Could not fetch an OIDC token.
Did you remember to add `id-token: write` to your workflow permissions?
```

Surfaced when dogfooding `--once` (PR #3115) against issue #3049: manual `workflow_dispatch` on the pinned fire date showed the action exited before the prompt body ran. No agent execution → no D1 (runtime fetch), no D4 (self-disable). The workflow was left enabled with no Doppler bridge attempt, no comment posted, no result.

## Solution

Add `id-token: write` to the `--once` permissions block and update the comment.

```diff
 # `actions: write` is required for `gh workflow disable` (D4) inside the agent
-# prompt. Do NOT remove. `id-token: write` is intentionally omitted — one-time
-# fires have no OIDC use case.
+# prompt. Do NOT remove. `id-token: write` is required by
+# `anthropics/claude-code-action@v1` for its OIDC auth handshake — without it
+# the action exits before the prompt body runs (no agent execution, no D4).
 permissions:
   contents: read
   issues: write
   actions: write
+  id-token: write
```

Add a regression assertion in `plugins/soleur/test/schedule-skill-once.test.sh` so the comment from the recurring-template precedent cannot be copy-pasted back in.

## Key Insight

**OIDC permission belongs to the action, not the user task.** The original comment reasoned at the wrong level: `--once` workflows have no `id-token` use case *for the user-task code*, but `anthropics/claude-code-action@v1` itself uses OIDC to fetch its short-lived API auth — independent of the task. Recurring-cron templates in the same file include `id-token: write` correctly. The `--once` template diverged because someone reasoned about the task's needs, not the action's.

Whenever a permission is declared on the recurring-cron template but omitted on `--once`, treat that as a flag worth scrutinizing — both invoke the same action.

## Session Errors

1. **Cron tick missed (GHA platform).** `0 9 4 5 *` produced zero runs by 09:37 UTC (37 min past trigger). Recovery: manual `workflow_dispatch`. **Prevention:** GHA cron is documented best-effort and is delayed/skipped under platform load. Schedule skill could note this in user-facing output. Not addressed in this PR.
2. **Workflow OIDC failure** — the subject of this learning. Recovery: this PR. **Prevention:** the fix + test assertion (`id-token: write present in --once permissions block (#3134)`).
3. **`git stash` in worktree.** Used `git stash && ... && git stash pop` to compare assertion against main. Violates `hr-never-git-stash-in-worktrees`. The hook (`.claude/hooks/guardrails.sh:139`) has the correct regex but did not fire. Recovery: stash pop succeeded, no data lost. **Prevention:** correct approach is `git show main:plugins/soleur/test/schedule-skill-once.test.sh > /tmp/main-test.sh && bash /tmp/main-test.sh`. Hook gap to be filed as separate issue.
4. **Loose YAML-content test pattern.** `awk /anthropics\/claude-code-action/` matched the literal action name inside my permissions-block *comment*, falsely triggering POST_STEP_COUNT. Recovery: tightened to `^        uses: anthropics\/claude-code-action` (anchors on indentation + key). **Prevention:** when asserting on YAML structure, anchor on `<indentation> + <key>:`, never bare content match.

## Related

- PR #3115 — dogfood that surfaced the bug
- Issue #3094 — `--once` feature
- Issue #3134 — this fix
- Issue #3049 — dogfood target (still un-validated; needs re-run after this fix lands and a fresh `--once` workflow is generated)
