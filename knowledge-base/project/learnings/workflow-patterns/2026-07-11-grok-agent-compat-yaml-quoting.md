---
title: Grok agent compat stubs require YAML-quoted descriptions
date: 2026-07-11
category: workflow-patterns
tags: [grok, agent-discoverability, yaml, phase-e]
---

# Learning: Grok agent compat stubs require YAML-quoted descriptions

## Problem

Phase E (#6324) generated 67 thin compat stubs under `.grok/agents/`. Two agents (`security-sentinel`, `data-integrity-guardian`) were absent from `grok inspect` despite files on disk.

## Root cause

Frontmatter `description` fields contained unquoted `:` and `§` characters. Grok's agent parser silently skipped those stubs.

## Solution

`sync-grok-agent-compat.ts` now emits `description: "..."` with escaped double quotes for all stubs.

## Verification

```bash
grok inspect 2>&1 | rg 'soleur:engineering:review:security-sentinel'
cd plugins/soleur && bun test test/grok-agent-discoverability.test.ts
```

## Key insight

Project-level agents live in flat `.grok/agents/*.md` (not `.grok/agents/soleur/`). Grok does not recurse into nested plugin `agents/**` paths — compat stubs must be flat project agents with qualified `name:` in frontmatter.