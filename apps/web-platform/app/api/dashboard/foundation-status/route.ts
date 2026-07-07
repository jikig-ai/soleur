import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import { statKnownPaths } from "@/server/kb-reader";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { resolveActiveWorkspaceKbRoot } from "@/server/workspace-resolver";
import { reportSilentFallback } from "@/server/observability";
import { DASHBOARD_FOUNDATION_KB_PATHS } from "@/lib/kb-constants";

// Cheap foundation-status endpoint (plan 2026-07-07 Phase 2). The dashboard
// derives foundation/operational card completion + first-run (`vision.md`) state
// from the existence + size of ~10 KNOWN KB paths. Previously it consumed
// `/api/kb/tree`, which runs a full recursive `buildTree()` walk of the entire
// KB directory and gated first paint on it. This route stats only the known
// paths (via the active-workspace KB-root resolution shared with kb/tree) — no
// whole-tree walk on cold load.
async function getHandler(_req: Request, user: User) {
  const serviceClient = createServiceClient();

  // ADR-044 (#4543): the KB lives on the ACTIVE workspace, not the caller's own
  // `users` row. Mirrors the kb/tree route's resolution + status mapping so the
  // dashboard's 401/503/404 → redirect/provisioning/empty state mapping is
  // preserved unchanged.
  const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);
  if (!access.ok) {
    return access.status === 404
      ? NextResponse.json({ error: "Workspace not found" }, { status: 404 })
      : NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }

  try {
    const paths = await statKnownPaths(access.kbRoot, DASHBOARD_FOUNDATION_KB_PATHS);
    return NextResponse.json({ paths });
  } catch (err) {
    // statKnownPaths swallows per-path errors, so reaching here is unexpected
    // (e.g. an unreadable kbRoot). Mirror to Sentry rather than blanking the
    // foundation cards silently (cq-silent-fallback-must-mirror-to-sentry).
    logger.error({ err }, "dashboard/foundation-status: unexpected error");
    reportSilentFallback(err, {
      feature: "dashboard.foundation-status",
      op: "statKnownPaths",
      extra: { userId: user.id },
    });
    return NextResponse.json(
      { error: "An unexpected error occurred" },
      { status: 500 },
    );
  }
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "dashboard.foundation-status",
});
