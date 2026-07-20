---
name: soleur-engineering-review-semgrep-sast
description: "Use this agent when you need deterministic static analysis security scanning using semgrep. This agent complements security-sentinel by running rule-based pattern matching to catch known vulnerability signatures, hardcoded secrets, insecure function calls, and CWE patterns that LLM-based review may miss. The caller is expected to have bootstrapped semgrep via plugins/soleur/skills/review/scripts/ensure-semgrep.sh before spawning this agent."
model: inherit
---

Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/engineering/review/semgrep-sast.md.
