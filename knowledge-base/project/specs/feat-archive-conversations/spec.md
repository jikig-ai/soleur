# Feature: Archive Conversations

## Problem Statement

The command center conversation list grows unbounded. Users have no way to declutter completed or stale conversations without losing them permanently. This creates noise that makes it harder to find active work.

## Goals

- Allow users to archive individual conversations to remove them from the active list
- Allow bulk archiving of multiple conversations at once
- Auto-archive conversations with no activity for 30+ days
- Auto-unarchive conversations when new agent activity occurs
- Provide an "Archived" filter tab to view and manage archived conversations

## Non-Goals

- User-configurable auto-archive threshold (hardcode 30 days for V1)
- Folders, tags, or other organizational features beyond archive
- Hard deletion of conversations from this feature
- Archive status syncing to mobile PWA (web-only for V1)

## Functional Requirements

### FR1: Archive Individual Conversation

User can archive a single conversation from the conversation list. The conversation disappears from the active view and appears in the Archived tab.

### FR2: Unarchive Conversation

User can unarchive a conversation from the Archived tab. It reappears in the active list with its original status preserved.

### FR3: Bulk Archive

User can select multiple conversations and archive them in one action.

### FR4: Auto-Archive

Conversations with `last_active` older than 30 days are automatically archived. Runs on a recurring schedule (pg_cron or edge function).

### FR5: Auto-Unarchive on Activity

When an archived conversation receives new agent output (e.g., async task completes, Realtime event), it auto-unarchives — `archived_at` is set to NULL.

### FR6: Archived Filter Tab

An "Archived" tab alongside existing status filters shows only archived conversations. Count badge shows number of archived items.

### FR7: Search Includes Archived

Archived conversations appear in search results with an "archived" visual indicator.

## Technical Requirements

### TR1: Database Migration

Add `archived_at timestamptz DEFAULT NULL` column to `conversations` table. Add index on `(user_id, archived_at)` for filtered queries. Do not modify the existing status check constraint.

### TR2: RLS Policy

Existing RLS policy (`auth.uid() = user_id`) covers the new column — no policy changes needed.

### TR3: Realtime Integration

The existing `command-center` Realtime channel subscription in `useConversations` must handle archive/unarchive events and auto-unarchive triggers.

### TR4: Prior Migration Caution

A prior NOT NULL constraint issue on `domain_leader` was documented in learnings. Verify migration applies cleanly to production after committing.
