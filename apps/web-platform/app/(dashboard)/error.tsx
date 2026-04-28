"use client";
import { ErrorBoundaryView } from "@/components/error-boundary-view";

// Per Next.js 15 error-boundary semantics, this segment file is rendered as a
// SIBLING of `(dashboard)/layout.tsx` — it does NOT catch throws originating
// in `layout.tsx` itself or in modules that layout imports at module-load
// time. The validator throw in `lib/supabase/client.ts` (imported by layout)
// bubbles up to the root `app/error.tsx`. This boundary catches throws in
// dashboard children (`(dashboard)/dashboard/page.tsx` and below). See
// `knowledge-base/project/learnings/runtime-errors/2026-04-28-module-load-throw-collapses-auth-surface.md`.
export default function DashboardSegmentError(props: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <ErrorBoundaryView
      {...props}
      feature="dashboard-error-boundary"
      segment="dashboard"
    />
  );
}
