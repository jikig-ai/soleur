# Post-Connect Sync & Project Status Report

**Issue:** TBD
**Branch:** feat-post-connect-sync-proposal
**Brainstorm:** [2026-04-07-post-connect-sync-proposal-brainstorm.md](../../brainstorms/2026-04-07-post-connect-sync-proposal-brainstorm.md)

## Problem Statement

When users connect a project in the web platform, the provisioning pipeline clones the repo but does nothing to analyze it. The "Setting Up" animation shows fake progress steps. Users land on an empty Knowledge Base with "Nothing Here Yet" -- a value gap at the most critical moment of onboarding.

## Goals

- G1: Automatically scan connected projects to produce a project health snapshot
- G2: Auto-trigger headless agent sync to populate the Knowledge Base
- G3: Display health snapshot with actionable recommendations in the connect-repo Ready state
- G4: Provide a persistent KB overview page for ongoing project health visibility
- G5: Notify users in the Command Center when deep analysis completes

## Non-Goals

- Interactive sync (Accept/Skip/Edit review) -- this remains a CLI-only feature
- Numeric project health "scores" -- categorized labels only (Well-documented, Getting started, Needs attention)
- Periodic auto-refresh of health snapshot (deferred -- could be added via git push webhook later)
- Custom scan configurations -- all projects get the same analysis

## Functional Requirements

- FR1: Fast server-side file scanner runs during provisioning after repo clone
- FR2: Scanner detects: package managers, test files, CI config, linting, Docker, README, CLAUDE.md, KB directory and completeness
- FR3: Health snapshot stored as JSON in user's database record
- FR4: Agent sync conversation auto-created after provisioning completes
- FR5: Agent sync runs headless (auto-accept high-confidence findings, skip low-confidence)
- FR6: Agent sync conversation appears in Command Center with "Executing" status
- FR7: When agent sync completes, conversation status updates to "Completed" via Supabase Realtime
- FR8: Connect-repo Ready state displays health snapshot with detected signals, missing signals, and top 3 recommendations
- FR9: New `/dashboard/kb/overview` page shows full health report, KB completeness, recommendations, and deep analysis status
- FR10: "Setting Up" animation steps correspond to real provisioning operations

## Technical Requirements

- TR1: Fast scan completes in under 5 seconds for repos up to 100k files
- TR2: Health snapshot JSON payload under 2KB
- TR3: Agent sync uses existing conversation/message infrastructure
- TR4: No new external dependencies for the fast scanner
- TR5: KB overview page uses the same responsive layout pattern as existing KB pages
- TR6: Health snapshot column added via Supabase migration
