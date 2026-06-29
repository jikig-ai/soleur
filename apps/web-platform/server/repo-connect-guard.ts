import {
  resolveSoloFounderForInstallation,
  type SoloFounderResolution,
} from "@/server/resolve-founder-for-installation";
import { reportSilentFallback } from "@/server/observability";

// feat-repo-connect-block-offer-join — application-enforced scoped solo-uniqueness
// at the repo-connect boundary (ADR-044 amendment). Completes the "connect path"
// half of the invariant ADR-044 Amendment 2026-06-17b R7 noted was "enforced
// nowhere structurally — only by the connect path + runtime >1 fail-closed":
// before the cloning flip in repo/setup/route.ts, this guard reuses the EXISTING
// solo-founder resolver (one source of truth for the solo invariant — no second,
// drift-prone SQL copy) to decide whether a connect proceeds, is redirected to a
// SWITCH (the owning solo is the caller's own + ready), or is DECLINED.
//
// No new migration / RPC / advisory lock: the WEB-PLATFORM-3M incident is
// sequential (one operator, two sessions); the double-click race is covered by
// the optimistic `.neq("repo_status","cloning")` lock at setup/route.ts:213, and
// the rare true concurrent race degrades to today's behavior via the retained
// resolver `>1` backstop (resolve-founder-for-installation.ts:131).
//
// Pure + injected service client (NO `.service-role-allowlist` entry — the route
// owns `createServiceClient()` and passes it in, mirroring the resolver), so the
// branch logic is unit-testable without HTTP and the route stays HTTP-only
// (cq-nextjs-route-files-http-only-exports).

interface ServiceClient {
  from: (table: string) => unknown;
}

// supabase-js read chain for the `repo_status` gate (mirrors active-repo/route.ts:67).
type RepoStatusChain = {
  select: (cols: string) => RepoStatusChain;
  eq: (col: string, val: string | number) => RepoStatusChain;
  maybeSingle: () => Promise<{
    data: { repo_status?: string | null } | null;
    error: unknown;
  }>;
};

// Discriminated outcome consumed by repo/setup/route.ts AND (forward-compatibly)
// the deferred collaborator request-to-join path. `code` / `canRequestJoin` are
// stable contract fields for that future path. SECURITY (FR5): `existingWorkspaceId`
// is present ONLY on the `switch` arm, where it is the CALLER'S OWN solo id
// (founderId === userId). It is NEVER attached to a decline — on a different-user
// decline the resolved founderId is another user's solo id (== their user UUID),
// and leaking it would be a G3 / IDOR-class disclosure.
export type RepoConnectOutcome =
  | { outcome: "ok" }
  | {
      outcome: "switch";
      code: "workspace_switch_required";
      existingWorkspaceId: string;
      canRequestJoin: false;
    }
  | { outcome: "decline"; code: "repo_connect_blocked"; canRequestJoin: false };

const DECLINE: RepoConnectOutcome = {
  outcome: "decline",
  code: "repo_connect_blocked",
  canRequestJoin: false,
};

// Read the founder workspace's repo_status via the service-role client. The
// resolver returns only `{ kind, founderId }` (no repo_status), so the switch-
// ready gate needs this explicit second read. It runs ONLY on the caller's-own
// arms (founderId === userId), so it adds no cross-user latency signal.
async function isWorkspaceReady(
  service: ServiceClient,
  workspaceId: string,
): Promise<boolean> {
  const chain = service.from("workspaces") as RepoStatusChain;
  const { data } = await chain
    .select("repo_status")
    .eq("id", workspaceId)
    .maybeSingle();
  return (data?.repo_status ?? null) === "ready";
}

/**
 * Decide the connect-time outcome for binding `repoUrl` (under `installationId`)
 * to the caller's active workspace. Branch order is load-bearing: the
 * `founderId === activeWorkspaceId` arm is evaluated BEFORE the
 * `founderId === userId` arm — for a solo user reconnecting from their own active
 * solo, `activeWorkspaceId === userId === founderId`, and testing the userId arm
 * first would wrongly route them to "switch" into the workspace they are already in.
 */
export async function evaluateRepoConnect(params: {
  installationId: number;
  repoUrl: string;
  userId: string;
  activeWorkspaceId: string;
  serviceClient: ServiceClient;
}): Promise<RepoConnectOutcome> {
  const { installationId, repoUrl, userId, activeWorkspaceId, serviceClient } =
    params;

  const resolution: SoloFounderResolution =
    await resolveSoloFounderForInstallation(
      installationId,
      repoUrl,
      serviceClient,
    );

  switch (resolution.kind) {
    case "none":
      return { outcome: "ok" };

    case "found": {
      const { founderId } = resolution;
      // Load-bearing order — see jsdoc above.
      if (founderId === activeWorkspaceId) {
        // The caller's active workspace already owns it → re-connect / no-op.
        return { outcome: "ok" };
      }
      if (founderId === userId) {
        // The caller's OWN solo owns it (reached while acting from a different
        // active workspace). Offer a switch only if that workspace is ready;
        // never switch into a not-ready workspace (GAP-2).
        const ready = await isWorkspaceReady(serviceClient, founderId);
        if (ready) {
          return {
            outcome: "switch",
            code: "workspace_switch_required",
            existingWorkspaceId: founderId, // caller's own id — safe to surface
            canRequestJoin: false,
          };
        }
        return DECLINE;
      }
      // A DIFFERENT user's solo owns it → generic decline. NEVER attach founderId.
      return DECLINE;
    }

    case "ambiguous":
      // A pre-existing duplicate-solo pair already exists for this (install, repo)
      // — the WEB-PLATFORM-3M condition, surfaced at the connect boundary. Fail
      // closed (decline), and page so it is visible (the connect-time signal is
      // distinct from the webhook-time resolver report).
      reportSilentFallback(
        new Error(
          `repo-connect: ambiguous solo founder for (install, repo) — count=${resolution.count}`,
        ),
        {
          feature: "repo-setup",
          op: "connect-guard-ambiguous",
          extra: { installationId, count: resolution.count },
          message:
            "Connect-time block hit a pre-existing duplicate-solo pair (WEB-PLATFORM-3M)",
        },
      );
      return DECLINE;

    case "db-error":
      // The resolver already mirrored the underlying read error (feature
      // github-webhook); re-mirror with the connect-path feature/op so on-call
      // sees the decline was caused by a fail-closed DB error at connect time,
      // not a genuine ownership block.
      reportSilentFallback(
        new Error("repo-connect: solo-founder resolution returned db-error"),
        {
          feature: "repo-setup",
          op: "connect-guard-db-error",
          extra: { installationId },
          message: "Connect-time block fail-closed on resolver db-error",
        },
      );
      return DECLINE;
  }
}
