/**
 * Canonical action + action hash for durable approval requests (#4672, Guard 1).
 *
 * `canonicalizeAction` builds, from the FULL tool input plus platform-derived fields, the one object that is
 * (a) hashed into `approval_request.action_sha256`, (b) stored in `approval_request.canonical_action`, and
 * (c) the only input of `renderApprovalView` (render.ts). Display and hash therefore cannot disagree (P6).
 *
 * Rules (the hashed bytes must be the executed bytes):
 *   - Every field a tool's handler reads is included. The field lists are confirmed against each tool's real zod
 *     schema by test/approval/canonical-schema-drift.test.ts.
 *   - Strings are hashed exactly as supplied: no Unicode normalisation, no trimming, no truncation, no length cap
 *     (the tool's own schema caps; a cap here would make the card disagree with what the handler receives).
 *   - zod defaults the handler applies (`force=false`, `base="main"`, `jurisdiction="unknown"`) are applied here too,
 *     so an omitted field and its default are the same action.
 *   - Keys the handler's zod object would strip are not part of the action (they cannot change what runs).
 *   - Server-derived fields the model cannot supply (the reply recipient, the repository, the HEAD commit being
 *     pushed) are REQUIRED and bound; a missing one is an error, never a silent omission.
 *   - Invalid input throws `ApprovalCanonicalError` with a static message that never echoes the input (the caller
 *     denies the tool call: fail closed).
 *
 * `action_sha256 = sha256(canonicalJson({tool_name, workspace_id, conversation_id, action}))`.
 */

import { createHash } from "node:crypto";
import { z } from "zod/v4";
import { APPROVAL_REQUIRED_TOOLS, type ApprovalToolName, isApprovalRequiredTool } from "./tools";

export const CANONICAL_VERSION = 1 as const;

export type CanonicalValue = string | number | boolean | null | CanonicalValue[] | { [k: string]: CanonicalValue };

export interface CanonicalAction {
  v: typeof CANONICAL_VERSION;
  tool: ApprovalToolName;
  fields: { [k: string]: CanonicalValue };
}

export type ApprovalCanonicalCode = "unsupported_tool" | "invalid_input" | "invalid_server_derived" | "bad_hash_input" | "not_canonical";

export class ApprovalCanonicalError extends Error {
  readonly code: ApprovalCanonicalCode;
  constructor(code: ApprovalCanonicalCode) {
    // Static message per code: never interpolates the tool input (it can carry email bodies and recipients).
    super(`approval canonicalization failed: ${code}`);
    this.name = "ApprovalCanonicalError";
    this.code = code;
  }
}

/** Deterministic JSON: keys sorted by UTF-16 code unit, no whitespace, no undefined/NaN/function values. */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(sortValue(value));
}

function sortValue(value: unknown): CanonicalValue {
  if (value === null) return null;
  switch (typeof value) {
    case "string":
    case "boolean":
      return value;
    case "number":
      if (!Number.isFinite(value)) throw new ApprovalCanonicalError("not_canonical");
      return value;
    case "object": {
      if (Array.isArray(value)) return value.map(sortValue);
      const out: { [k: string]: CanonicalValue } = {};
      for (const k of Object.keys(value as object).sort()) out[k] = sortValue((value as Record<string, unknown>)[k]);
      return out;
    }
    default:
      throw new ApprovalCanonicalError("not_canonical");
  }
}

// ---------------------------------------------------------------------------
// Per-tool schemas. These mirror the zod shapes the tools register (kept in sync by the drift test).
// ---------------------------------------------------------------------------

const art14 = z
  .object({
    identity: z.string().optional(),
    purpose: z.string().optional(),
    legalBasis: z.string().optional(),
    dataSource: z.string().optional(),
    retention: z.string().optional(),
    rights: z.string().optional(),
  })
  .optional();

const complianceFields = {
  jurisdiction: z.enum(["us", "eu_uk", "unknown"]).optional().default("unknown"),
  postalAddress: z.string().optional(),
  optOut: z.string().optional(),
  ftcDisclosure: z.string().optional(),
  art14,
};

const nonEmpty = z.string().min(1);
const sha = z.string().regex(/^[0-9a-f]{40}$|^[0-9a-f]{64}$/);

interface ToolSpec {
  input: z.ZodObject<z.ZodRawShape>;
  server: z.ZodObject<z.ZodRawShape> | null;
}

