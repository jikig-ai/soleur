---
name: soleur-marketing-fact-checker
description: "Verifies factual claims, statistics, and attributed quotes in drafts by fetching cited URLs and confirming source support. Use soleur:marketing:copywriter for marketing copy; use content-writer for blog articles; use this agent for citation verification."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `agents/marketing/fact-checker.md`, relative to the plugin root.
