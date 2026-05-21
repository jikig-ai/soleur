import * as Sentry from "@sentry/nextjs";
import {
  getFlag,
  getTeamWorkspaceAllowlist,
} from "@/lib/feature-flags/server";

// Catches accidental enablement on prd — if FLAG_TEAM_WORKSPACE_INVITE and
// TEAM_WORKSPACE_ALLOWLIST_ORG_IDS both resolve truthy in production, the
// breadcrumb surfaces in Sentry session-replay for any subsequent error and
// makes the gate state visible without exposing tenant org IDs.
export function emitTeamWorkspaceInviteBootBreadcrumb(): void {
  if (process.env.NODE_ENV !== "production") return;
  if (!getFlag("team-workspace-invite")) return;
  const allowlist = getTeamWorkspaceAllowlist();
  if (allowlist.size === 0) return;
  Sentry.addBreadcrumb({
    category: "feature-flag",
    level: "info",
    message: "team-workspace-invite two-key gate ON in production",
    data: {
      allowlistSize: allowlist.size,
    },
  });
}
