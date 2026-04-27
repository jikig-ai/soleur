// Zod schemas for the Command Center WebSocket protocol (#2885 Stage 3).
//
// `parseWSMessage` is the strict, fail-closed gate the client `onmessage`
// handler uses to validate incoming frames before dispatching them to the
// reducer. The schema covers every variant of `WSMessage` from `lib/types.ts`;
// drift between the schema and the union is caught at compile time by the
// `_SchemaCovers` bidirectional structural assertion at the bottom of this
// file.
//
// Every variant is a `z.strictObject` (rejects unknown top-level fields) so
// a server emitting an undocumented field fails loudly rather than silently
// dropping it. Together with `z.discriminatedUnion("type", ...)` this gives
// O(1) discriminator dispatch on the hot per-frame path — see
// `lib/ws-client.ts:onmessage`.
//
// IDs are plain `z.string().min(1)` because the wire format has no brand
// concept; branded utility types from `lib/branded-ids.ts` are used at
// internal API boundaries (registry signatures, mint helpers).

import { z, type ZodError } from "zod";
import {
  type WSMessage,
  WORKFLOW_END_STATUSES,
  SUBAGENT_COMPLETE_STATUSES,
  INTERACTIVE_PROMPT_KINDS,
} from "@/lib/types";

// ---------------------------------------------------------------------------
// ID schemas (min length 1 — empty IDs are server bugs, not legitimate frames)
// ---------------------------------------------------------------------------

const conversationIdSchema = z.string().min(1);
const promptIdSchema = z.string().min(1);
const spawnIdSchema = z.string().min(1);

// DomainLeaderId — pinned to the 10-id allowlist from
// `server/domain-leaders.ts`. The list is short and stable; pinning here
// makes the bidirectional `_SchemaCovers` proof structurally complete (Zod
// cannot otherwise prove `z.string()` satisfies the narrow `DomainLeaderId`
// union). Add a new leader → add a new entry here AND in
// `server/domain-leaders.ts` AND in tests; tsc will guide you.
const domainLeaderIdSchema = z.enum([
  "cmo",
  "cto",
  "cfo",
  "cpo",
  "cro",
  "coo",
  "clo",
  "cco",
  "system",
  "cc_router",
]);

const workflowNameSchema = z.enum([
  "one-shot",
  "brainstorm",
  "plan",
  "work",
  "review",
  "drain-labeled-backlog",
]);

// ---------------------------------------------------------------------------
// Shared object schemas
// ---------------------------------------------------------------------------

const attachmentRefSchema = z.strictObject({
  storagePath: z.string(),
  filename: z.string(),
  contentType: z.string(),
  sizeBytes: z.number(),
});

const conversationContextSchema = z.strictObject({
  path: z.string(),
  type: z.string(),
  content: z.string().optional(),
});

const todoItemSchema = z.strictObject({
  id: z.string(),
  content: z.string(),
  status: z.enum(["pending", "in_progress", "completed"]),
});

// ---------------------------------------------------------------------------
// `interactive_prompt.kind` payload schemas — exported standalone for tests
// and for downstream consumers that want to validate a payload independent
// of the surrounding `interactive_prompt` envelope.
// ---------------------------------------------------------------------------

const askUserPayloadSchema = z.strictObject({
  kind: z.literal("ask_user"),
  payload: z.strictObject({
    question: z.string(),
    options: z.array(z.string()),
    multiSelect: z.boolean(),
  }),
});

const planPreviewPayloadSchema = z.strictObject({
  kind: z.literal("plan_preview"),
  payload: z.strictObject({ markdown: z.string() }),
});

const diffPayloadSchema = z.strictObject({
  kind: z.literal("diff"),
  payload: z.strictObject({
    path: z.string(),
    additions: z.number(),
    deletions: z.number(),
  }),
});

// `bash_approval`: the server has already classified the SDK request and is
// asking the user to approve. `command` and `cwd` flow through to a UI
// modal; the bound caps are defense-in-depth against an unbounded
// server-side payload exhausting client memory (CWE-400).
const bashApprovalPayloadSchema = z.strictObject({
  kind: z.literal("bash_approval"),
  payload: z.strictObject({
    command: z.string().max(16_384),
    cwd: z.string().max(4_096),
    gated: z.boolean(),
  }),
});

