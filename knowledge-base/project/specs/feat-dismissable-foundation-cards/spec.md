---
title: Dismissable Foundation Cards — Progressive Task Surfacing
status: draft
issue: 2413
branch: feat-dismissable-foundation-cards
date: 2026-04-16
---

# Dismissable Foundation Cards

## Problem Statement

The Command Center foundation cards (Vision, Brand Identity, Business Validation, Legal Foundations) remain visible with a checkmark after completion until all 4 are done. This wastes dashboard space and misses an opportunity to guide the founder toward their next high-impact task.

## Goals

- G1: Completed foundation cards auto-collapse into compact chips, freeing grid space
- G2: Freed slots fill with KB-gap-aware operational tasks (skip tasks whose KB file already exists)
- G3: The card grid always shows the founder's most relevant next actions
- G4: No new database tables or localStorage — state derived entirely from KB tree API

## Non-Goals

- AI-generated dynamic recommendations (deferred to L4 North Star)
- Manual dismiss/close buttons
- User-configurable task ordering
- Persistent dismissal state in database

## Functional Requirements

- FR1: Completed foundation cards render as compact chips (checkmark + title) above the active card grid
- FR2: Compact chips link to the KB file path (same as completed cards today)
- FR3: A curated list of 6 post-foundation operational tasks is defined, each with: id, title, leaderId, kbPath, promptText
- FR4: Operational tasks that already have a KB file with content >= `FOUNDATION_MIN_CONTENT_BYTES` are skipped
- FR5: The active card grid shows incomplete foundations + next operational tasks, filling up to 4 columns
- FR6: When all foundations AND all operational tasks are complete, the section is hidden (or shows existing suggested prompts)
- FR7: The "FOUNDATIONS" header updates to show progress (e.g., "2/4 complete")

## Technical Requirements

- TR1: Extend `FOUNDATION_PATHS` with a new `OPERATIONAL_TASKS` array using the same `FoundationCard` interface
- TR2: Reuse existing KB tree fetch and `flattenTree` logic — no new API calls
- TR3: Update `FoundationCards` component to accept both foundation and operational cards
- TR4: Add a new `CompletedChips` component for the collapsed completed items
- TR5: No changes to database schema or API routes

## Acceptance Criteria

- [ ] Completing a foundation card causes it to auto-collapse into a chip on next page load/refetch
- [ ] An operational task card appears in the freed grid slot
- [ ] Operational tasks whose KB file exists are not shown
- [ ] Clicking a compact chip navigates to the KB file
- [ ] Clicking an operational task card navigates to a new chat with the prompt pre-filled
- [ ] Grid maintains 4-column layout on desktop, 2-column on mobile
- [ ] All existing dashboard states (first-run, provisioning, error) remain unaffected
