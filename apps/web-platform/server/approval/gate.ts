/**
 * Production factory for the gated branch's approval dependency (#4672). Wires the flag seam, the service-role
 * gate-side RPC wrappers, the tenant client for the two owner-scoped reads, and the resolvers for the fields the model
 * cannot supply. Tests drive `permission-callback.ts` with a hand-built `ApprovalGateDeps`; this file is the only place
 * that touches Supabase and git for the gate.
 *
 * Boundary: this module must never import `./decide` (the Owner's decision path). The agent shares this process;
 * test/approval/decide-boundary.test.ts walks the import graph to hold that line.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createServiceClient } from "@/lib/supabase/service";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import type { ServerDerived } from "./canonical";
import { isApprovalQueueEnabled } from "./flag";
import { notifyApprovalRequested } from "./notify";
import type { ApprovalGateDeps } from "./gate-types";
import { consumeApproval, getApprovalStatus, submitApprovalRequest, type ApprovalRpcClient } from "./service";
import type { WaitStatus } from "./waiters";

const execFileAsync = promisify(execFile);

const SHA_RE = /^[0-9a-f]{40}$|^[0-9a-f]{64}$/;

/** The workspace HEAD that `pushBranch` pushes (`HEAD:refs/heads/<branch>`): binding it content-addresses the pushed commits. */
async function gitHeadSha(workspacePath: string): Promise<string> {
  const { stdout } = await execFileAsync("git", ["rev-parse", "HEAD"], { cwd: workspacePath, timeout: 10_000 });
  const sha = stdout.trim();
  if (!SHA_RE.test(sha)) throw new Error("workspace HEAD is not a commit sha");
  return sha;
}

/** The slice of a tenant client the gate reads through (owner-scoped by RLS / the RPC's own check). */
interface TenantLike {
  rpc(fn: string, args?: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
  from(table: string): {
    select(cols: string): {
      eq(col: string, val: string): { maybeSingle(): PromiseLike<{ data: unknown; error: unknown }> };
    };
  };
}

export interface CreateApprovalGateDepsArgs {
  userId: string;
  /** Active workspace id of the session (the hash and the row are bound to it). */
  workspaceId: string;
  /** `owner/name` of the connected repository, or "" when none is connected. */
  repoSlug: string;
  workspacePath: string;
  /** Test seams. */
  isEnabled?: () => Promise<boolean>;
  serviceClient?: () => ApprovalRpcClient;
  tenantClient?: () => Promise<TenantLike>;
  headSha?: (workspacePath: string) => Promise<string>;
  /** Push/email dispatch for a newly created request; false = nothing reached the Owner. */
  notifyRequested?: (approvalId: string) => Promise<boolean>;
}

export function createApprovalGateDeps(args: CreateApprovalGateDepsArgs): ApprovalGateDeps {
  let service: ApprovalRpcClient | null = null;
  const svc = (): ApprovalRpcClient => (service ??= (args.serviceClient ?? (() => createServiceClient() as unknown as ApprovalRpcClient))());
  const tenant = (): Promise<TenantLike> =>
    args.tenantClient ? args.tenantClient() : (getFreshTenantClient(args.userId) as unknown as Promise<TenantLike>);
  const headSha = args.headSha ?? gitHeadSha;
  const requireRepo = (): string => {
    if (!args.repoSlug) throw new Error("no connected repository to bind");
    return args.repoSlug;
  };

  return {
    isEnabled: args.isEnabled ?? (() => isApprovalQueueEnabled({ userId: args.userId, workspaceId: args.workspaceId })),
    workspaceId: args.workspaceId,

    async resolveServerDerived(toolName, snapshot): Promise<ServerDerived | undefined> {
      switch (toolName) {
        case "mcp__soleur_platform__email_reply": {
          // The recipient is the stored sender of the inbound item, owner-scoped, exactly as the handler derives it.
          const messageId = snapshot.messageId;
          if (typeof messageId !== "string") throw new Error("reply target missing");
          const t = await tenant();
          const { data, error } = await t.from("email_triage_items").select("id, sender").eq("id", messageId).maybeSingle();
          const sender = (data as { sender?: string | null } | null)?.sender;
          if (error || typeof sender !== "string" || sender.length === 0) throw new Error("reply recipient not resolvable");
          return { recipient: sender };
        }
        case "mcp__soleur_platform__github_push_branch":
          return { repo: requireRepo(), headSha: await headSha(args.workspacePath) };
        case "mcp__soleur_platform__create_pull_request":
        case "mcp__soleur_platform__github_trigger_workflow":
          return { repo: requireRepo() };
        default:
          return undefined;
      }
    },

    submit: (p) => submitApprovalRequest(svc(), p),

    async readStatus(approvalId): Promise<WaitStatus | null> {
      const row = await getApprovalStatus(svc(), approvalId);
      return row ? row.status : null;
    },

    consume: (p) => consumeApproval(svc(), p),

    async onRequested({ approvalId, created }) {
      // A re-ask finds the existing request, whose row was already pushed when it was created: no second nudge.
      if (!created) return;
      const delivered = await (args.notifyRequested ?? notifyApprovalRequested)(approvalId);
      // The gate reports this as its own approval-notify-failed op; the inbox row remains the fallback surface.
      if (!delivered) throw new Error("approval notification not delivered");
    },

    async viewerRole() {
      const t = await tenant();
      const { data, error } = await t.rpc("is_workspace_owner", { p_workspace_id: args.workspaceId, p_user_id: args.userId });
      return !error && data === true ? "owner" : "member";
    },
  };
}
