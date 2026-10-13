# Archive Conversations in Command Center

**Date:** 2026-04-12
**Status:** Decided
**Issue:** #1990

## What We're Building

Conversation archiving for the command center — users can archive individual or bulk conversations to declutter their active list, view archived conversations in a dedicated filter tab, and unarchive at any time. Conversations auto-archive after 30 days of inactivity. Archived conversations auto-unarchive when new agent activity occurs.

## Why This Approach

- **`archived_at` timestamp column** — orthogonal to functional status (active/waiting/completed/failed). A completed conversation can be archived without losing its status. Cleaner than adding "archived" to the status enum.
- **Auto-unarchive on activity** — prevents buried agent responses. If an async task completes on an archived conversation, it moves back to the active list.
- **Auto-archive at 30 days** — reduces clutter for users who don't manually manage their list. Implemented via pg_cron or Supabase edge function.
- **Filter tab UI** — "Archived" tab alongside existing status filters. Clean separation without taking permanent sidebar space.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data model | `archived_at timestamptz` column | Orthogonal to status, preserves original state for analytics |
| New activity on archived | Auto-unarchive | Prevents missed agent output |
| V1 scope | Single + bulk + auto-archive | Full feature set, user confirmed |
| UI pattern | Filter tab | Clean separation, doesn't take permanent space |
| Auto-archive threshold | 30 days inactive | Based on `last_active` column |

## Open Questions

- Should auto-archive threshold be user-configurable in settings? (Deferred — hardcode 30 days for V1)
- Should archived conversations appear in search results? (Recommend yes, with an "archived" badge)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Good Phase 3 ("Make it Sticky") fit. Unarchive is non-negotiable from day one. Flagged notification behavior on archived conversations — resolved with auto-unarchive. Small scope, no validation gate needed.

### Marketing (CMO)

**Summary:** Table-stakes UX — no dedicated marketing action needed. Auto-archive is the most interesting differentiating angle. Note in release notes, save messaging energy for bigger features.
