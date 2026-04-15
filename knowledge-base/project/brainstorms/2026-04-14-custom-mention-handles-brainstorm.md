---
title: "Custom leader names as @mention handles"
date: 2026-04-14
status: complete
issue: 2170
---

# Custom Leader Names as @mention Handles

## What We're Building

When users rename domain leaders (e.g., CTO to "Oleg"), the @mention system should insert the custom name into the chat text instead of the raw leader ID. Selecting "Oleg" from the dropdown inserts `@Oleg (CTO)` rather than `@cto`.

## Why This Approach

The system already supports most of this:

- The `AtMentionDropdown` already filters by custom names (typing `@ol` matches "Oleg")
- The server's `parseAtMentions` already reverse-lookups custom names from the `team_names` table
- The `useTeamNames` hook provides `getDisplayName(id)` which returns `"CustomName (RoleName)"` or `"RoleName"`

The only gap is the `onSelect` handler which currently always inserts `@${leaderId}`. Changing this to insert the display name is a minimal change with zero architectural impact.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Name format | Single-word only | Avoids regex changes — `/@(\w+)/g` captures single words. Chat handles are naturally single-word. |
| Insert format | `@Oleg (CTO)` | Custom name as handle + role in parentheses for context. If no custom name, falls back to `@CTO`. |
| Server parsing | No changes needed | `parseAtMentions` already resolves custom names via reverse-lookup from `team_names` table. |
| Manual typing | `@cto` still works | Server checks leader IDs first, then falls back to custom name reverse-lookup. Both paths resolve correctly. |
| Validation | Enforce single-word at API level | Server-side validation on `PUT /api/team-names` rejects names containing spaces. UI shows inline error. |

## Scope

### In scope

- Chat page `onSelect` handler: insert display name instead of ID
- Team names API: single-word validation (reject spaces)
- Team names UI: validation error for spaces

### Out of scope

- Multi-word handle support (would require regex and parser changes)
- Rich @mention rendering (styled chips/tags in the textarea)
- @mention autocomplete in other input fields (only chat input)

## Open Questions

None — all key decisions resolved.

## References

- Issue: #2170
- AtMentionDropdown: `apps/web-platform/components/chat/at-mention-dropdown.tsx`
- Chat page onSelect: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Server routing: `apps/web-platform/server/domain-router.ts` (`parseAtMentions`)
- Team names API: `apps/web-platform/app/api/team-names/route.ts`
- Team names hook: `apps/web-platform/hooks/use-team-names.tsx`
