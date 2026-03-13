---
title: Domain Leader Pattern and LLM-Based Domain Detection
date: 2026-02-21
category: agent-design
tags: [implementation-patterns, agents, commands, fragile keyword routing, no cross-agent coordination, marketing agents operating independently]
---

# Learning: Domain Leader Pattern and LLM-Based Domain Detection

## Problem

Soleur had 12 marketing agents but no coordinator. The brainstorm command used keyword substring matching for domain routing (scanning for "brand", "brand identity", etc.), which was fragile (false positives like "brand new feature") and not extensible to multiple domains.

## Solution

### Domain Leader Interface

Introduced a documented behavioral contract (not a runtime abstraction) for domain leaders. Each leader implements 4 phases: Assess, Recommend, Delegate, Review. The interface is documented in AGENTS.md, not enforced by code -- appropriate for 2 domains.

### Agent Absorption Pattern

Replaced `marketing-strategist` with `cmo` by absorbing all sharp edges into the new leader agent and adding orchestration capabilities. Key steps: copy sharp edges verbatim, add the 4-phase structure, update disambiguation refs in sibling agents, update NOTICE attribution.

### LLM Semantic Assessment

Replaced keyword substring matching in brainstorm Phase 0.5 with natural language assessment questions. The brainstorm command runs inside Claude -- leveraging semantic understanding is more accurate than pattern matching and requires no keyword list maintenance. Adding a new domain costs one assessment question (~5 lines) instead of a keyword table.

Backward compatibility preserved: brand workshop is a special case within marketing detection, offering both "Start brand workshop" and "Include marketing perspective" options.

## Key Insight

When extending a command that runs inside an LLM, prefer semantic assessment over keyword matching. LLMs are worse at substring matching than they are at understanding intent. The detection is non-deterministic but acceptable because domain assessments are brief and non-destructive. [Updated 2026-03-12] The confirmation gate was later removed — domain leaders now auto-fire without AskUserQuestion, both in brainstorm Phase 0.5 and via passive domain routing in AGENTS.md. Workshops remain explicitly user-invoked.

## Tags

category: implementation-patterns
module: agents, commands
symptoms: fragile keyword routing, no cross-agent coordination, marketing agents operating independently
