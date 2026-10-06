---
name: soleur-dspy-ruby
description: "This skill should be used when working with DSPy.rb, a Ruby framework for type-safe, composable LLM applications."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/dspy-ruby/SKILL.md`, relative to the plugin root.
