---
name: help
description: "List all available Soleur commands, agents, and skills"
argument-hint: ""
---

# Soleur Help

Display a formatted overview of all available Soleur capabilities. Read the plugin manifest to get current counts rather than relying on hardcoded values.

## Step 1: Read Plugin Manifest

Use the **Read tool** to read `plugins/soleur/.claude-plugin/plugin.json` to get the plugin version and metadata.

If that path does not exist, try reading from `~/.claude/plugins/*/soleur/.claude-plugin/plugin.json`.

## Step 2: Count Components

Use the **Glob tool** to count components. Make all four calls in parallel in a single message:

1. **Count agents:** Use pattern `**/*.md` with path `plugins/soleur/agents` -- count the returned file paths
2. **Count commands:** Use pattern `*.md` with path `plugins/soleur/commands` -- count the returned file paths
3. **Count skills:** Use pattern `**/SKILL.md` with path `plugins/soleur/skills` -- count the returned file paths (one SKILL.md per skill)
4. **Count agent domains:** From the agent file paths in result 1, extract the unique top-level directory names (the first path segment after `agents/`) and count them

If the plugin paths do not exist, fall back to the installed plugin paths under `~/.claude/plugins/`.

## Step 2.5: Harness-aware command names

Detect the active harness before printing commands:

- **Claude Code:** commands use the `/soleur:` prefix (`/soleur:go`, `/soleur:sync`, `/soleur:help`). Workflow skills are invoked via the **Skill tool** (`soleur:<skill>`).
- **Grok Build:** commands are unqualified (`/go`, `/sync`, `/help`). Workflow skills are invoked via **slash commands** (`/brainstorm`, `/one-shot`, …) — not `/soleur:go`.
- Implementation reference: `plugins/soleur/lib/harness.ts` (`routingInstructions`, `formatSkillInvocation`).

Use the matching column in Step 3 below.

## Step 3: Output the Help Reference

Present the following formatted overview. Replace placeholder counts with actual values from Step 2. **Print the Claude block OR the Grok block** based on Step 2.5 — not both.

### Claude Code

```text
Soleur - The Company-as-a-Service Platform

COMMANDS:
  /soleur:go <what you want>  The recommended way to use Soleur
  /soleur:sync                Populate knowledge-base from existing codebase
  /soleur:help                This help listing

WORKFLOW SKILLS (invoked via /soleur:go or directly via Skill tool):
  brainstorm                  Explore requirements and approaches
  plan                        Create an implementation plan
  work                        Execute the plan systematically
  review                      Run multi-agent code review
  compound                    Capture learnings from solved problems
  one-shot                    Full autonomous engineering workflow

AGENTS: [N] agents across [M] categories
  review    ([count])  Code review, security, performance, patterns
  research  ([count])  Codebase analysis, best practices, docs
  design    ([count])  Domain-driven design
  workflow  ([count])  PR comments, spec analysis

SKILLS: [N] skills
  [List all skills found with brief descriptions]

MCP SERVERS:
  context7                    Framework documentation lookup

Quick start: /soleur:go <what you want to do>
Full docs:   See plugins/soleur/README.md
```

### Grok Build

```text
Soleur - The Company-as-a-Service Platform

COMMANDS:
  /go <what you want>   The recommended way to use Soleur
  /sync                 Populate knowledge-base from existing codebase
  /help                 This help listing

WORKFLOW SKILLS (invoked via /go or directly via slash command):
  brainstorm            Explore requirements and approaches
  plan                  Create an implementation plan
  work                  Execute the plan systematically
  review                Run multi-agent code review
  compound              Capture learnings from solved problems
  one-shot              Full autonomous engineering workflow

AGENTS: [N] agents across [M] categories
  (same category breakdown as Claude block)

SKILLS: [N] skills
  (list all skills — invoke as /<skill-name>)

MCP SERVERS:
  context7              Framework documentation lookup

Quick start: /go <what you want to do>
Full docs:   See plugins/soleur/README.md and knowledge-base/engineering/grok-onboarding.md
```

Replace all `[N]`, `[M]`, and `[count]` placeholders with actual values from Step 2. List all skills found, not just a subset.

## Output Rules

- Keep the output compact and scannable
- Use fixed-width alignment for command names and descriptions
- Do not add emoji
- Do not truncate any commands or skills -- list everything found