---
name: soleur-code-to-prd
description: "This skill should be used when generating a PRD from a Next.js codebase for buyer/investor/agent handoff. Walks tracked files, redacts secrets, writes structured markdown to knowledge-base/product/prd/."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/code-to-prd/SKILL.md`, relative to the plugin root.
