# Learning: Quoted dash strings in agent bash blocks trigger approval prompts

## Problem
The `functional-discovery` agent had two separate bash code blocks for checking already-installed community artifacts. At runtime, the agent model combined them into a single command using `echo "---"` as a separator. Claude Code's CLI safety heuristic flagged `"---"` as "quoted characters in flag names" and prompted the user for approval, blocking autonomous execution.

## Solution
Merged the two separate bash blocks into a single `;`-joined command in the agent prompt. Added an explicit note warning against `echo "---"` separators:

```bash
# Before (two blocks, agent adds echo "---" at runtime)
ls plugins/soleur/agents/community/ 2>/dev/null
ls -d plugins/soleur/skills/community-*/ 2>/dev/null

# After (single block, no separator needed)
ls plugins/soleur/agents/community/ 2>/dev/null; ls -d plugins/soleur/skills/community-*/ 2>/dev/null
```

## Key Insight
When agent prompts contain multiple bash code blocks that the model might combine at runtime, pre-combine them into a single block. Avoid any quoted strings that start with dashes (e.g., `"---"`, `"-flag"`) as Claude Code's CLI heuristic interprets these as potentially dangerous flag manipulation and triggers an approval prompt. The heuristic is "Command contains quoted characters in flag names."

## Tags
category: agent-prompt-design
module: functional-discovery
