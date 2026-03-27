---
adr: ADR-014
title: Subagent Output Merging
status: active
date: 2026-03-27
---

# ADR-014: Subagent Output Merging

## Context

Parallel fan-out of 6 subagents exceeded the 5-subagent constitution limit. Need to reduce count without losing parallelism.

## Decision

When a parallel subagent's output feeds exclusively to one other subagent (producer-consumer pair), merge producer into consumer. Example: Category Classifier merged into Documentation Writer (exclusive dependency). Preserves parallelism while reducing inter-agent data flow.

## Consequences

Respects resource guardrails without sacrificing parallel performance. Skill SKILL.md must have zero references to removed subagent names. Constitution uses generic language for limits rather than hardcoded counts, enabling future adjustment.
