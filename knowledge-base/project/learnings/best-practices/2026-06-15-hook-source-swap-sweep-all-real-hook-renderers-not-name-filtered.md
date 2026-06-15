---
title: "Source-swapping a shared hook's data source — sweep ALL real-hook renderers, not a name-filtered subset"
date: 2026-06-15
category: best-practices
tags: [testing, vitest, react-hooks, mock-sweep, one-shot]
module: apps/web-platform/hooks
related:
  - 2026-04-27-wrapper-extension-test-mock-chain-sweep.md
---

# Source-swapping a shared hook's data source must sweep every real-hook renderer

## Problem

Fixing the empty Recent Conversations rail (#5317) required changing
`hooks/use-conversations.ts` to read repo scope from
`GET /api/workspace/active-repo` instead of the deprecated `users.repo_url`
column. That swap breaks every test that renders the **real** hook and stubs
its old data source (a `from("users")` supabase mock) — those tests now hit an
unstubbed `fetch` and either throw or resolve to a null repo → empty list.

I enumerated the affected tests with a **name-filtered** grep
(`git grep -l ... test/ | grep -iE 'conversation|nav-rail|update-status'`) and
fixed the 3 that matched. But two more files — `command-center.test.tsx` and
`start-fresh-onboarding.test.tsx` — also render the real `useConversations`
(via the dashboard page) and broke. Their names don't contain "conversation",
so the name filter silently dropped them. They surfaced only at the Phase 2
**full-suite exit gate** (`vitest run` whole package): 2 files / 7 tests red.

## Solution

When source-swapping a shared hook (or any module a hook transitively calls),
the authoritative work-list is **every test that renders the REAL hook**, which
is the set that imports it MINUS the set that mocks it away:

```bash
# Files that touch the hook at all:
git grep -l 'useConversations' apps/web-platform/test/
# Of those, the ones that MOCK the hook (NOT affected by a source swap):
git grep -l 'vi.mock("@/hooks/use-conversations"' apps/web-platform/test/
# The difference = files rendering the real hook = the swap's blast radius.
```

Never name-filter that list by topic — a page-level test (`command-center`,
`start-fresh-onboarding`) renders the hook without "conversation" in its
filename. The full-suite exit gate is the backstop, but discovering breakage at
the gate costs an extra full run; deriving the exhaustive list up front is one
grep.

## Key Insight

A hook's data-source swap has a blast radius = {importers} − {mockers}, not
{importers whose names match the feature}. This is the render-time sibling of
[[2026-04-27-wrapper-extension-test-mock-chain-sweep]] (which covers extending a
wrapper's mock chain); the same exhaustive-sweep discipline applies to swapping
the *source* a hook reads, and the litmus is `git grep -l <hookName> test/`
minus the `vi.mock("@/hooks/<hook>"` set — never a topical name filter.

## Session Errors

1. **Name-filtered test sweep missed 2 real-hook renderers.** Recovery: the
   full-suite exit gate caught `command-center.test.tsx` +
   `start-fresh-onboarding.test.tsx`; both fixed with the active-repo route
   fetch stub. **Prevention:** derive the sweep list as {importers}−{mockers}
   via grep, never a topical name filter (this learning).
2. **nav-states e2e: 3 `Target page/browser has been closed` crashes** on a
   resource-starved local machine. One-off, already-documented flake class
   (#5009); CI's containerized e2e job is authoritative. No fix.
