---
name: soleur:help
description: "List all available Soleur commands, agents, and skills"
argument-hint: ""
---

# Soleur Help

Display a formatted overview of all available Soleur capabilities. Read the plugin manifest to get current counts rather than relying on hardcoded values.

## Step 1: Read Plugin Manifest

```bash
cat plugins/soleur/.claude-plugin/plugin.json
```

If that path does not exist, try the installed plugin location:

```bash
cat ~/.claude/plugins/*/soleur/.claude-plugin/plugin.json 2>/dev/null || echo "Plugin manifest not found"
```

## Step 2: Count Components

```bash
# Count agents
find plugins/soleur/agents -name "*.md" -type f 2>/dev/null | wc -l

# Count commands (all in soleur/ subdirectory)
find plugins/soleur/commands/soleur -name "*.md" -type f 2>/dev/null | wc -l

# Count skills
find plugins/soleur/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l

# Count agent categories
find plugins/soleur/agents -name "*.md" -not -name "README.md" 2>/dev/null | wc -l
```

If the plugin paths above do not exist, fall back to the installed plugin paths under `~/.claude/plugins/`.

## Step 3: Output the Help Reference

Present the following formatted overview. Replace placeholder counts with actual values from Step 2.

```text
Soleur - The Company-as-a-Service Platform

COMMANDS (all soleur: namespaced):
  /soleur:brainstorm <idea>   Explore requirements and approaches
  /soleur:plan                Create an implementation plan
  /soleur:work <plan>         Execute the plan systematically
  /soleur:review              Run multi-agent code review
  /soleur:compound            Capture learnings from solved problems
  /soleur:sync                Populate knowledge-base from existing codebase
  /soleur:help                This help listing
  /soleur:one-shot <feature>  Full autonomous engineering workflow

AGENTS: [N] agents across [M] categories
  review    ([count])  Code review, security, performance, patterns
  research  ([count])  Codebase analysis, best practices, docs
  design    ([count])  Domain-driven design
  workflow  ([count])  PR comments, spec analysis

SKILLS: [N] skills
  [List all skills found with brief descriptions]

MCP SERVERS:
  context7                    Framework documentation lookup

Quick start: /soleur:brainstorm <idea>
Full docs:   See plugins/soleur/README.md
```

Replace all `[N]`, `[M]`, and `[count]` placeholders with actual values from Step 2. List all skills found, not just a subset.

## Output Rules

- Keep the output compact and scannable
- Use fixed-width alignment for command names and descriptions
- Do not add emoji
- Do not truncate any commands or skills -- list everything found
