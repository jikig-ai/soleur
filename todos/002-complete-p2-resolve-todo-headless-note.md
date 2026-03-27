---
status: complete
priority: p2
issue_id: 1170
tags: [code-review, quality]
dependencies: []
---

# Add note explaining why resolve-todo-parallel omits --headless

## Problem Statement

In work/SKILL.md Phase 4, steps 1, 3, and 4 include the headless forwarding parenthetical but step 2 (resolve-todo-parallel) does not. Without explanation, this looks like an oversight.

## Findings

- The plan explicitly states: "resolve-todo-parallel does not accept --headless (it has no interactive prompts)"
- This explanation did not carry into the implementation

## Proposed Solutions

1. Add parenthetical note to step 2 explaining the omission

## Acceptance Criteria

- [ ] Step 2 includes explanatory note about no --headless support
