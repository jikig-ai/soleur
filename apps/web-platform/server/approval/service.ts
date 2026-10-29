/**
 * Durable approval request service (#4672): thin, typed wrappers over the migration-180 RPCs.
 *
 * Every call is an RPC; there is no table access. The gate-side functions here (create, consume, get, list,
 * submit) take a SERVICE-role client. The Owner's decision lives in `decide.ts` (user-JWT client only) and is
 * deliberately NOT exported from this module: the agent shares this process, and the sentinel that no module
 * reachable from the MCP tool builders or the canUseTool deps can reach the decide path is only meaningful if
 * decide sits behind its own import.
 *
 * Errors: an RPC failure throws `ApprovalServiceError` with a STATIC message (never database text, which can
 * echo row content) and the SQLSTATE in `code`. `consumeApproval` is the exception: it NEVER throws and NEVER
 * reports `consumed: true` unless the database said so, because its caller turns "consumed" into an allow.
 * Callers own the Sentry ops (each with its own static message); this module reports nothing.
 */

export const APPROVAL_STATUSES = ["pending", "approved", "rejected", "expired", "consumed"] as const;
export type ApprovalStatus = (typeof APPROVAL_STATUSES)[number];

/**
 * Allowed transitions: forward-only plus the Owner revoke (`approved -> rejected`, an unconsumed approval withdrawn).
 * MUST equal the `(OLD.status, NEW.status) NOT IN (...)` list in the migration trigger; the parity test
 * (test/approval/migration-180-approval-request.test.ts) parses the SQL and compares.
 */
export const APPROVAL_TRANSITIONS: ReadonlyArray<readonly [ApprovalStatus, ApprovalStatus]> = [
  ["pending", "approved"],
  ["pending", "rejected"],
  ["pending", "expired"],
  ["approved", "consumed"],
  ["approved", "expired"],
  ["approved", "rejected"],
];

export interface RpcResult {
  data: unknown;
  error: { message: string; code?: string } | null;
}

/** The slice of a Supabase client these wrappers use. */
export interface ApprovalRpcClient {
  rpc(fn: string, args?: Record<string, unknown>): PromiseLike<RpcResult>;
}

export class ApprovalServiceError extends Error {
  readonly fn: string;
  readonly code?: string;
  constructor(fn: string, code?: string) {
    super(`approval rpc failed: ${fn}`);
    this.name = "ApprovalServiceError";
    this.fn = fn;
    this.code = code;
  }
}

