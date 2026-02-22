---
name: one-shot
description: "This skill should be used when running the full autonomous engineering workflow from plan to PR with video."
---

Run these steps in order. Do not do anything else.

**Step 0a: Activate Ralph Loop.** Run this command via the Bash tool:

```bash
bash ./plugins/soleur/scripts/setup-ralph-loop.sh "finish all slash commands" --completion-promise "DONE"
```

**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), pull latest and create a feature branch named `feat/one-shot-<slugified-arguments>` before proceeding. Parallel agents on the same repo cause silent merge conflicts when both work on main.

1. Use the **Skill tool**: `skill: soleur:plan`, args: "$ARGUMENTS"
2. Use the **Skill tool**: `skill: soleur:deepen-plan`
3. Use the **Skill tool**: `skill: soleur:work`
4. Use the **Skill tool**: `skill: soleur:review`
5. Use the **Skill tool**: `skill: soleur:resolve-todo-parallel`
6. Use the **Skill tool**: `skill: soleur:compound`
7. Use the **Skill tool**: `skill: soleur:test-browser`
8. Use the **Skill tool**: `skill: soleur:feature-video`
9. Output `<promise>DONE</promise>` when video is in PR

CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop.

Start with step 1 now.
