---
title: Review agent definitions live under the Soleur plugin root
date: 2026-09-28
category: tooling
tags: [review, agents, codex]
symptoms: [rg --files agents returns no such directory]
module: System
component: tooling
problem_type: workflow_issue
resolution_type: workflow_improvement
root_cause: incorrect_path_assumption
severity: low
---

# Review agent definitions live under the Soleur plugin root

## Problem

Looking for review agent definitions at repository-root `agents/` fails because this checkout stores them under `plugins/soleur/agents/`.

## Resolution

Use `rg --files plugins/soleur/agents` from the worktree root, or resolve canonical paths from the installed Soleur plugin root described in `plugins/soleur/codex/INSTRUCTIONS.md`.
