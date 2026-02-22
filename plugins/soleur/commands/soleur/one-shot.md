---
name: soleur:one-shot
description: Full autonomous engineering workflow from plan to PR with video
argument-hint: "[feature description or issue reference]"
---

Run these steps in order. Do not do anything else.

**Step 0: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), pull latest and create a feature branch named `feat/one-shot-<slugified-arguments>` before proceeding. Parallel agents on the same repo cause silent merge conflicts when both work on main.

1. `/ralph-loop:ralph-loop "finish all slash commands" --completion-promise "DONE"`
2. `/soleur:plan $ARGUMENTS`
3. `/deepen-plan`
4. `/soleur:work`
5. `/soleur:review`
6. `/resolve-todo-parallel`
7. `/soleur:compound`
8. `/test-browser`
9. `/feature-video`
10. Output `<promise>DONE</promise>` when video is in PR

Start with step 1 now.
