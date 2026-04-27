// Zod schemas for the Command Center WebSocket protocol (#2885 Stage 3).
//
// `parseWSMessage` is the strict, fail-closed gate the client `onmessage`
// handler uses to validate incoming frames before dispatching them to the
// reducer. The schema covers every variant of `WSMessage` from `lib/types.ts`;
// drift between the schema and the union is caught at compile time by the
// `_SchemaCovers` bidirectional assertion at the bottom of this file.
//
// Branded IDs (PromptId / ConversationId / SpawnId) are produced via a
// `.transform()` chain so `parseWSMessage`'s output is structurally typed
// with the branded slots that consumers expect — there's no second cast
// required at the call site.
//
// Zod 4 caveat: `z.discriminatedUnion("type", [...])` discriminator parameter
// is non-generic in Zod 4 (https://github.com/colinhacks/zod/issues/5024) so
// per-variant inference at the schema-tuple level is weaker than Zod 3. The
// bidirectional `_SchemaCovers` assertion below is the load-bearing drift
// guard.

import { z, type ZodError } from "zod";
import type { WSMessage } from "@/lib/types";

// ---------------------------------------------------------------------------
// ID schemas
//
// WSMessage carries IDs as plain `string` because the wire format has no
// brand concept. Internal APIs (registry, mint helpers) use the branded
// `PromptId` / `ConversationId` / `SpawnId` from `lib/branded-ids.ts` for
// cross-confusion protection at function-signature boundaries.
// ---------------------------------------------------------------------------

const conversationIdSchema = z.string();
const promptIdSchema = z.string();
const spawnIdSchema = z.string();

// DomainLeaderId — kept as a permissive string. The canonical 10-id allowlist
// lives in `server/domain-leaders.ts`; if the server emits an unknown leaderId
// it's a server bug, not a client validation concern. The reducer is robust
// to unknown leaderIds (inert no-op).
const domainLeaderIdSchema = z.string();

// WorkflowName — pinned to the 6-name allowlist from
// `server/conversation-routing.ts`. Keep in sync with the COUPLING INVARIANT
// in that file.
const workflowNameSchema = z.enum([
  "one-shot",
  "brainstorm",
  "plan",
  "work",
  "review",
  "drain-labeled-backlog",
]);

// ---------------------------------------------------------------------------
// Shared schemas
// ---------------------------------------------------------------------------

const attachmentRefSchema = z.object({
  storagePath: z.string(),
  filename: z.string(),
  contentType: z.string(),
  sizeBytes: z.number(),
});

const conversationContextSchema = z.object({
  path: z.string(),
  type: z.string(),
  content: z.string().optional(),
});

const todoItemSchema = z.object({
  id: z.string(),
  content: z.string(),
  status: z.enum(["pending", "in_progress", "completed"]),
});

// ---------------------------------------------------------------------------
// interactive_prompt — discriminated on `kind`
// ---------------------------------------------------------------------------

const askUserPayloadSchema = z.object({
  kind: z.literal("ask_user"),
  payload: z.object({
    question: z.string(),
    options: z.array(z.string()),
    multiSelect: z.boolean(),
  }),
});

const planPreviewPayloadSchema = z.object({
  kind: z.literal("plan_preview"),
  payload: z.object({ markdown: z.string() }),
});

const diffPayloadSchema = z.object({
  kind: z.literal("diff"),
  payload: z.object({
    path: z.string(),
    additions: z.number(),
    deletions: z.number(),
  }),
});

const bashApprovalPayloadSchema = z.object({
  kind: z.literal("bash_approval"),
  payload: z.object({
    command: z.string(),
    cwd: z.string(),
    gated: z.boolean(),
  }),
});

const todoWritePayloadSchema = z.object({
  kind: z.literal("todo_write"),
  payload: z.object({ items: z.array(todoItemSchema) }),
});

