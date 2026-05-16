// Dev-only sign-in gate (R3 / feat-dev-signin-bypass).
//
// Two callers — `app/(auth)/login/page.tsx` (server-component panel render
// decision) and `app/api/auth/dev-signin/route.ts` (request-time guard).
// Both call `isDevSignInEnabled()` at request time; the strict equality on
// `NODE_ENV === "development"` plus the runtime feature-flag check produce
// fail-closed behavior independently — both must agree before the surface
// activates.
//
// Why the check is INSIDE the function (not at module top):
//   - learning 2026-04-28-module-load-throw-collapses-auth-surface — any
//     throw or top-level branch on env vars at import time collapses the
//     auth surface in CI/preview where NODE_ENV semantics differ.
//   - Vercel preview defaults `NODE_ENV` to production; a top-level
//     literal would short-circuit imports for both production AND preview
//     paths. Routing the decision through a function keeps the module
//     side-effect-free at import.
//
// Why strict `=== "development"` (not `!== "production"`):
//   - learning 2026-04-13-supabase-env-var-dev-mode-graceful-degradation —
//     `!= "production"` fires under `NODE_ENV=test` (vitest default),
//     which would render the panel in SDK-mocked suites and the route's
//     gate would pass under the same conditions.

import { getFlag } from "@/lib/feature-flags/server";

export function isDevSignInEnabled(): boolean {
  if (process.env.NODE_ENV !== "development") return false;
  return getFlag("dev-signin");
}
