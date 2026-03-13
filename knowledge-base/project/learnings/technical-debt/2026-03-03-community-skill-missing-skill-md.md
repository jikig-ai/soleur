---
title: Community skill directory missing SKILL.md
date: 2026-03-03
category: technical-debt
tags: [plugin-structure, skills, community]
severity: low
---

# Community Skill Missing SKILL.md

## Problem

The `plugins/soleur/skills/community/` directory contains only `scripts/` with no `SKILL.md` file. This makes it structurally incomplete -- it would fail the `components.test.ts` validation test that requires every skill directory to have a `SKILL.md`.

The skill likely avoids the test because skill discovery looks for `skills/*/SKILL.md` and skips directories without one.

## Key Insight

Either add a `SKILL.md` to make it a proper skill, or move the scripts to a shared `scripts/` location if they are utility scripts not meant to be a standalone skill.

## Tags

plugin-structure, skills, community
