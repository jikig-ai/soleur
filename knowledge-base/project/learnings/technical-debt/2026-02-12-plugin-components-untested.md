---
module: plugins/soleur
date: 2026-02-12
problem_type: best_practice
component: testing
tags: [testing, plugin, markdown, validation, coverage-gap]
severity: medium
---

# Plugin Markdown Components Have No Automated Tests

## Context

The telegram-bridge app has excellent test coverage (84 tests, 102% LOC ratio with factory patterns), but the plugin's 22 agents, 8 commands, and 35 skills have zero automated tests. This means YAML frontmatter errors, broken markdown structure, or missing required fields are only caught during manual use.

## Impact

- Broken frontmatter silently degrades agent/skill discovery
- Missing required fields (model, argument-hint) go unnoticed
- Convention violations (backtick references, wrong voice) accumulate

## Suggested Tests

- YAML frontmatter validation: required fields per component type
- Markdown structure checks: required sections, heading hierarchy
- Reference link validation: no broken links to references/, assets/, scripts/
- Convention compliance: third-person voice in descriptions, kebab-case filenames
