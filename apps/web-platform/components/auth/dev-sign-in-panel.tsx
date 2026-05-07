// Dev-only multi-account sign-in panel (R3 / feat-dev-signin-bypass).
//
// Server component (no "use client"). Renders nothing in any non-dev
// environment AND nothing when FLAG_DEV_SIGNIN is unset — both checks
// are inline literals at the top of the function body so SWC/Terser
// can dead-code-eliminate the body in production builds, layered on
// top of the runtime gate in `lib/auth/dev-mode.ts`. This double check
// (literal + getFlag) is intentional per the plan's "Files to Create"
// entry — concentrating the elimination signal at the call site.
//
// Each button posts a vanilla form (no client JS) to /api/auth/dev-signin
// where the route handler enforces the same triple-defense gate before
// authenticating with Supabase.

import { getFlag } from "@/lib/feature-flags/server";
import { Card } from "@/components/ui/card";

const SLOTS: ReadonlyArray<1 | 2 | 3> = [1, 2, 3];

export function DevSignInPanel() {
  // Layered defense — see SKILL.md Files-to-Create entry. The literal
  // is intentionally inlined here (not delegated to isDevSignInEnabled())
  // so the post-build CI grep gate's tripwire fires on a dead branch
  // rather than on dev paths leaking into shared client code.
  if (process.env.NODE_ENV !== "development") return null;
  if (!getFlag("dev-signin")) return null;

  return (
    <Card className="w-full max-w-sm">
      <p className="mb-3 text-xs font-medium uppercase tracking-wider text-soleur-text-muted">
        Dev sign-in (local only)
      </p>
      <div className="space-y-2">
        {SLOTS.map((slot) => (
          <form
            key={slot}
            action="/api/auth/dev-signin"
            method="post"
          >
            <input type="hidden" name="slot" value={slot} />
            <button
              type="submit"
              className="w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-2 text-sm text-soleur-text-secondary hover:border-soleur-border-emphasized hover:text-soleur-text-primary"
            >
              Sign in as dev-{slot}
            </button>
          </form>
        ))}
      </div>
    </Card>
  );
}