const todoWritePayloadSchema = z.strictObject({
  kind: z.literal("todo_write"),
  payload: z.strictObject({ items: z.array(todoItemSchema) }),
});

const notebookEditPayloadSchema = z.strictObject({
  kind: z.literal("notebook_edit"),
  payload: z.strictObject({
    notebookPath: z.string(),
    cellIds: z.array(z.string()),
  }),
});

export const interactivePromptPayloadSchema = z.discriminatedUnion("kind", [
  askUserPayloadSchema,
  planPreviewPayloadSchema,
  diffPayloadSchema,
  bashApprovalPayloadSchema,
  todoWritePayloadSchema,
  notebookEditPayloadSchema,
]);

// ---------------------------------------------------------------------------
// `interactive_prompt_response.kind` schemas — same pattern but with
// per-kind `response` shapes.
// ---------------------------------------------------------------------------

const askUserResponseSchema = z.strictObject({
  promptId: promptIdSchema,
  conversationId: conversationIdSchema,
  kind: z.literal("ask_user"),
  response: z.union([z.string(), z.array(z.string())]),
});

const planPreviewResponseSchema = z.strictObject({
  promptId: promptIdSchema,
  conversationId: conversationIdSchema,
  kind: z.literal("plan_preview"),
  response: z.enum(["accept", "iterate"]),
});

const bashApprovalResponseSchema = z.strictObject({
  promptId: promptIdSchema,
  conversationId: conversationIdSchema,
  kind: z.literal("bash_approval"),
  response: z.enum(["approve", "deny"]),
});

const ackResponseSchema = z.strictObject({
  promptId: promptIdSchema,
  conversationId: conversationIdSchema,
  kind: z.enum(["diff", "todo_write", "notebook_edit"]),
  response: z.literal("ack"),
});

export const interactivePromptResponseSchema = z.discriminatedUnion("kind", [
  askUserResponseSchema,
  planPreviewResponseSchema,
  bashApprovalResponseSchema,
  ackResponseSchema,
]);

// ---------------------------------------------------------------------------
// Per-`type` `WSMessage` schemas — flat `z.strictObject` for every variant,
// no `.and()` composition, so the top-level union is a clean
// `z.discriminatedUnion("type", ...)` with O(1) dispatch.
// ---------------------------------------------------------------------------

const authSchema = z.strictObject({ type: z.literal("auth"), token: z.string() });
const authOkSchema = z.strictObject({ type: z.literal("auth_ok") });
const chatSchema = z.strictObject({
  type: z.literal("chat"),
  content: z.string(),
  attachments: z.array(attachmentRefSchema).optional(),
});
const startSessionSchema = z.strictObject({
  type: z.literal("start_session"),
  leaderId: domainLeaderIdSchema.optional(),
  context: conversationContextSchema.optional(),
  resumeByContextPath: z.string().optional(),
});
const resumeSessionSchema = z.strictObject({
  type: z.literal("resume_session"),
  conversationId: z.string(),
});
const closeConversationSchema = z.strictObject({ type: z.literal("close_conversation") });
const reviewGateResponseSchema = z.strictObject({
  type: z.literal("review_gate_response"),
  gateId: z.string(),
  selection: z.string(),
});
const streamSchema = z.strictObject({
  type: z.literal("stream"),
  content: z.string(),
  partial: z.boolean(),
  leaderId: domainLeaderIdSchema,
});
const streamStartSchema = z.strictObject({
  type: z.literal("stream_start"),
  leaderId: domainLeaderIdSchema,
  source: z.enum(["auto", "mention"]).optional(),
});
const streamEndSchema = z.strictObject({
  type: z.literal("stream_end"),
  leaderId: domainLeaderIdSchema,
});
const toolUseSchema = z.strictObject({
  type: z.literal("tool_use"),
  leaderId: domainLeaderIdSchema,
  label: z.string(),
});
const toolProgressSchema = z.strictObject({
  type: z.literal("tool_progress"),
  leaderId: domainLeaderIdSchema,
  toolUseId: z.string(),
  toolName: z.string(),
  elapsedSeconds: z.number(),
});
const reviewGateSchema = z.strictObject({
  type: z.literal("review_gate"),
  gateId: z.string(),
  question: z.string(),
  header: z.string().optional(),
  options: z.array(z.string()),
  descriptions: z.record(z.string(), z.string().optional()).optional(),
  stepProgress: z
    .strictObject({ current: z.number(), total: z.number() })
    .optional(),
});
const sessionStartedSchema = z.strictObject({
  type: z.literal("session_started"),
  conversationId: z.string(),
  // Stage 3 (#2885) — optional capability manifest. When present, lists the
  // `interactive_prompt.kind` values this server build can emit. Absent =
  // legacy server, treat as the default 6-kind set. Lets external agents
  // skip a feature-detection round-trip.
  capabilities: z
    .strictObject({ promptKinds: z.array(z.string()).readonly() })
    .optional(),
});
const sessionResumedSchema = z.strictObject({
  type: z.literal("session_resumed"),
  conversationId: z.string(),
  resumedFromTimestamp: z.string(),
  messageCount: z.number(),
});
const sessionEndedSchema = z.strictObject({
  type: z.literal("session_ended"),
  reason: z.string(),
});
const usageUpdateSchema = z.strictObject({
  type: z.literal("usage_update"),
  conversationId: z.string(),
  totalCostUsd: z.number(),
  inputTokens: z.number(),
  outputTokens: z.number(),
});
const fanoutTruncatedSchema = z.strictObject({
  type: z.literal("fanout_truncated"),
  dispatched: z.number(),
  dropped: z.number(),
});
const upgradePendingSchema = z.strictObject({ type: z.literal("upgrade_pending") });
const errorSchema = z.strictObject({
  type: z.literal("error"),
  message: z.string(),
  errorCode: z
    .enum([
      "key_invalid",
      "session_expired",
      "session_resumed",
      "rate_limited",
      "idle_timeout",
      "upload_failed",
      "file_too_large",
      "unsupported_file_type",
      "too_many_files",
      "interactive_prompt_rejected",
    ])
    .optional(),
  gateId: z.string().optional(),
});

