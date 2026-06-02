import logger from "@/server/logger";
import { hashUserId } from "@/server/observability";

// AC11 (#4813) — the wrong-workspace detector that ships WITH the single-rail
// prevention. The single nav rail's persistent context band keeps the active
// workspace unambiguous (prevention); this emits the active-workspace context
// at the moment a tenant-sensitive action COMMITS so a wrong-workspace action
// is detectable after the fact, without a dashboard eyeball
// (hr-no-dashboard-eyeball — structured log → Better Stack / Sentry).
//
// The actor id is hashed (hashUserId) so the audit line carries no raw PII.

export type WorkspaceAction = "invite-member" | "api-key-share" | "scope-grant";

export function emitWorkspaceActionContext(params: {
  action: WorkspaceAction;
  userId: string;
  workspaceId: string;
  organizationId?: string;
}): void {
  logger.info(
    {
      event: "workspace_action_context",
      action: params.action,
      actor: hashUserId(params.userId),
      workspaceId: params.workspaceId,
      organizationId: params.organizationId ?? null,
    },
    `workspace-action-context: ${params.action}`,
  );
}
