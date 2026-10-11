---
name: soleur-frontend-anti-slop
description: "This skill should be used when auditing React/Next.js source for Hallmark-adapted anti-AI-slop patterns via a deterministic Tailwind/JSX scanner."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/frontend-anti-slop/SKILL.md`, relative to the plugin root.
