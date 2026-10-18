---
mode: subagent
description: "Use this agent when you need deterministic static analysis security scanning using semgrep. This agent complements soleur:engineering:review:security-sentinel by running rule-based pattern matching to catch known vulnerability signatures, hardcoded secrets, insecure function calls, and CWE patterns that LLM-based review may miss. The caller is expected to have bootstrapped semgrep via plugins/soleur/skills/review/scripts/ensure-semgrep.sh before spawning this agent."
---

Stub for the canonical agent `soleur:engineering:review:semgrep-sast`. OpenCode derives an agent's id from this
file's path, so the canonical `name:` frontmatter is deliberately not repeated here.

Read and follow the canonical agent definition at `__SOLEUR_PLUGIN_ROOT__/agents/engineering/review/semgrep-sast.md`,
then work as that agent.