// Stage 3 (#2885) — new event variants
const subagentSpawnSchema = z.strictObject({
  type: z.literal("subagent_spawn"),
  parentId: spawnIdSchema,
  leaderId: domainLeaderIdSchema,
  spawnId: spawnIdSchema,
  // Stage 3 (#2885) — optional one-line description of what this subagent
  // is doing. Mirrors the SDK's `description` parameter; lets external
  // observers (CI scripts, Sentry breadcrumbs) understand sub-agent intent
  // without parsing the full WS stream.
  task: z.string().max(2_048).optional(),
});

const subagentCompleteSchema = z.strictObject({
  type: z.literal("subagent_complete"),
  spawnId: spawnIdSchema,
  status: z.enum(SUBAGENT_COMPLETE_STATUSES),
});

const workflowStartedSchema = z.strictObject({
  type: z.literal("workflow_started"),
  workflow: workflowNameSchema,
  conversationId: conversationIdSchema,
});

const workflowEndedSchema = z.strictObject({
  type: z.literal("workflow_ended"),
  workflow: workflowNameSchema,
  status: z.enum(WORKFLOW_END_STATUSES),
  summary: z.string().optional(),
});

// `interactive_prompt` and `interactive_prompt_response` flatten to
// (type, promptId, conversationId, kind, payload/response). Each (type,
// kind) pair is its own `z.strictObject` so the top-level union remains a
// clean discriminated union on `type`.
function makeInteractivePromptSchema<K extends typeof INTERACTIVE_PROMPT_KINDS[number], P extends z.ZodTypeAny>(kind: K, payload: P) {
  return z.strictObject({
    type: z.literal("interactive_prompt"),
    promptId: promptIdSchema,
    conversationId: conversationIdSchema,
    kind: z.literal(kind),
    payload,
  });
}

const ipAskUserSchema = makeInteractivePromptSchema("ask_user", askUserPayloadSchema.shape.payload);
const ipPlanPreviewSchema = makeInteractivePromptSchema("plan_preview", planPreviewPayloadSchema.shape.payload);
const ipDiffSchema = makeInteractivePromptSchema("diff", diffPayloadSchema.shape.payload);
const ipBashApprovalSchema = makeInteractivePromptSchema("bash_approval", bashApprovalPayloadSchema.shape.payload);
const ipTodoWriteSchema = makeInteractivePromptSchema("todo_write", todoWritePayloadSchema.shape.payload);
const ipNotebookEditSchema = makeInteractivePromptSchema("notebook_edit", notebookEditPayloadSchema.shape.payload);

