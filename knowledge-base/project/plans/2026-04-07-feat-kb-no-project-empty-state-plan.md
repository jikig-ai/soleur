---
title: "feat: show no-project empty state in KB UI instead of generic error"
type: feat
date: 2026-04-07
---

# feat: Show No-Project Empty State in KB UI

## Overview

When a user navigates to the Knowledge Base UI (`/dashboard/kb`) without having connected a project, the API returns 404 (no `workspace_path`), the layout maps it to the `"not-found"` error state, and the page renders the generic catch-all: "Unable to load your knowledge base. Please try again later." This is misleading -- the user has not encountered an error; they simply have no project set up yet.

Replace the generic error with a purpose-built empty state that explains the situation and provides a CTA to create or connect a project via `/connect-repo`.

## Problem Statement

The current error handling chain:

1. **API** (`/api/kb/tree`): when `workspace_path` is null or `fetchError` occurs, returns `{ error: "Workspace not found" }` with HTTP 404
2. **Layout** (`kb/layout.tsx`): maps 404 to `setError("not-found")`
3. **Page** (`kb/page.tsx`): has a specific handler for `"workspace-not-ready"` but falls through to the generic `if (error)` block for `"not-found"`, showing the unhelpful "Unable to load" message

The `"not-found"` error is a distinct state from a genuine server error (`"unknown"`). It means no project exists, and should be handled with a dedicated UI that guides the user toward project setup.

## Proposed Solution

Add a dedicated `if (error === "not-found")` branch in `kb/page.tsx` that renders a no-project empty state with:

- An icon (folder or similar, consistent with the existing page design language)
- A heading explaining no project is set up
- A brief description
- A primary CTA button linking to `/connect-repo?return_to=/dashboard/kb`

### Architecture

The change is contained to a single file: `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx`.

No API changes are needed -- the API already returns the correct 404 status and the layout already maps it to `"not-found"`. The only gap is in the page-level error rendering.

### Design Direction

Follow the existing patterns in the same file:

- The `EmptyState` component (lines 72-100) shows a similar empty-state pattern (icon + heading + description + CTA link)
- The `"workspace-not-ready"` handler (lines 15-34) shows the centered card pattern with an icon in a circle

Use the same Tailwind utility classes, `font-serif` for headings, `text-neutral-400` for descriptions, amber accent for the CTA button. The CTA should use a `Link` component (already imported) pointing to `/connect-repo?return_to=/dashboard/kb` so the user returns to KB after setup.

## Acceptance Criteria

- [x] When a user with no connected project visits `/dashboard/kb`, they see a dedicated empty state (not "Unable to load your knowledge base")
- [x] The empty state includes a heading indicating no project is set up
- [x] The empty state includes a brief description guiding the user
- [x] The empty state includes a CTA button to create or connect a project (links to `/connect-repo?return_to=/dashboard/kb`)
- [x] The generic error message ("Unable to load your knowledge base") remains for the `"unknown"` error state
- [x] The `"workspace-not-ready"` state continues to work as before

## Test Scenarios

- Given a user with no connected project (`workspace_path` is null), when they navigate to `/dashboard/kb`, then they see the no-project empty state with a "Set Up Project" CTA
- Given a user with no connected project, when they click the CTA, then they are navigated to `/connect-repo?return_to=/dashboard/kb`
- Given a user with a connected project in error state (API returns 500), when they navigate to `/dashboard/kb`, then they still see the generic "Unable to load" error
- Given a user with `workspace_status !== "ready"`, when they navigate to `/dashboard/kb`, then they still see the "Setting Up Your Workspace" state

## Context

### Key Files

| File | Role |
|------|------|
| `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx` | Page component -- where the fix goes |
| `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` | Layout that fetches tree and provides context |
| `apps/web-platform/components/kb/kb-context.tsx` | Context type definition (already has `"not-found"` in union) |
| `apps/web-platform/app/api/kb/tree/route.ts` | API route returning 404 when no workspace |
| `apps/web-platform/components/settings/project-setup-card.tsx` | Reference for "not connected" UI pattern and CTA wording |

### Error State Mapping

| API Status | Layout Error | Current UI | Desired UI |
|------------|-------------|------------|------------|
| 401 | redirect to `/login` | redirect | no change |
| 503 | `"workspace-not-ready"` | "Setting Up Your Workspace" | no change |
| 404 | `"not-found"` | "Unable to load your knowledge base" | **New: no-project empty state** |
| 500 | `"unknown"` | "Unable to load your knowledge base" | no change |
| network error | `"unknown"` | "Unable to load your knowledge base" | no change |

## MVP

### `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx`

Add a new conditional branch before the generic `if (error)` block:

```typescript
if (error === "not-found") {
  return <NoProjectState />;
}
```

Extract the JSX into a named function component (matching the file's existing `EmptyState` and `LoadingSkeleton` pattern):

```typescript
function NoProjectState() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="max-w-sm text-center">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-neutral-800">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-amber-500">
            <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2Z" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <h1 className="mb-2 font-serif text-lg font-medium text-white">
          No Project Connected
        </h1>
        <p className="mb-6 text-sm leading-relaxed text-neutral-400">
          Connect a GitHub project so your AI team can build your knowledge
          base with plans, specs, and analyses.
        </p>
        <Link
          href="/connect-repo?return_to=/dashboard/kb"
          className="inline-flex items-center gap-2 rounded-lg bg-gradient-to-r from-amber-600 to-amber-500 px-5 py-2.5 text-sm font-medium text-neutral-950 transition-opacity hover:opacity-90"
        >
          Set Up Project
        </Link>
      </div>
    </div>
  );
}
```

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

## References

- KB viewer UI: PR #1689 / #1711
- Connect repo flow: `apps/web-platform/app/(auth)/connect-repo/page.tsx`
- Project setup card pattern: `apps/web-platform/components/settings/project-setup-card.tsx`
