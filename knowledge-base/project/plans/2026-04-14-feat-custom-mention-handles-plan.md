---
title: "feat: custom leader names as @mention handles"
type: feature
date: 2026-04-14
---

# feat: custom leader names as @mention handles

## Overview

When users rename domain leaders (e.g., CTO to "Oleg"), selecting from the @mention dropdown should insert `@Oleg (CTO)` into the chat text instead of `@cto`. The server already resolves custom names via reverse-lookup — only the client-side insertion and name validation need changes.

## Problem Statement

The `onSelect` handler in the chat page always inserts `@${leaderId}` (e.g., `@cto`) regardless of custom naming. Users who personalize their team expect the chat to reflect those names.

## Proposed Solution

### 1. Chat page `onSelect` — insert display name

In `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`, change the `onSelect` callback from:

```typescript
insertRef.current(`@${id}`, atPosition);
```

To use the display name from `getDisplayName(id)`:

```typescript
const displayText = getDisplayName(id);
insertRef.current(`@${displayText}`, atPosition);
```

- With custom name "Oleg" for CTO: inserts `@Oleg (CTO)`
- Without custom name: inserts `@CTO`

The server's `parseAtMentions` regex `/@(\w+)/g` captures the first word ("Oleg" or "CTO"), which resolves via existing ID match or custom name reverse-lookup in `domain-router.ts`.

### 2. Validation — enforce single-word custom names

In `apps/web-platform/server/team-names-validation.ts`, tighten `VALID_PATTERN` from `/^[a-zA-Z0-9 ]+$/` to `/^[a-zA-Z0-9]+$/` (remove space from character class). Update the error message to say "Name must be a single word (letters and numbers only, no spaces)".

### 3. Client-side validation — show inline error

In `apps/web-platform/components/settings/team-settings.tsx`, ensure the validation feedback reflects the single-word constraint. The component already calls `validateCustomName()` — the updated error message propagates automatically.

### Files to modify

1. **`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`** — change `onSelect` to insert display name
2. **`apps/web-platform/server/team-names-validation.ts`** — remove space from `VALID_PATTERN`, update error message
3. **`apps/web-platform/test/team-names.test.ts`** — update validation tests for single-word enforcement
4. **`apps/web-platform/test/chat-input.test.tsx`** — no changes needed (tests ChatInput, not chat page)

### What does NOT change

- `apps/web-platform/components/chat/at-mention-dropdown.tsx` — already filters by custom names, already passes leader ID
- `apps/web-platform/server/domain-router.ts` — `parseAtMentions` already resolves custom names via reverse-lookup
- `apps/web-platform/hooks/use-team-names.tsx` — `getDisplayName` already returns the correct format
- `apps/web-platform/components/chat/chat-input.tsx` — `insertRef` and `atMentionVisible` work unchanged

## Acceptance Criteria

- [ ] Selecting a renamed leader from dropdown inserts `@CustomName (RoleName)` into chat text
- [ ] Selecting a non-renamed leader from dropdown inserts `@RoleName` into chat text
- [ ] Server correctly routes messages containing `@CustomName` to the right leader
- [ ] Setting a custom name with spaces returns 400 from the API
- [ ] Typing `@cto` manually still routes correctly (backward compatibility)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Minimal change — one line in the chat page `onSelect`, one regex update in validation. Server routing already handles custom name resolution. No architectural changes. The `getDisplayName` function already returns the exact format needed.

## Test Scenarios

- Given a leader has custom name "Oleg", when the user selects them from the dropdown, then `@Oleg (CTO)` is inserted into the chat text
- Given a leader has no custom name, when the user selects them from the dropdown, then `@CTO` is inserted into the chat text
- Given a user tries to set a custom name "Chief Bob" (with space), when the API validates, then it returns 400 with "Name must be a single word"
- Given a user sends a message containing `@Oleg`, when the server parses mentions, then it resolves to the CTO leader
- Given a user sends a message containing `@cto`, when the server parses mentions, then it still resolves correctly (backward compatibility)
- Given a user previously set "Chief Bob" as a custom name (before validation change), when they view team settings, then the existing name is shown but editing requires single-word format

## References

- Related issue: #2170
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-14-custom-mention-handles-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-custom-mention-handles/spec.md`
