---
module: knowledge-base
date: 2026-02-12
problem_type: best_practice
component: documentation
tags: [documentation, overview, component-counts, restructure]
severity: high
---

# Overview Documentation Becomes Stale After Major Restructures

## Context

The v2.0.0 restructure consolidated 26 commands into 8 (moving 18 to skills), reorganized agents under domain-first hierarchy, and added many new skills. The overview README and component docs were not updated to reflect these changes.

## Pattern

After any MAJOR version bump or structural reorganization, the overview documentation (`knowledge-base/overview/`) must be refreshed:

- `README.md` component counts table
- `components/agents.md` - verify listed agents match actual files
- `components/commands.md` - verify listed commands match actual files
- `components/skills.md` - verify listed skills match actual directories

## Prevention

Add overview doc verification to the versioning triad checklist, especially for MAJOR bumps. The `/soleur:sync overview` command can detect these drift issues.
