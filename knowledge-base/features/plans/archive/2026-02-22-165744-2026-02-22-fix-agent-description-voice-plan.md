# Plan: Fix Agent Description Voice (#222)

**Date:** 2026-02-22
**Issue:** #222 - Fix agent description voice: use imperative form for 3 agents
**Type:** Bug fix (PATCH bump)

## Problem

Three agent descriptions use third-person phrasing instead of the required imperative form per AGENTS.md compliance checklist. Agent descriptions must use "Use this agent when..." format.

## Changes

### 1. `plugins/soleur/agents/engineering/discovery/functional-discovery.md` (line 3)

**Before:** `"This agent should be used when running /plan to check whether..."`
**After:** `"Use this agent when running /plan and the project uses a stack not covered by built-in agents. This agent queries external registries for community agents and skills matching the detected stack gap, presents trusted suggestions, and installs approved artifacts with provenance tracking. Use agent-finder for stack-gap detection; use this agent to find agents for a missing tech stack."`

Wait -- re-reading the issue more carefully. The current description says "This agent should be used when running /plan to check whether community registries already have skills or agents with similar functionality to the feature being planned." The fix is simpler: just change "This agent should be used when" to "Use this agent when".

**Before:** `"This agent should be used when running /plan to check..."`
**After:** `"Use this agent when running /plan to check..."`

### 2. `plugins/soleur/agents/marketing/growth-strategist.md` (line 3)

**Before:** `"This agent performs content strategy analysis including keyword research..."`
**After:** `"Use this agent when you need content strategy analysis including keyword research, content auditing for search intent alignment, content gap analysis, content planning, and GEO/AEO (Generative Engine Optimization / AI Engine Optimization) auditing at the content level. It complements the seo-aeo-analyst (which handles technical SEO correctness) by focusing on whether content matches what people actually search for."`

### 3. `plugins/soleur/agents/marketing/seo-aeo-analyst.md` (line 3)

**Before:** `"This agent analyzes Eleventy documentation sites for SEO and AEO..."`
**After:** `"Use this agent when you need to analyze Eleventy documentation sites for SEO and AEO (AI Engine Optimization) opportunities. It audits structured data, meta tags, AI discoverability signals, and content quality, then produces actionable reports or generates fixes. Use growth-strategist for content strategy and keyword research; use programmatic-seo-specialist for scalable page generation; use this agent for technical SEO audits."`

## Version Bump

PATCH bump (bug fix). Update plugin.json, CHANGELOG.md, README.md.

## Risk

Zero. Text-only changes to YAML frontmatter description fields. No behavioral change.
