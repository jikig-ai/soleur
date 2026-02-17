---
title: UX Review Gap -- Visual Polish PR Missed Information Architecture Problems
category: review-methodology
module: docs-site
tags:
  - ux-review
  - information-architecture
  - navigation-design
  - content-structure
  - agent-coverage-gap
symptoms:
  - PR review approved visual changes (colors, border-radius) without catching navigation ordering problems
  - Redundant/empty pages (Commands, MCP) not flagged as information architecture issues
  - Over-granular category pills (8 instead of 6) not identified as cognitive overload
  - Visual inconsistency between sections (plain ol vs styled cards) missed
  - Missing first-time-user content (use case examples) not identified during review
date: 2026-02-17
---

# UX Review Gap: Visual Polish vs Information Architecture

## Problem

PR #111 fixed UI polish issues on the docs site (colors, border-radius, grid layouts, mobile nav) and was merged. But it missed fundamental UX problems that required a follow-up overhaul:

1. **Navigation ordering** -- Getting Started was last in the nav (6th item). New users see Agents, Commands, Skills, MCP, Changelog before they see how to install.
2. **Redundant pages** -- Commands and MCP pages existed but added minimal value. Commands duplicated what Getting Started already covered. MCP had one server entry.
3. **Over-granular categories** -- Agents page had 8 pill nav items with 3 Engineering sub-categories (Review, Design, Infra) when Engineering is one domain with sub-headers.
4. **Visual inconsistency** -- Workflow section used a plain `<ol>` while Quick Commands used styled `.command-item` cards. Different visual weight for same-level content.
5. **Missing onboarding content** -- No "Common Workflows" section showing users what command sequences to run for typical tasks (building a feature, fixing a bug, reviewing a PR).

## Root Cause

The review agents (code-quality, architecture, security, etc.) focus on code correctness. The `ux-design-lead` agent is scoped to creating `.pen` files via Pencil MCP -- it has zero capability for auditing existing HTML sites. No agent in the current roster reviews:

- Information architecture (page necessity, content hierarchy)
- Navigation flow (ordering for user journey)
- Content completeness (onboarding gaps, missing use cases)
- Visual consistency across sections (same-level content should look the same)

This is a coverage gap in the agent roster.

## Solution

Performed a docs UX overhaul (v2.12.1):
- Moved Get Started first in nav, removed Commands/MCP links
- Deleted commands.html and mcp-servers.html
- Collapsed Engineering sub-categories into one section with h3 sub-headers
- Converted workflow steps to card treatment matching Quick Commands
- Added Common Workflows section with 3 use case scenarios
- Updated Learn More links, sitemap, deploy workflow, release-docs skill

## Key Insight

**Visual polish review and UX review are different disciplines.** A PR can have perfect CSS and still have broken information architecture. The current agent roster has no UX auditor for existing sites -- the ux-design-lead only creates new .pen files. Either:

1. Expand ux-design-lead to also audit existing HTML for IA/navigation/content issues, OR
2. Create a dedicated `ux-reviewer` agent focused on site audits (navigation order, page necessity, content gaps, visual consistency)

Option 2 is cleaner -- creation and review are different concerns.

## Prevention

When reviewing docs site changes:
- Ask "does the navigation order match the user journey?" (install -> learn -> reference)
- Ask "does every page justify its existence?" (if a page has <3 items, merge it)
- Ask "do same-level sections have consistent visual treatment?"
- Ask "can a first-time user figure out what to do in 30 seconds?"