const SPECS: Record<ApprovalToolName, ToolSpec> = {
  mcp__soleur_platform__email_send: {
    input: z.object({
      to: z.string().min(3),
      subject: z.string().min(1),
      body: z.string().min(1),
      replyTo: z.string().optional(),
      ...complianceFields,
    }),
    server: null,
  },
  mcp__soleur_platform__email_reply: {
    input: z.object({
      messageId: z.string().uuid(),
      subject: z.string().min(1),
      body: z.string().min(1),
      ...complianceFields,
    }),
    // The recipient is the stored sender of the inbound item (P0-3): absent from the model's input, bound here.
    server: z.object({ recipient: nonEmpty }),
  },
  mcp__soleur_platform__email_suppress: {
    input: z.object({
      recipient: z.string().min(3),
      reason: z.enum(["opt_out", "decline", "bounce", "manual"]),
    }),
    server: null,
  },
  mcp__soleur_platform__github_push_branch: {
    input: z.object({ branch: nonEmpty, force: z.boolean().default(false) }),
    // `headSha` is the workspace HEAD that `pushBranch` pushes: binding it content-addresses the pushed commits.
    server: z.object({ repo: nonEmpty, headSha: sha }),
  },
  mcp__soleur_platform__create_pull_request: {
    input: z.object({
      head: nonEmpty,
      base: z.string().default("main"),
      title: z.string(),
      body: z.string().optional(),
    }),
    server: z.object({ repo: nonEmpty }),
  },
  mcp__soleur_platform__github_trigger_workflow: {
    input: z.object({
      workflow_id: z.number().refine(Number.isSafeInteger),
      ref: nonEmpty,
      inputs: z.record(z.string(), z.string()).optional(),
    }),
    server: z.object({ repo: nonEmpty }),
  },
  mcp__soleur_platform__kb_share_create: {
    input: z.object({ documentPath: nonEmpty }),
    server: null,
  },
  mcp__soleur_platform__workspace_set_autonomous: {
    input: z.object({ value: z.boolean() }),
    server: null,
  },
};

/** The server-derived fields each tool requires (consumed by the gate, which fills them). */
export type ServerDerived = Record<string, string>;

function dropUndefined(o: Record<string, unknown>): { [k: string]: CanonicalValue } {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(o)) {
    if (v === undefined) continue;
    out[k] = v && typeof v === "object" && !Array.isArray(v) ? dropUndefined(v as Record<string, unknown>) : v;
  }
  return out as { [k: string]: CanonicalValue };
}

export function canonicalizeAction(tool: string, input: unknown, serverDerived?: unknown): CanonicalAction {
  if (!isApprovalRequiredTool(tool)) throw new ApprovalCanonicalError("unsupported_tool");
  const spec = SPECS[tool];

  const parsedInput = spec.input.safeParse(input);
  if (!parsedInput.success) throw new ApprovalCanonicalError("invalid_input");

  let server: Record<string, unknown> = {};
  if (spec.server) {
    const parsedServer = spec.server.safeParse(serverDerived);
    if (!parsedServer.success) throw new ApprovalCanonicalError("invalid_server_derived");
    server = parsedServer.data as Record<string, unknown>;
  }

  const fields = dropUndefined({ ...(parsedInput.data as Record<string, unknown>), ...server });
  // Re-derive through sortValue so the stored object is plain canonical JSON (and non-canonical values throw here).
  const sorted = sortValue(fields) as { [k: string]: CanonicalValue };
  return { v: CANONICAL_VERSION, tool, fields: sorted };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface ActionHashInput {
  toolName: string;
  workspaceId: string;
  conversationId: string;
  action: CanonicalAction;
}

export function computeActionHash(input: ActionHashInput): string {
  if (!UUID_RE.test(input.workspaceId) || !UUID_RE.test(input.conversationId)) {
    throw new ApprovalCanonicalError("bad_hash_input");
  }
  if (input.toolName !== input.action.tool || !APPROVAL_REQUIRED_TOOLS.includes(input.toolName as ApprovalToolName)) {
    throw new ApprovalCanonicalError("bad_hash_input");
  }
  const text = canonicalJson({
    tool_name: input.toolName,
    workspace_id: input.workspaceId,
    conversation_id: input.conversationId,
    action: input.action,
  });
  return createHash("sha256").update(text, "utf8").digest("hex");
}