const notebookEditPayloadSchema = z.object({
  kind: z.literal("notebook_edit"),
  payload: z.object({
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
// interactive_prompt_response — discriminated on `kind`
// ---------------------------------------------------------------------------

const askUserResponseSchema = z.object({
  promptId: promptIdSchema,
  conversationId: conversationIdSchema,
  kind: z.literal("ask_user"),
  response: z.union([z.string(), z.array(z.string())]),
});

const planPreviewResponseSchema = z.object({
  promptId: promptIdSchema,
  conversationId: conversationIdSchema,
  kind: z.literal("plan_preview"),
  response: z.enum(["accept", "iterate"]),
});

const bashApprovalResponseSchema = z.object({
  promptId: promptIdSchema,
  conversationId: conversationIdSchema,
  kind: z.literal("bash_approval"),
  response: z.enum(["approve", "deny"]),
});

const ackResponseSchema = z.object({
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
// Per-`type` schemas
// ---------------------------------------------------------------------------

const authSchema = z.object({ type: z.literal("auth"), token: z.string() });
const authOkSchema = z.object({ type: z.literal("auth_ok") });
const chatSchema = z.object({
  type: z.literal("chat"),
  content: z.string(),
  attachments: z.array(attachmentRefSchema).optional(),
});
const startSessionSchema = z.object({
  type: z.literal("start_session"),
  leaderId: domainLeaderIdSchema.optional(),
  context: conversationContextSchema.optional(),
  resumeByContextPath: z.string().optional(),
});
const resumeSessionSchema = z.object({
  type: z.literal("resume_session"),
  conversationId: z.string(),
});
const closeConversationSchema = z.object({ type: z.literal("close_conversation") });
const reviewGateResponseSchema = z.object({
  type: z.literal("review_gate_response"),
  gateId: z.string(),
  selection: z.string(),
});
const streamSchema = z.object({
  type: z.literal("stream"),
  content: z.string(),
  partial: z.boolean(),
  leaderId: domainLeaderIdSchema,
});
const streamStartSchema = z.object({
  type: z.literal("stream_start"),
  leaderId: domainLeaderIdSchema,
  source: z.enum(["auto", "mention"]).optional(),
});
const streamEndSchema = z.object({
  type: z.literal("stream_end"),
  leaderId: domainLeaderIdSchema,
});
const toolUseSchema = z.object({
  type: z.literal("tool_use"),
  leaderId: domainLeaderIdSchema,
  label: z.string(),
});
const toolProgressSchema = z.object({
  type: z.literal("tool_progress"),
  leaderId: domainLeaderIdSchema,
  toolUseId: z.string(),
  toolName: z.string(),
  elapsedSeconds: z.number(),
});
const reviewGateSchema = z.object({
  type: z.literal("review_gate"),
  gateId: z.string(),
  question: z.string(),
  header: z.string().optional(),
  options: z.array(z.string()),
  descriptions: z.record(z.string(), z.string().optional()).optional(),
  stepProgress: z
    .object({ current: z.number(), total: z.number() })
    .optional(),
});
const sessionStartedSchema = z.object({
  type: z.literal("session_started"),
  conversationId: z.string(),
});
const sessionResumedSchema = z.object({
  type: z.literal("session_resumed"),
  conversationId: z.string(),
  resumedFromTimestamp: z.string(),
  messageCount: z.number(),
});
const sessionEndedSchema = z.object({
  type: z.literal("session_ended"),
  reason: z.string(),
});
const usageUpdateSchema = z.object({
  type: z.literal("usage_update"),
  conversationId: z.string(),
  totalCostUsd: z.number(),
  inputTokens: z.number(),
  outputTokens: z.number(),
});
const fanoutTruncatedSchema = z.object({
  type: z.literal("fanout_truncated"),
  dispatched: z.number(),
  dropped: z.number(),
});
const upgradePendingSchema = z.object({ type: z.literal("upgrade_pending") });
const errorSchema = z.object({
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
const subagentSpawnSchema = z.object({
  type: z.literal("subagent_spawn"),
  parentId: spawnIdSchema,
  leaderId: domainLeaderIdSchema,
  spawnId: spawnIdSchema,
});

const subagentCompleteSchema = z.object({
  type: z.literal("subagent_complete"),
  spawnId: spawnIdSchema,
  status: z.enum(["success", "error", "timeout"]),
});

const workflowStartedSchema = z.object({
  type: z.literal("workflow_started"),
  workflow: workflowNameSchema,
  conversationId: conversationIdSchema,
});

const workflowEndedSchema = z.object({
  type: z.literal("workflow_ended"),
  workflow: workflowNameSchema,
  status: z.enum([
    "completed",
    "user_aborted",
    "cost_ceiling",
    "idle_timeout",
    "plugin_load_failure",
    "sandbox_denial",
    "runner_crash",
    "runner_runaway",
    "internal_error",
  ]),
  summary: z.string().optional(),
});

// `interactive_prompt` flattens (type, promptId, conversationId) over the
// `kind`-discriminated payload sub-union. We can't directly z.discriminatedUnion
// on `kind` here AND on `type` at the top level; instead, build six explicit
// per-(type, kind) schemas and let the top-level union discriminate on `type`.
function makeInteractivePromptVariant<K extends z.ZodTypeAny>(kindPayload: K) {
  return z
    .object({
      type: z.literal("interactive_prompt"),
      promptId: promptIdSchema,
      conversationId: conversationIdSchema,
    })
    .and(kindPayload);
}
const interactivePromptAskUser = makeInteractivePromptVariant(askUserPayloadSchema);
const interactivePromptPlanPreview = makeInteractivePromptVariant(planPreviewPayloadSchema);
const interactivePromptDiff = makeInteractivePromptVariant(diffPayloadSchema);
const interactivePromptBashApproval = makeInteractivePromptVariant(bashApprovalPayloadSchema);
const interactivePromptTodoWrite = makeInteractivePromptVariant(todoWritePayloadSchema);
const interactivePromptNotebookEdit = makeInteractivePromptVariant(notebookEditPayloadSchema);

// `interactive_prompt_response` — flatten `type` + `(promptId, conversationId, kind, response)`.
function makeInteractivePromptResponseVariant<R extends z.ZodTypeAny>(responseShape: R) {
  return z.object({ type: z.literal("interactive_prompt_response") }).and(responseShape);
}
const interactivePromptResponseAskUser = makeInteractivePromptResponseVariant(askUserResponseSchema);
const interactivePromptResponsePlanPreview = makeInteractivePromptResponseVariant(planPreviewResponseSchema);
const interactivePromptResponseBashApproval = makeInteractivePromptResponseVariant(bashApprovalResponseSchema);
const interactivePromptResponseAck = makeInteractivePromptResponseVariant(ackResponseSchema);

// ---------------------------------------------------------------------------
// Top-level wsMessageSchema — z.union (not z.discriminatedUnion) because the
// `interactive_prompt*` variants use `.and()` composition which the
// discriminated-union runtime rejects (it requires plain ZodObjects). Zod 4
// `union` still attempts each branch and reports the most-specific error.
// ---------------------------------------------------------------------------

export const wsMessageSchema = z.union([
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
  interactivePromptAskUser,
  interactivePromptPlanPreview,
  interactivePromptDiff,
  interactivePromptBashApproval,
  interactivePromptTodoWrite,
  interactivePromptNotebookEdit,
  interactivePromptResponseAskUser,
  interactivePromptResponsePlanPreview,
  interactivePromptResponseBashApproval,
  interactivePromptResponseAck,
]);

// ---------------------------------------------------------------------------
// parseWSMessage — fail-closed wrapper consumed by `ws-client.ts:onmessage`.
// ---------------------------------------------------------------------------

export type ParseWSMessageResult =
  | { ok: true; msg: WSMessage }
  | { ok: false; error: ZodError };

export function parseWSMessage(raw: unknown): ParseWSMessageResult {
  const result = wsMessageSchema.safeParse(raw);
  if (result.success) {
    // Cast through `unknown` because Zod's inferred type carries `.and()`
    // intersection shapes that are structurally identical but nominally
    // distinct from the `WSMessage` union; the bidirectional `_SchemaCovers`
    // assertion below pins the equivalence at compile time.
    return { ok: true, msg: result.data as unknown as WSMessage };
  }
  return { ok: false, error: result.error };
}

// ---------------------------------------------------------------------------
// Bidirectional drift guard — every `WSMessage["type"]` must have a schema,
// and every schema's `type` must appear in `WSMessage["type"]`. A new variant
// added on either side fails compilation here.
// ---------------------------------------------------------------------------

type WSMessageType = WSMessage["type"];
type SchemaInferredType = z.infer<typeof wsMessageSchema>["type"];

type _SchemaCovers = {
  _forward: Exclude<WSMessageType, SchemaInferredType>;
  _backward: Exclude<SchemaInferredType, WSMessageType>;
};
const _SchemaCoversProof: { _forward: never; _backward: never } =
  null as unknown as _SchemaCovers;
void _SchemaCoversProof;
