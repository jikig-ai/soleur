---
name: compound
description: "Document a recently solved problem to compound your team's knowledge. Creates structured learnings in knowledge-base/project/learnings/."
---

# Compound

Capture problem solutions while context is fresh, creating structured documentation in `knowledge-base/project/learnings/` with YAML frontmatter for searchability.

## Usage

Activate this skill after solving a non-trivial problem. If context about the problem is not already in the conversation, use `ask_user` to request a brief description.

## Phase 0: Setup

Read project conventions from `GEMINI.md` if it exists. Apply conventions during documentation.

**Branch safety check:** Run `run_shell_command` with `git branch --show-current`. If the result is `main` or `master`, abort with: "Error: compound cannot run on main/master. Checkout a feature branch first."

## Phase 0.5: Session Error Inventory

Before writing any learning, enumerate ALL errors encountered in this session. Output a numbered list. This step cannot be skipped.

Include:

- Wrong file paths, directories, or branch confusion
- Failed shell commands or unexpected exit codes
- API errors or unexpected responses
- Wrong assumptions that required backtracking

If genuinely no errors occurred, output: "Session error inventory: none detected."

## Execution Strategy

Analyze the session context to extract the learning. Unlike the Claude Code version which spawns 5 parallel subagents, this version runs sequentially within the conversation:

### 1. Context Analysis

- Extract conversation history
- Identify problem type, component, symptoms
- Determine YAML frontmatter fields: title, date, category, tags

### 2. Solution Extraction

- Analyze investigation steps
- Identify root cause
- Extract working solution with code examples

### 3. Related Documentation Search

- Search `knowledge-base/project/learnings/` for related documentation using `grep_search`
- Identify cross-references and links
- Find related GitHub issues via `run_shell_command` with `gh issue list`

### 4. Prevention Strategy

- Develop prevention strategies
- Create best practices guidance
- Propose enforcement: hook (strongest), skill instruction (moderate), prose rule (weakest)

### 5. Write Learning File

Determine the optimal `knowledge-base/project/learnings/` category subdirectory. Create the file with this structure:

```markdown
---
title: "<descriptive title>"
date: YYYY-MM-DD
category: <category>
tags: [tag1, tag2]
---

# Learning: <title>

## Problem

<What went wrong or what was unclear>

## Solution

<What fixed it, with code examples>

## Key Insight

<The non-obvious takeaway>

## Session Errors

<Errors from Phase 0.5 inventory, each with a **Prevention:** line>
```

Use `write_file` to create the learning document.

### 6. Constitution Promotion

After writing the learning, check if the insight should be promoted to a project convention:

- If the learning addresses a recurring pattern → propose adding to project conventions
- If the learning exposes a gap in rules → propose a rule addition
- Use `ask_user` to confirm before modifying convention files

