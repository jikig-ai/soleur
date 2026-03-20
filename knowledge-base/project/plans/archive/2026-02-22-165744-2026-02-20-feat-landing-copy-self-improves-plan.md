---
title: "feat: Update landing copy to emphasize self-improvement"
type: feat
date: 2026-02-20
---

# Update Landing Copy to Emphasize Self-Improvement

## Overview

Update the core value proposition copy across the website, brand guide, plugin description, and README to communicate that Soleur self-improves -- not just remembers. Also update the closing sentence from "Every project starts faster than the last" to "Every feature or project gets better and faster than the last."

## Changes

### 1. Landing page (`plugins/soleur/docs/index.njk:47`)

**Before:**
> Not a copilot. Not an assistant. A full AI organization that reviews, plans, builds, and remembers. Every decision you make teaches the system. Every project starts faster than the last.

**After:**
> Not a copilot. Not an assistant. A full AI organization that reviews, plans, builds, remembers, and self-improves. Every decision you make teaches the system. Every feature or project gets better and faster than the last.

### 2. Brand guide -- Mission (`knowledge-base/overview/brand-guide.md:11`)

**Before:**
> ...a full-stack AI organization that reviews, plans, builds, and remembers. Every decision the founder makes teaches the system. Every project starts faster than the last.

**After:**
> ...a full-stack AI organization that reviews, plans, builds, remembers, and self-improves. Every decision the founder makes teaches the system. Every feature or project gets better and faster than the last.

### 3. Brand guide -- Product descriptions (`knowledge-base/overview/brand-guide.md:75`)

**Before:**
> "Not a copilot. Not an assistant. A full AI organization that reviews, plans, builds, and remembers."

**After:**
> "Not a copilot. Not an assistant. A full AI organization that reviews, plans, builds, remembers, and self-improves."

### 4. Plugin description (`plugins/soleur/.claude-plugin/plugin.json:4`)

**Before:**
> AI-powered development tools for Claude Code that get smarter with every use. 44 agents, 8 commands, and 44 skills that compound your engineering knowledge over time.

**After:**
> A full AI organization that reviews, plans, builds, remembers, and self-improves. 44 agents, 8 commands, and 44 skills that compound your engineering knowledge over time.

### 5. Plugin README (`plugins/soleur/README.md:3`)

**Before:**
> AI-powered development tools that get smarter with every use. Make each unit of engineering work easier than the last.

**After:**
> A full AI organization that reviews, plans, builds, remembers, and self-improves. Every feature or project gets better and faster than the last.

## Out of Scope

- Audit files (`knowledge-base/audits/`) -- these are historical snapshots, not source of truth
- Brainstorm files (`knowledge-base/brainstorms/`) -- historical records
- `.pen` design files -- separate design workflow

## Acceptance Criteria

- [ ] Landing page copy updated with "self-improves" and new closing sentence
- [ ] Brand guide mission and product description updated consistently
- [ ] Plugin description updated to match brand voice
- [ ] README description updated to match
- [ ] Version bump (PATCH -- docs/copy update to existing plugin files)

## Test Scenarios

- Given the docs site builds, when visiting the landing page, then the updated copy is visible
- Given the plugin.json is valid JSON, when installing the plugin, then the new description shows