const interactivePromptSchema = z.discriminatedUnion("kind", [
  ipAskUserSchema,
  ipPlanPreviewSchema,
  ipDiffSchema,
  ipBashApprovalSchema,
  ipTodoWriteSchema,
  ipNotebookEditSchema,
]);

const interactivePromptResponseTopSchema = z.discriminatedUnion("kind", [
  z.strictObject({
    type: z.literal("interactive_prompt_response"),
    promptId: promptIdSchema,
    conversationId: conversationIdSchema,
    kind: z.literal("ask_user"),
    response: z.union([z.string(), z.array(z.string())]),
  }),
  z.strictObject({
    type: z.literal("interactive_prompt_response"),
    promptId: promptIdSchema,
    conversationId: conversationIdSchema,
    kind: z.literal("plan_preview"),
    response: z.enum(["accept", "iterate"]),
  }),
  z.strictObject({
    type: z.literal("interactive_prompt_response"),
    promptId: promptIdSchema,
    conversationId: conversationIdSchema,
    kind: z.literal("bash_approval"),
    response: z.enum(["approve", "deny"]),
  }),
  z.strictObject({
    type: z.literal("interactive_prompt_response"),
    promptId: promptIdSchema,
    conversationId: conversationIdSchema,
    kind: z.enum(["diff", "todo_write", "notebook_edit"]),
    response: z.literal("ack"),
  }),
]);

// ---------------------------------------------------------------------------
// Top-level `wsMessageSchema` — the top union dispatches on `type` first via
// a small table, then falls through to the inner `interactive_prompt*`
// discriminated unions. This avoids a 30+ branch `z.union` walk on every
// hot-path frame.
// ---------------------------------------------------------------------------

const flatTypeSchema = z.discriminatedUnion("type", [
  authSchema,
  authOkSchema,
  chatSchema,
  startSessionSchema,
  resumeSessionSchema,
  closeConversationSchema,
  reviewGateResponseSchema,
  streamSchema,
  streamStartSchema,
  streamEndSchema,
  toolUseSchema,
  toolProgressSchema,
  reviewGateSchema,
  sessionStartedSchema,
  sessionResumedSchema,
  sessionEndedSchema,
  usageUpdateSchema,
  fanoutTruncatedSchema,
  upgradePendingSchema,
  errorSchema,
  subagentSpawnSchema,
  subagentCompleteSchema,
  workflowStartedSchema,
  workflowEndedSchema,
]);

export const wsMessageSchema = z.union([
  flatTypeSchema,
  interactivePromptSchema,
  interactivePromptResponseTopSchema,
]);

// ---------------------------------------------------------------------------
// parseWSMessage — fail-closed wrapper consumed by `ws-client.ts:onmessage`.
// Note: the inferred return type of `wsMessageSchema.safeParse` is
// structurally identical to `WSMessage`; the `_SchemaCovers` assertion
// below pins the equivalence so no narrowing cast is needed.
// ---------------------------------------------------------------------------

export type ParseWSMessageResult =
  | { ok: true; msg: WSMessage }
  | { ok: false; error: ZodError };

export function parseWSMessage(raw: unknown): ParseWSMessageResult {
  const result = wsMessageSchema.safeParse(raw);
  if (result.success) {
    return { ok: true, msg: result.data };
  }
  return { ok: false, error: result.error };
}

// ---------------------------------------------------------------------------
// Bidirectional drift guard — every `WSMessage` variant must be covered by
// the schema, and every schema-inferred variant must appear in `WSMessage`.
// The two `_check` consts assert structural equivalence in both directions:
// either side gaining/losing a field on any variant fails compilation here.
// ---------------------------------------------------------------------------

type SchemaInferred = z.infer<typeof wsMessageSchema>;

// Forward: every WSMessage value must be assignable to the inferred type.
const _SchemaCoversForward = (msg: WSMessage): SchemaInferred => msg;
// Backward: every inferred value must be assignable to WSMessage.
const _SchemaCoversBackward = (msg: SchemaInferred): WSMessage => msg;
void _SchemaCoversForward;
void _SchemaCoversBackward;
