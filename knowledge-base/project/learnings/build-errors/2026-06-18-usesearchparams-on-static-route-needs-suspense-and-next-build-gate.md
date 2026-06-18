# Learning: `useSearchParams` on a static App Router route needs `<Suspense>` — and only `next build` catches it

## Problem

A new dashboard page `app/(dashboard)/dashboard/inbox/page.tsx` (#5512) was first planned as a
plain `"use client"` page calling `useSearchParams()` to drive Active/Archived tabs via a
`?status=archived` query param. On Next.js 15.x this **fails `next build`** with
`missing-suspense-with-csr-bailout` — because the route is **static** (no dynamic segment), Next
tries to prerender it, and `useSearchParams()` forces a client-side bailout that must be bounded
by a `<Suspense>` boundary.

Critically: **`tsc --noEmit` does NOT catch this, and `vitest` does NOT catch it** (jsdom renders
the component fine). Only `next build` surfaces it. A verify gate of "tsc + vitest" ships green and
the break only appears in CI's build step.

A sibling page `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` uses `useSearchParams()`
in a bare `"use client"` page with **no** `<Suspense>` — but it is **exempt** because it has a
**dynamic segment** (`[conversationId]`), so the route is already dynamic and never prerenders.
That made it a tempting-but-WRONG precedent for the static `/dashboard/inbox` route. (This exact
mis-precedent was proposed in the plan and caught by Kieran plan-review before implementation.)

## Solution

Use the **Routines pattern**: a Server page that auth-gates and wraps a client surface in
`<Suspense>`.

```tsx
// app/(dashboard)/dashboard/inbox/page.tsx — Server component
export const dynamic = "force-dynamic";
export default async function InboxPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  return (
    <main className="mx-auto max-w-5xl px-6 py-8">
      <header>…</header>
      <Suspense fallback={<p>Loading…</p>}>
        <InboxSurface />   {/* "use client"; calls useSearchParams() */}
      </Suspense>
    </main>
  );
}
```

The committed static-client precedents that DO need the boundary: `app/(auth)/signup/page.tsx`,
`app/(auth)/setup-key/page.tsx` (both wrap `useSearchParams` in `<Suspense>`).

## Key Insight

`useSearchParams()` on a **static** route (no dynamic `[param]` segment) is a `next build`
breaker unless bounded by `<Suspense>`. `tsc` and `vitest` are both blind to it. Two rules follow:

1. **Any page calling `useSearchParams` needs a `<Suspense>` boundary** unless its route is
   already dynamic (has a `[param]` segment). A client page on a dynamic route is NOT valid
   precedent for a static one — check the route shape, not just "another page does it this way."
2. **The verify gate for such a page MUST include `next build`**, not just `tsc --noEmit` +
   `vitest`. Add a `next build` AC whenever the diff adds/changes a `useSearchParams` page.

The canonical fix is the Server-page + `<Suspense>`-wrapped client-surface split (the Routines
pattern), which also gives a clean place for the cookie-session auth gate.

## Tags
category: build-errors
module: web-platform, nextjs-app-router
issues: 5512
