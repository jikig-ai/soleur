---
title: "fix: show conversation history alongside incomplete foundation cards"
type: fix
date: 2026-04-12
issue: "#2026"
---

# fix: Show conversation history alongside incomplete foundation cards

The Command Center dashboard uses mutually exclusive render states. When foundations are incomplete (vision exists but Brand/Validation/Legal are missing), the page renders only foundation cards and hides the conversation inbox entirely. Users with past conversations cannot see or access them.

The conversation inbox (shipped #1759, #1962, #1990) is fully functional — it's hidden by a conditional early return in `page.tsx:292`.

## Acceptance Criteria

- [ ] When foundations are incomplete and conversations exist, both foundation cards and conversation list render on the same page
- [ ] When foundations are incomplete and no conversations exist, foundation cards render above an empty conversation placeholder ("No conversations yet — start one to put your agents to work.")
- [ ] The first-run state (no `vision.md`, no conversations) is unchanged
- [ ] The full inbox state (all foundations complete, conversations exist) is unchanged
- [ ] Foundation cards remain compact (horizontal row) and don't dominate the page when conversations are present
- [ ] Mobile-responsive: foundation cards stack 2-wide on mobile, conversation list below

## Test Scenarios

- Given a user with `vision.md` + 3 incomplete foundations + 2 past conversations, when they visit the Command Center, then they see foundation cards at the top AND conversation list below
- Given a user with `vision.md` + 3 incomplete foundations + 0 conversations, when they visit the Command Center, then they see foundation cards at the top AND an empty conversation placeholder below
- Given a user with all foundations complete + conversations, when they visit the Command Center, then they see the existing inbox view (no foundation cards)
- Given a first-run user (no `vision.md`, no conversations), when they visit the Command Center, then they see the existing "Tell your organization what you're building" screen
- Given a user with incomplete foundations, when they apply status/domain filters to conversations, then filters work correctly

## Context

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

The page currently has 4 early-return render states in order:

1. **Loading** (line 222) — skeleton while KB tree loads
2. **Provisioning** (line 237) — 503 from KB tree
3. **First-run** (line 250) — no vision, no conversations
4. **Foundations** (line 292) — vision exists, not all complete → **THIS IS THE GATE**

After these early returns, two more states render:

5. **Empty inbox** (line 378) — all foundations complete, no conversations
6. **Full inbox** (line 432) — conversations exist

**The fix:** Remove state #4 as a separate early return. Instead, merge foundation cards into states #5 and #6 as a conditional section at the top.

## Domain Review

**Domains relevant:** Product, Marketing

Domain assessments carried forward from brainstorm (2026-04-12).

### Product (CPO)

**Status:** reviewed
**Assessment:** Inbox already shipped (#1690). User is seeing the foundation-card gate, not a missing feature. Recommended empty-state discoverability fix. Flagged stale roadmap Current State section.

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Foundation gate undermines the "compounding knowledge" brand thesis. Status badges create re-engagement psychology. Copy review needed for any new strings.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)

## MVP

### Implementation approach

The change is a restructuring of render logic in a single file. No new components, no new hooks, no backend changes.

**Step 1: Extract a `FoundationsBar` inline component**

Extract the foundation cards rendering into a reusable inline component within `page.tsx`:

```tsx
// apps/web-platform/app/(dashboard)/dashboard/page.tsx
function FoundationsBar({
  foundationCards,
  onPromptClick,
}: {
  foundationCards: FoundationCard[];
  onPromptClick: (text: string) => void;
}) {
  return (
    <div className="mb-8">
      <p className="mb-2 text-xs font-medium tracking-widest text-amber-500">
        FOUNDATIONS
      </p>
      <p className="mb-4 text-sm text-neutral-400">
        Complete these to brief your department leaders.
      </p>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {/* same card rendering as current foundations state */}
      </div>
    </div>
  );
}
```

**Step 2: Remove the foundations early return (lines 292-368)**

Delete the entire `if (!kbError && visionExists && !allFoundationsComplete)` block that returns early.

**Step 3: Add `FoundationsBar` to the empty inbox state (lines 378-426)**

When `visionExists && !allFoundationsComplete`, render `FoundationsBar` at the top of the empty state. Replace the "Your organization is ready" heading with context-appropriate copy:

```tsx
if (conversations.length === 0 && !hasActiveFilter) {
  return (
    <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
      {visionExists && !allFoundationsComplete && (
        <FoundationsBar
          foundationCards={foundationCards}
          onPromptClick={handlePromptClick}
        />
      )}

      <p className="mb-3 text-xs font-medium tracking-widest text-amber-500">
        COMMAND CENTER
      </p>
      <h1 className="...">
        {allFoundationsComplete
          ? "Your organization is ready."
          : "No conversations yet."}
      </h1>
      <p className="...">
        Start a conversation to put your agents to work.
      </p>

      {/* New conversation button */}
      {/* Suggested prompts (only when foundations are complete) */}
      {/* Leader strip */}
    </div>
  );
}
```

**Step 4: Add `FoundationsBar` to the inbox state (lines 432-543)**

When `visionExists && !allFoundationsComplete`, render `FoundationsBar` between the header and the filter bar:

```tsx
return (
  <div className="mx-auto max-w-4xl px-4 py-6 md:py-8">
    {/* Header */}
    <div className="mb-6 flex items-center justify-between">...</div>

    {/* Foundation cards (only when incomplete) */}
    {visionExists && !allFoundationsComplete && (
      <FoundationsBar
        foundationCards={foundationCards}
        onPromptClick={handlePromptClick}
      />
    )}

    {/* Filter bar */}
    <div className="mb-4 flex flex-wrap items-center gap-2">...</div>

    {/* Conversation list */}
    ...
  </div>
);
```
