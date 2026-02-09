---
name: help
description: "List all available Soleur commands, agents, and skills"
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

# Count commands
find plugins/soleur/commands -name "*.md" -type f 2>/dev/null | wc -l

# Count skills
find plugins/soleur/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l

# Count agent categories
ls plugins/soleur/agents/ 2>/dev/null
```

If the plugin paths above do not exist, fall back to the installed plugin paths under `~/.claude/plugins/`.

## Step 3: Output the Help Reference

Present the following formatted overview. Replace placeholder counts with actual values from Step 2.

```text
Soleur - AI-powered development workflow

CORE WORKFLOW (run in order):
  /soleur:brainstorm <idea>   Explore requirements and approaches
  /soleur:plan                Create an implementation plan
  /soleur:work <plan>         Execute the plan systematically
  /soleur:review              Run multi-agent code review
  /soleur:compound            Capture learnings from solved problems
  /soleur:sync                Populate knowledge-base from existing codebase

PLANNING & REVIEW:
  /deepen-plan                Enhance plan sections with parallel research
  /plan_review                Multi-agent plan review

CODE QUALITY:
  /resolve_parallel           Resolve TODO comments in parallel
  /resolve_pr_parallel        Resolve PR comments in parallel
  /resolve_todo_parallel      Resolve todo items in parallel

UTILITIES:
  /changelog                  Generate changelogs from recent merges
  /triage                     Triage and prioritize findings
  /report-bug                 Report a Soleur plugin bug
  /reproduce-bug              Reproduce bugs using logs and console
  /create-agent-skill         Create or edit Claude Code skills
  /generate_command            Generate new slash commands
  /heal-skill                 Fix skill documentation issues
  /test-browser               Run browser tests on PR-affected pages
  /feature-video              Record video walkthroughs for PRs
  /xcode-test                 Build and test iOS apps on simulator

AGENTS: [N] agents across [M] categories
  review    ([count])  Code review, security, performance, patterns
  research  ([count])  Codebase analysis, best practices, docs
  design    ([count])  UI implementation, Figma sync, iteration
  workflow  ([count])  Bug reproduction, linting, PR comments
  docs      ([count])  README writing, documentation

SKILLS: [N] skills including
  agent-browser               CLI-based browser automation
  agent-native-architecture   Prompt-native agent design
  compound-docs               Capture solved problems as docs
  dhh-rails-style             Ruby/Rails in DHH's style
  frontend-design             Production-grade frontend interfaces
  gemini-imagegen             Image generation via Gemini API
  git-worktree                Parallel development with worktrees
  rclone                      Upload files to cloud storage
  spec-templates              Specification templates

MCP SERVERS:
  context7                    Framework documentation lookup

Quick start: /soleur:brainstorm <idea>
Full docs:   See plugins/soleur/README.md
```

Replace all `[N]`, `[M]`, and `[count]` placeholders with actual values from Step 2. List all skills found, not just the subset above.

## Output Rules

- Keep the output compact and scannable
- Use fixed-width alignment for command names and descriptions
- Do not add emoji
- Do not truncate any commands or skills -- list everything found
