import * as Sentry from "@sentry/nextjs";
import {
  getRuntimeFlag,
  ANON_IDENTITY,
} from "@/lib/feature-flags/server";

export async function emitTeamWorkspaceInviteBootBreadcrumb(): Promise<void> {
  if (process.env.NODE_ENV !== "production") return;
  const flagOn = await getRuntimeFlag("team-workspace-invite", ANON_IDENTITY);
  if (!flagOn) return;
  Sentry.addBreadcrumb({
    category: "feature-flag",
    level: "info",
    message: "team-workspace-invite single-control gate ON in production",
  });
}
