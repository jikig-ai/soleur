---
name: soleur:one-shot
description: Full autonomous engineering workflow from plan to PR with video
argument-hint: "[feature description or issue reference]"
---

Run these steps in order. Do not do anything else.

**Step 0: Ensure branch isolation.** If on the default branch (main/master), create a feature branch before proceeding. Parallel agents on the same repo cause silent merge conflicts when both work on main.

```bash
current_branch=$(git branch --show-current)
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$default_branch" ]; then
  default_branch=$(git rev-parse --verify origin/main >/dev/null 2>&1 && echo "main" || echo "master")
fi
if [ "$current_branch" = "$default_branch" ]; then
  git pull origin "$default_branch"
  git checkout -b feat/one-shot-$(echo "$ARGUMENTS" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 40)
fi
```

1. `/ralph-wiggum:ralph-loop "finish all slash commands" --completion-promise "DONE"`
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
