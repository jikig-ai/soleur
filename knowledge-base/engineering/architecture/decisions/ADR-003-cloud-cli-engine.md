---
adr: ADR-003
title: Cloud CLI Engine
status: active
date: 2026-03-27
---

# ADR-003: Cloud CLI Engine

## Context

Users need both visibility (web dashboard) and autonomous execution (orchestration tools like Task, Skill, Bash). Full web-native platform loses 65-70% of agent capability.

## Decision

Agents execute on cloud-hosted Claude Code instances. Web app is a thin view/control layer over the CLI engine. Preserves 100% of orchestration value.

## Consequences

67.7% of agent code is prose (portable). 57.9% of skills are non-portable (depend on orchestration tools). Cloud CLI sidesteps portability by keeping the engine unchanged. Adds infrastructure complexity of managing CLI instances.
