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
  CONTEXT_RESET_REASONS,
} from "@/lib/types";

// ---------------------------------------------------------------------------
// ID schemas (min length 1 — empty IDs are server bugs, not legitimate frames)
// ---------------------------------------------------------------------------

const conversationIdSchema = z.string().min(1);
const promptIdSchema = z.string().min(1);
const spawnIdSchema = z.string().min(1);

// feat-stream-since-disconnect (#5273) — server-stamped monotonic replay
// cursor on the buffered streaming family. Optional on the wire so a rolling
// prd deploy doesn't drop frames between an old server (no `seq`) and a new
// client. Non-negative integer; the client treats it as a dedup cursor.
const replaySeqSchema = z.number().int().nonnegative().optional();

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
// feat-stream-since-disconnect (#5273) — client→server transient-reconnect
// reattach control frame. `ackSeq` is the highest `seq` the client already
// rendered (server clamps a negative/huge value; absent ⇒ replay whole tail).
// `userId` is NOT a wire field — resolved from the authenticated socket
// (strictObject rejects forgery; TR4 cross-user invariant). See ADR-059.
const resumeStreamSchema = z.strictObject({
  type: z.literal("resume_stream"),
  conversationId: conversationIdSchema,
  ackSeq: z.number().int().nonnegative().optional(),
});
// feat-stream-since-disconnect (#5273) — server→client replay-status boundary
// frame, emitted ONLY on the fallback path (cursor older than oldest buffered
// frame, or whole buffer map-evicted). Client triggers the v1 honest history
// refetch. Per-status discriminated sub-union (only `incomplete` today).
const streamReplaySchema = z.strictObject({
  type: z.literal("stream_replay"),
  conversationId: conversationIdSchema,
  status: z.literal("incomplete"),
});
const closeConversationSchema = z.strictObject({ type: z.literal("close_conversation") });
const reviewGateResponseSchema = z.strictObject({
  type: z.literal("review_gate_response"),
  gateId: z.string(),
  selection: z.string(),
});
// feat-bash-autonomous-default-on — first-run consent soft-gate response
// (client→server). Mirrors `review_gate_response`. `selection` is one of the
// disclosure actions: "Got it" (default-ON ack), "Keep autonomous on" /
// "Ask me each time" (existing-workspace opt-out). The server resolves the held
// command + writes the ack from this frame. `userId` is NOT a wire field
// (strictObject rejects forgery — TR4).
const autonomousDisclosureResponseSchema = z.strictObject({
  type: z.literal("autonomous_disclosure_response"),
  gateId: z.string(),
  selection: z.string(),
});
// `abort_turn` (feat-abort-conversation-web PR1, plan §1.2): user-initiated
// Stop. `userId` is intentionally NOT a wire field — strictObject + the
// minimum-length conversationId reject forged userIds and empty IDs at the
// boundary. See plan §"User-Brand Impact" / TR4 cross-user invariant.
const abortTurnSchema = z.strictObject({
  type: z.literal("abort_turn"),
  conversationId: conversationIdSchema,
});
const streamSchema = z.strictObject({
  type: z.literal("stream"),
  content: z.string(),
  partial: z.boolean(),
  leaderId: domainLeaderIdSchema,
  seq: replaySeqSchema,
});
const streamStartSchema = z.strictObject({
  type: z.literal("stream_start"),
  leaderId: domainLeaderIdSchema,
  source: z.enum(["auto", "mention"]).optional(),
  seq: replaySeqSchema,
});
const streamEndSchema = z.strictObject({
  type: z.literal("stream_end"),
  leaderId: domainLeaderIdSchema,
  seq: replaySeqSchema,
});
const toolUseSchema = z.strictObject({
  type: z.literal("tool_use"),
  leaderId: domainLeaderIdSchema,
  label: z.string(),
  seq: replaySeqSchema,
});
// feat-concierge-stream-commands — inline Bash command/output stream.
// `command`/`output` are optional (set per `phase`); both are already
// redacted at the emit boundary. `truncated` flags an output chunk that
// hit the per-command cap (D4).
const commandStreamSchema = z.strictObject({
  type: z.literal("command_stream"),
  leaderId: domainLeaderIdSchema,
  // FIX 4 — wire-length caps. `command` is pre-capped to 16384 bytes at the
  // emit boundary (mirrors the output path); `output` is byte-capped to
  // COMMAND_STREAM_TOTAL_CAP_BYTES (16384) — the char `.max()` sits slightly
  // above to admit the truncation marker + any redaction-marker expansion.
  command: z.string().max(16384).optional(),
  output: z.string().max(20000).optional(),
  phase: z.enum(["start", "output", "end"]),
  truncated: z.boolean().optional(),
  // FIX 2 — SDK tool_use id for concurrent-Bash output correlation. Optional
  // for back-compat with emitters/replayed frames that predate it.
  toolUseId: z.string().optional(),
});
const toolProgressSchema = z.strictObject({
  type: z.literal("tool_progress"),
  leaderId: domainLeaderIdSchema,
  toolUseId: z.string(),
  toolName: z.string(),
  elapsedSeconds: z.number(),
  seq: replaySeqSchema,
});
// feat-debug-mode-stream — internal dev-cohort harness instruction stream.
// Delta/append semantics: one event per frame (turn end is signalled by
// stream_end/session_ended). `body` is already redacted-or-dropped at the
// server emit boundary; `label` (optional) is the human tool label, never the
// raw SDK tool name. `body` is byte-capped at the emit site
// (COMMAND_STREAM_TOTAL_CAP_BYTES = 16384); the char `.max()` sits slightly
// above to admit redaction-marker expansion + the truncation marker.
const debugEventSchema = z.strictObject({
  type: z.literal("debug_event"),
  kind: z.enum(["tool_use", "reasoning", "result"]),
  label: z.string().optional(),
  body: z.string().max(20000),
});
// feat-reasoning-chat-boxes (#5370) — agent-emitted user-facing narration.
// `reasoning_narration` is the transient live status line (live-only, no seq,
// excluded from the replay buffer). `turn_summary` is the durable per-turn
// record (persisted + buffered, carries seq). Both text fields are redacted at
// the server emit boundary; the max() admits redaction-marker expansion.
const reasoningNarrationSchema = z.strictObject({
  type: z.literal("reasoning_narration"),
  message: z.string().max(20000),
});
const turnSummarySchema = z.strictObject({
  type: z.literal("turn_summary"),
  summary: z.string().max(20000),
  seq: replaySeqSchema,
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
// feat-bash-autonomous-default-on — first-run consent soft-gate disclosure
// (server→client). Mirrors `review_gate`: a held Bash command awaiting the
// owner's one-time acknowledgement. `existingWorkspace` true => the workspace
// is stored `false`/un-acked (offer the opt-out "Keep autonomous on" /
// "Ask me each time"); false => default-ON workspace (single "Got it" ack).
const autonomousDisclosureSchema = z.strictObject({
  type: z.literal("autonomous_disclosure"),
  gateId: z.string(),
  existingWorkspace: z.boolean(),
});
// feat-bash-autonomous-default-on — SERVER-resolved autonomous posture for the
// persistent chip (server→client). `autonomous` is the server truth
// `bashAutonomous && ackAt != null`. The chip reads THIS, never message
// presence — a held (un-acked) disclosure is "Approve each", not "Auto-run on".
const autonomousPostureSchema = z.strictObject({
  type: z.literal("autonomous_posture"),
  autonomous: z.boolean(),
});
const sessionStartedSchema = z.strictObject({
  type: z.literal("session_started"),
  conversationId: z.string(),
  // Stage 3 (#2885) — optional capability manifest. When present, lists the
  // `interactive_prompt.kind` values this server build can emit. Absent =
  // legacy server, treat as the default 6-kind set. Lets external agents
  // skip a feature-detection round-trip.
  //
  // #3464 — `incomingTypes` advertises the curated client→server message
  // types this server build accepts as stable agent primitives (today:
  // `["abort_turn"]`). Required-for-protocol and feature-internal
  // variants are intentionally not advertised. Source of truth:
  // `apps/web-platform/lib/ws-capabilities.ts`.
  capabilities: z
    .strictObject({
      promptKinds: z.array(z.string()).readonly(),
      incomingTypes: z.array(z.string()).readonly().optional(),
    })
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
  // Optional disambiguator for multi-tab clients (feat-abort-conversation-web
  // PR1). Existing emitters that omit it remain wire-compatible.
  conversationId: z.string().optional(),
  seq: replaySeqSchema,
});
const usageUpdateSchema = z.strictObject({
  type: z.literal("usage_update"),
  conversationId: z.string(),
  // Phase 3 (feat-team-workspace-multi-user) — workspace_id for client-side
  // workspace-grain attribution. Optional for one release cycle so a
  // rolling prd deploy doesn't drop frames between an old server (without
  // the field) and a new client. Tighten in a follow-up.
  workspaceId: z.string().optional(),
  totalCostUsd: z.number(),
  inputTokens: z.number(),
  outputTokens: z.number(),
  // Cache tokens — widened 2026-05-12 to close the dashboard
  // cross-check gap vs the Anthropic Console for cached prompts.
  // `0` when prompt caching is not engaged. `.optional()` for one
  // release cycle so a rolling prd deploy doesn't drop frames between
  // an old server (emitting the legacy 3-field shape) and a new client.
  // Tighten to required in a follow-up after the old build ages out.
  cacheReadInputTokens: z.number().optional(),
  cacheCreationInputTokens: z.number().optional(),
  seq: replaySeqSchema,
});
const fanoutTruncatedSchema = z.strictObject({
  type: z.literal("fanout_truncated"),
  dispatched: z.number(),
  dropped: z.number(),
});
// #3269 — context-reset lifecycle notice (prefill-guard fire / tool_use orphan).
// Mirrors the `fanoutTruncatedSchema` shape (z.strictObject with a literal
// type discriminator) so the WS lifecycle-notice family stays homogeneous
// per ADR-025. `reason` derives from `CONTEXT_RESET_REASONS` so the Zod
// schema, helper return shape, reducer variant, and render-side copy map
// all share a single source of truth.
const contextResetSchema = z.strictObject({
  type: z.literal("context_reset"),
  reason: z.enum(CONTEXT_RESET_REASONS),
  conversationId: z.string(),
});
const upgradePendingSchema = z.strictObject({ type: z.literal("upgrade_pending") });
// #3930 — cross-process JWT-deny discriminator. See lib/types.ts WSMessage
// revocation_notice variant for the full prose. `reason` and `deniedAt` are
// nullable because the underlying `my_revocation_status()` RPC returns NULL
// columns when the deny row pre-dates the schema columns (legacy paths).
const revocationNoticeSchema = z.strictObject({
  type: z.literal("revocation_notice"),
  reason: z.string().nullable(),
  deniedAt: z.string().nullable(),
});
const errorSchema = z.strictObject({
  type: z.literal("error"),
  message: z.string(),
  errorCode: z
    .enum([
      "key_invalid",
      // Phase 3.2 AC-D (#4229) — fail-closed when keyOwnerUserId has no
      // api_keys row. Distinct from key_invalid (which means key exists
      // but is unusable).
      "byok_key_missing",
      // feat-operator-cc-oauth FR5 — subscription credit/rate-limit
      // exhaustion on an oauth_token run; non-retryable, distinct from
      // key_invalid and the per-account rate_limited throttle.
      "subscription_limit",
      "session_expired",
      "session_resumed",
      "rate_limited",
      "idle_timeout",
      "upload_failed",
      "file_too_large",
      "unsupported_file_type",
      "too_many_files",
      "interactive_prompt_rejected",
      "image_paste_lost",
      // #5394 — Concierge dispatch blocked because the active workspace repo
      // setup errored (repo_status === "error"). Client renders the reconnect
      // CTA. The cloning block carries no errorCode.
      "repo_setup_failed",
      "delegation_revoked_post_grace",
      "delegation_expired",
      "delegation_hourly_cap_exceeded",
      "delegation_daily_cap_exceeded",
      "delegation_cross_tenant",
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
  resumeStreamSchema,
  streamReplaySchema,
  closeConversationSchema,
  reviewGateResponseSchema,
  autonomousDisclosureResponseSchema,
  abortTurnSchema,
  streamSchema,
  streamStartSchema,
  streamEndSchema,
  toolUseSchema,
  commandStreamSchema,
  toolProgressSchema,
  debugEventSchema,
  reasoningNarrationSchema,
  turnSummarySchema,
  reviewGateSchema,
  autonomousDisclosureSchema,
  autonomousPostureSchema,
  sessionStartedSchema,
  sessionResumedSchema,
  sessionEndedSchema,
  usageUpdateSchema,
  fanoutTruncatedSchema,
  contextResetSchema,
  upgradePendingSchema,
  errorSchema,
  revocationNoticeSchema,
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
