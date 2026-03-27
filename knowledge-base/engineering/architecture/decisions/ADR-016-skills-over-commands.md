---
adr: ADR-016
title: Skills Over Commands
status: active
date: 2026-03-27
---

# ADR-016: Skills Over Commands

## Context

Core workflow stages (brainstorm, plan, work, review, compound) need to be discoverable by agents and invocable via the Skill tool. Commands are invisible to agents.

## Decision

Core workflow stages are skills under plugins/soleur/skills/, not commands. Only three commands remain: go, sync, help using soleur: prefix. Skills get soleur: prefix automatically from plugin namespace. The name field in frontmatter should NOT include the prefix.

## Consequences

Skills are discoverable in the plugin system and invocable via Skill tool. Agents can chain workflows (e.g., one-shot sequences plan then work). Command namespace stays clean. Skill loader does not recurse into subdirectories — skills must be flat.
