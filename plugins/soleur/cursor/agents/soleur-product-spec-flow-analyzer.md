---
name: soleur-product-spec-flow-analyzer
description: "Use this agent when you have a specification, plan, feature description, or technical document that needs user flow analysis and gap identification. Use soleur:product:business-validator for pre-build idea validation; use soleur:product:cpo for cross-cutting product strategy."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `agents/product/spec-flow-analyzer.md`, relative to the plugin root.
