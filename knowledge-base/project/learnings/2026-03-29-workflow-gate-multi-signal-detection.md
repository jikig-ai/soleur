---
title: Workflow gate detection must use multiple signal types to avoid blind spots
date: 2026-03-29
category: workflow
tags: [ship, phase-5.5, cmo, gate-detection, multi-signal, trigger-logic]
---

# Learning: Workflow gate detection must use multiple signal types

## Problem

Ship Phase 5.5's CMO Content-Opportunity Gate used file-path-only triggers (`knowledge-base/product/research/`, `knowledge-base/marketing/`). PR #1256 (PWA installability) shipped as a Phase 1 milestone feature without any content consideration because it only touched `apps/web-platform/` files. The gate explicitly skipped "code-only PRs" — but PWA is a user-facing feature delivered entirely as code.

The CMO agent and all marketing skills worked correctly. The trigger logic was the broken component.

## Solution

Replaced file-path-only trigger with a flat OR-list of multiple signal types:

1. File-path matches (existing, kept): `knowledge-base/product/research/`, `knowledge-base/marketing/`, new workflow patterns
2. Semver label: `semver:minor` or `semver:major` (new)
3. Title pattern: `^feat(\(.*\))?:` regex (new)

Also updated the CMO assessment question in `brainstorm-domain-config.md` to include "new user-facing product capabilities that could warrant content amplification or feature announcements" — this makes both brainstorm Phase 0.5 AND plan Phase 2.5 domain sweeps catch product features.

## Key Insight

When designing conditional gates in workflow skills, detection should use multiple independent signal types (file paths, PR labels, title patterns, linked issues) rather than a single signal type. Single-signal-type detection creates blind spots for legitimate cases that don't match that signal type. The CMO agent already had the judgment to assess content-worthiness — the problem was that it was never invoked.

A corollary: plan review is highly effective at catching overengineering. The initial plan proposed a "two-tier detection system with structural pre-filter and LLM semantic evaluation." Three reviewers (DHH, Kieran, Code Simplicity) independently identified this as overengineering — the fix was a flat OR-list of trigger conditions. The CMO agent itself serves as the semantic filter; adding a pre-filter before a filter is redundant.

## Tags

category: workflow
module: plugins/soleur/skills/ship, plugins/soleur/skills/brainstorm
