---
name: soleur-engineering-review-semgrep-sast
description: "Use this agent when you need deterministic static analysis security scanning using semgrep. This agent complements soleur:engineering:review:security-sentinel by running rule-based pattern matching to catch known vulnerability signatures, hardcoded secrets, insecure function calls, and CWE patterns that LLM-based review may miss. The caller is expected to have bootstrapped semgrep via plugins/soleur/skills/review/scripts/ensure-semgrep.sh before spawning this agent."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `agents/engineering/review/semgrep-sast.md`, relative to the plugin root.
