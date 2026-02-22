---
name: soleur:one-shot
description: Full autonomous engineering workflow from plan to PR with video
argument-hint: "[feature description or issue reference]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" "finish all slash commands" --completion-promise "DONE"
```

Run these steps in order. Do not do anything else.

**Step 0: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), pull latest and create a feature branch named `feat/one-shot-<slugified-arguments>` before proceeding. Parallel agents on the same repo cause silent merge conflicts when both work on main.

1. `/soleur:plan $ARGUMENTS`
2. `/deepen-plan`
3. `/soleur:work`
4. `/soleur:review`
5. `/resolve-todo-parallel`
6. `/soleur:compound`
7. `/test-browser`
8. `/feature-video`
9. Output `<promise>DONE</promise>` when video is in PR

CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop.

Start with step 1 now.