export interface ApprovalRow {
  id: string;
  workspace_id: string;
  conversation_id: string;
  requested_by_user_id: string | null;
  tool_name: string;
  action_sha256: string;
  status: ApprovalStatus;
  expires_at: string;
  decided_at: string | null;
  decided_by: string | null;
  consumed_at: string | null;
  expired_at: string | null;
  /** Set once with the Owner revoke (`approved -> rejected`); null otherwise. */
  revoked_at: string | null;
  revoked_by: string | null;
  unanswered_flagged_at: string | null;
  created_at: string;
  canonical_action: unknown | null;
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isStatus = (v: unknown): v is ApprovalStatus => typeof v === "string" && (APPROVAL_STATUSES as readonly string[]).includes(v);

export function parseApprovalRow(fn: string, v: unknown): ApprovalRow {
  if (!isObj(v) || typeof v.id !== "string" || !isStatus(v.status) || typeof v.action_sha256 !== "string" || typeof v.conversation_id !== "string") {
    throw new ApprovalServiceError(fn, "bad_payload");
  }
  return v as unknown as ApprovalRow;
}

async function call(client: ApprovalRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new ApprovalServiceError(fn, error.code);
  return data;
}

// ---------------------------------------------------------------------------

export interface CreateApprovalParams {
  workspaceId: string;
  conversationId: string;
  requestedByUserId: string;
  toolName: string;
  actionSha256: string;
  canonicalAction: unknown;
  /** Seconds until the request expires; the database rejects an out-of-range value with 22023 (default 24 h). */
  ttlSeconds?: number;
}

export interface CreateApprovalResult {
  approval: ApprovalRow;
  /** False when the call found an existing live request for the same (conversation, action hash). */
  created: boolean;
  /** Requests for this (conversation, action hash) across all statuses; the card header reads from 2 onward. */
  requestCount: number;
  /**
   * Whether to push/email the Owner: true only for a NEW request when no other pending request of the workspace was
   * created in the last 10 minutes (coalescing). The card and inbox row exist either way.
   */
  notify: boolean;
  /** ISO timestamp the request expires at (so notifications need no table read). */
  expiresAt: string;
}

/** SQLSTATEs `create_approval_request` raises when a pending cap is hit: 5 per conversation, 20 per workspace. */
export const APPROVAL_CAP_CODES = { AP429: "conversation", AP430: "workspace" } as const;
export type ApprovalCapScope = (typeof APPROVAL_CAP_CODES)[keyof typeof APPROVAL_CAP_CODES];

/** A pending cap was reached (`code` is AP429 for the conversation cap, AP430 for the workspace cap). */
export class ApprovalCapReachedError extends ApprovalServiceError {
  readonly scope: ApprovalCapScope;
  constructor(fn: string, code: keyof typeof APPROVAL_CAP_CODES) {
    super(fn, code);
    this.name = "ApprovalCapReachedError";
    this.scope = APPROVAL_CAP_CODES[code];
  }
}

export async function createApprovalRequest(client: ApprovalRpcClient, p: CreateApprovalParams): Promise<CreateApprovalResult> {
  const args: Record<string, unknown> = {
    p_workspace_id: p.workspaceId,
    p_conversation_id: p.conversationId,
    p_requested_by: p.requestedByUserId,
    p_tool_name: p.toolName,
    p_action_sha256: p.actionSha256,
    p_canonical_action: p.canonicalAction,
  };
  if (p.ttlSeconds !== undefined) args.p_ttl_seconds = p.ttlSeconds;
  let data: unknown;
  try {
    data = await call(client, "create_approval_request", args);
  } catch (e) {
    const code = e instanceof ApprovalServiceError ? e.code : undefined;
    if (code === "AP429" || code === "AP430") throw new ApprovalCapReachedError("create_approval_request", code);
    throw e;
  }
  // notify / expires_at are additive fields: an absent one (a database that predates them) degrades safely
  // (notify true = the Owner is nudged; expiresAt from the row), a PRESENT one of the wrong type is a bad payload.
  if (
    !isObj(data) ||
    typeof data.created !== "boolean" ||
    typeof data.request_count !== "number" ||
    (data.notify !== undefined && typeof data.notify !== "boolean") ||
    (data.expires_at !== undefined && typeof data.expires_at !== "string")
  ) {
    throw new ApprovalServiceError("create_approval_request", "bad_payload");
  }
  const approval = parseApprovalRow("create_approval_request", data.approval);
  return {
    approval,
    created: data.created,
    requestCount: data.request_count,
    notify: data.notify ?? true,
    expiresAt: data.expires_at ?? approval.expires_at,
  };
}

// ---------------------------------------------------------------------------

export type ConsumeRejectReason =
  | "not_found"
  | "hash_mismatch"
  | "wrong_conversation"
  | "expired"
  | "decider_not_owner"
  | "requester_not_member"
  | "not_approved"
  | "already_consumed"
  | "rpc_error"
  | "bad_request"
  | "unknown";

export type ConsumeResult = { consumed: true } | { consumed: false; reason: ConsumeRejectReason | string };

const HASH_RE = /^[0-9a-f]{64}$/;

/**
 * Turns an approved request into a single release. Fail closed in every direction: a malformed bind never reaches
 * the database, and any error, null, or unexpected shape is a rejection. Only `{consumed: true}` from the database
 * (strictly boolean true) is a consume.
 */
export async function consumeApproval(
  client: ApprovalRpcClient,
  p: { id: string; hash: string; conversationId: string },
): Promise<ConsumeResult> {
  if (!HASH_RE.test(p.hash)) return { consumed: false, reason: "bad_request" };
  let res: RpcResult;
  try {
    res = await client.rpc("consume_approval", { p_id: p.id, p_hash: p.hash, p_conversation: p.conversationId });
  } catch {
    return { consumed: false, reason: "rpc_error" };
  }
  if (res.error) return { consumed: false, reason: "rpc_error" };
  const d = res.data;
  if (isObj(d) && d.consumed === true) return { consumed: true };
  if (isObj(d) && d.consumed === false && typeof d.reason === "string") return { consumed: false, reason: d.reason };
  return { consumed: false, reason: "unknown" };
}

export type SubmitResult =
  | { kind: "released"; approvalId: string; requestCount: number }
  | { kind: "wait"; approval: ApprovalRow; created: boolean; requestCount: number; notify: boolean; expiresAt: string }
  | { kind: "consume_rejected"; approvalId: string; reason: string }
  | { kind: "not_waitable"; approval: ApprovalRow; requestCount: number }
  /** A pending cap was hit; nothing was saved. `scope` says which cap (5 per conversation, 20 per workspace). */
  | { kind: "cap_reached"; scope: ApprovalCapScope };

/**
 * Create-or-find the live request and decide what the gate does next. A live request that is ALREADY approved
 * (the Owner approved after the agent stopped waiting, then the agent asked again with identical arguments) is
 * consumed at once: no card, no wait. A pending one goes to the wait loop. Anything else is not waitable.
 */
export async function submitApprovalRequest(client: ApprovalRpcClient, p: CreateApprovalParams): Promise<SubmitResult> {
  let r: CreateApprovalResult;
  try {
    r = await createApprovalRequest(client, p);
  } catch (e) {
    if (e instanceof ApprovalCapReachedError) return { kind: "cap_reached", scope: e.scope };
    throw e;
  }
  if (r.approval.status === "approved") {
    const c = await consumeApproval(client, { id: r.approval.id, hash: p.actionSha256, conversationId: p.conversationId });
    return c.consumed
      ? { kind: "released", approvalId: r.approval.id, requestCount: r.requestCount }
      : { kind: "consume_rejected", approvalId: r.approval.id, reason: c.reason };
  }
  if (r.approval.status === "pending") {
    return {
      kind: "wait",
      approval: r.approval,
      created: r.created,
      requestCount: r.requestCount,
      notify: r.notify,
      expiresAt: r.expiresAt,
    };
  }
  return { kind: "not_waitable", approval: r.approval, requestCount: r.requestCount };
}

// ---------------------------------------------------------------------------

/** The scalar projection `get_approval_status` returns: no action text, no user ids. */
export interface ApprovalStatusRow {
  id: string;
  status: ApprovalStatus;
  expires_at: string;
  decided_at: string | null;
  consumed_at: string | null;
  expired_at: string | null;
  revoked_at: string | null;
  unanswered_flagged_at: string | null;
  created_at: string;
  tool_name: string;
  action_sha256: string;
  conversation_id: string;
  workspace_id: string;
}

export async function getApprovalStatus(client: ApprovalRpcClient, id: string): Promise<ApprovalStatusRow | null> {
  const data = await call(client, "get_approval_status", { p_id: id });
  if (data === null || data === undefined) return null;
  const row = parseApprovalRow("get_approval_status", data);
  // The RPC never returns the action text or the user ids: drop them even if a future change leaked one.
  const { canonical_action: _a, requested_by_user_id: _r, decided_by: _d, revoked_by: _v, ...status } = row;
  return status as unknown as ApprovalStatusRow;
}

export interface LiveApproval {
  approval: ApprovalRow;
  requestCount: number;
}

export async function listLiveApprovals(client: ApprovalRpcClient, conversationId: string): Promise<LiveApproval[]> {
  const data = await call(client, "list_live_approvals", { p_conversation: conversationId });
  if (data === null || data === undefined) return [];
  if (!Array.isArray(data)) throw new ApprovalServiceError("list_live_approvals", "bad_payload");
  return data.map((d) => {
    if (!isObj(d) || typeof d.request_count !== "number") throw new ApprovalServiceError("list_live_approvals", "bad_payload");
    return { approval: parseApprovalRow("list_live_approvals", d.approval), requestCount: d.request_count };
  });
}

export interface SweepExpired {
  id: string;
  workspaceId: string;
  toolName: string;
  /** `unanswered` = nobody decided; `unconsumed` = approved but the agent never asked again. */
  reason: "unanswered" | "unconsumed";
}

export interface SweepResult {
  expired: SweepExpired[];
  flagged: Array<{ id: string; workspaceId: string; toolName: string }>;
  scrubbed: number;
}

export async function sweepApprovals(client: ApprovalRpcClient): Promise<SweepResult> {
  const data = await call(client, "sweep_approvals", {});
  if (!isObj(data) || !Array.isArray(data.expired) || !Array.isArray(data.flagged) || typeof data.scrubbed !== "number") {
    throw new ApprovalServiceError("sweep_approvals", "bad_payload");
  }
  return {
    expired: data.expired.map((e: Record<string, unknown>) => ({
      id: String(e.id),
      workspaceId: String(e.workspace_id),
      toolName: String(e.tool_name),
      reason: e.reason === "unconsumed" ? "unconsumed" : "unanswered",
    })),
    flagged: data.flagged.map((e: Record<string, unknown>) => ({
      id: String(e.id),
      workspaceId: String(e.workspace_id),
      toolName: String(e.tool_name),
    })),
    scrubbed: data.scrubbed,
  };
}
