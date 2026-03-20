---
title: Brainstorm domain routing pattern for specialized agents
date: 2026-02-13
category: plugin-architecture
module: soleur-plugin
component: brainstorm
tags: [domain-routing, brainstorm, brand-architect, command-routing, keyword-detection]
severity: medium
---

# Learning: Brainstorm Domain Routing Pattern

## Problem

The brand-architect agent was only accessible via Task tool (assistant-initiated). Users who tried `/soleur:marketing:brand-architect` got "Unknown skill" because agents are not user-invocable. There was no entry point for users to reach specialized workshop agents.

## Solution

Added a "Specialized Domain Routing" section to `/soleur:brainstorm` Phase 0 that detects domain-specific keywords in the feature description and offers to route to the appropriate agent.

The pattern:
1. Define keywords per domain (e.g., "brand, brand identity, brand guide, voice and tone, brand workshop")
2. Scan feature description for keyword matches (case-insensitive substring matching)
3. If match: AskUserQuestion confirming the routing (user always decides)
4. If accepted: create worktree + issue, navigate to worktree, hand off via Task tool
5. If declined: continue normal brainstorm flow

Key implementation detail: the brand-architect's output (brand guide) replaces the brainstorm document -- there is no brainstorm doc for workshop sessions. Output summary uses "Document: none (brand workshop)" to maintain format consistency.

## Key Insight

When specialized agents produce their own structured output (e.g., brand guide), route through an existing command rather than creating a new skill or command. The brainstorm command becomes a router: it detects the domain, sets up infrastructure (worktree, issue), and delegates to the specialist. This avoids proliferating entry points and keeps the user workflow unified.

## Critical Bug Caught by Plan Review

The first plan draft was missing `cd ${WORKTREE_PATH}` before invoking the brand-architect agent via Task tool. Without this, the agent would write files to the main repo instead of the worktree. Plan review (Kieran reviewer) caught this as a blocking issue.

Lesson: any plan that creates a worktree and then invokes a Task agent MUST include explicit worktree navigation + `pwd` verification between creation and invocation.

## Tags

category: plugin-architecture
module: soleur-plugin
component: brainstorm
