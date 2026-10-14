import type { EngineEvent, EngineEventPayload } from "./agent-engine-contract";

export interface CodexTranslatedEvent {
  sourceId: string;
  payload: EngineEventPayload;
}

export interface CodexReplayEvent extends CodexTranslatedEvent {
  kind: "codex-replay";
}

type RecordLike = Record<string, unknown>;

function asRecord(value: unknown): RecordLike | null {
  return value !== null && typeof value === "object" ? value as RecordLike : null;
}

function safeProviderId(value: unknown): string | null {
  if (typeof value !== "string" || value.length < 1 || value.length > 96) return null;
  if ([...value].some((character) => {
    const codePoint = character.codePointAt(0)!;
    return codePoint <= 0x1f || codePoint === 0x7f || codePoint === 0x2028 || codePoint === 0x2029;
  })) return null;
  return value;
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function statusType(value: unknown): string | null {
  if (typeof value === "string") return value;
  const record = asRecord(value);
  return typeof record?.type === "string" ? record.type : null;
}

function boundedDescription(value: unknown): string {
  const description = nonEmptyString(value);
  if (!description) return "Codex requested command approval";
  return description.length > 4096 ? description.slice(0, 4096) : description;
}

function finiteNonNegative(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null;
}

function usagePayload(params: RecordLike): EngineEventPayload | null {
  const usage = asRecord(params.usage);
  if (!usage) return null;
  const native: { unit: string; value: number }[] = [];
  const inputTokens = finiteNonNegative(usage.inputTokens);
  const outputTokens = finiteNonNegative(usage.outputTokens);
  if (inputTokens !== null) native.push({ unit: "input_tokens", value: inputTokens });
  if (outputTokens !== null) native.push({ unit: "output_tokens", value: outputTokens });
  const amount = finiteNonNegative(usage.totalCostUsd);
  return {
    type: "usage",
    usage: {
      native,
      cost: amount === null
        ? { provenance: "unavailable" }
        : { provenance: "reported", amount, currency: "USD" },
    },
  };
}

function tokenUsageSnapshot(params: RecordLike): EngineEventPayload | null {
  const tokenUsage = asRecord(params.tokenUsage);
  const last = asRecord(tokenUsage?.last);
  const inputTokens = finiteNonNegative(last?.inputTokens);
  const outputTokens = finiteNonNegative(last?.outputTokens);
  if (inputTokens === null || outputTokens === null) return null;
  return {
    type: "usage",
    usage: {
      native: [{ unit: "input_tokens", value: inputTokens }, { unit: "output_tokens", value: outputTokens }],
      cost: { provenance: "unavailable" },
    },
  };
}

function turnIdentity(params: RecordLike): string | null {
  const turn = asRecord(params.turn);
  return safeProviderId(turn ? turn.id : params.turnId);
}

const RECOGNIZED_METHODS = new Set([
  "item/agentMessage/delta",
  "item/commandExecution/requestApproval",
  "turn/started",
  "turn/completed",
  "thread/tokenUsage/updated",
]);

function turnStatus(value: unknown): Extract<EngineEventPayload, { type: "status" }> ["status"] | null {
  switch (value) {
    case "started":
    case "in_progress":
    case "inProgress":
      return "running";
    case "completed":
      return "completed";
    case "failed":
    case "error":
      return "failed";
    case "cancelled":
    case "canceled":
    case "interrupted":
      return "cancelled";
    default:
      return null;
  }
}

export function createCodexReplayEvent(event: CodexTranslatedEvent): CodexReplayEvent {
  return { kind: "codex-replay", sourceId: event.sourceId, payload: event.payload };
}

function safeReplaySourceId(value: unknown): string | null {
  if (typeof value !== "string" || value.length < 1 || value.length > 128) return null;
  return [...value].some((character) => {
    const codePoint = character.codePointAt(0)!;
    return codePoint <= 0x1f || codePoint === 0x7f || codePoint === 0x2028 || codePoint === 0x2029;
  }) ? null : value;
}

function replayPayload(value: unknown): EngineEventPayload | null {
  const record = asRecord(value);
  if (!record) return null;
  switch (record.type) {
    case "text":
    case "progress":
    case "approval":
    case "artifact":
    case "usage":
    case "error":
    case "status":
      return value as EngineEventPayload;
    default:
      return null;
  }
}

/** Translate the stable App Server event subset without leaking protocol objects. */
export function translateCodexAppServerEvent(event: unknown): CodexTranslatedEvent[] {
  const record = asRecord(event);
  const method = nonEmptyString(record?.method);
  const params = asRecord(record?.params);
  if (!method || !params) return [];

  if (method === "item/agentMessage/delta") {
    const itemId = safeProviderId(params.itemId);
    const delta = nonEmptyString(params.delta);
    return itemId && delta
      ? [{ sourceId: `item:${itemId}:delta`, payload: { type: "text", text: delta } }]
      : [];
  }

  if (method === "item/commandExecution/requestApproval") {
    const itemId = safeProviderId(params.itemId);
    return itemId
      ? [{
        sourceId: `approval:${itemId}`,
        payload: {
          type: "approval",
          requestId: itemId,
          tool: "command",
          description: boundedDescription(params.reason),
        },
      }]
      : [];
  }

  if (method === "turn/started" || method === "turn/completed") {
    const turnId = turnIdentity(params);
    const turn = asRecord(params.turn);
    const status = turnStatus(method === "turn/started" ? "started" : (turn ? turn.status : params.status));
    if (!turnId || !status) return [];
    const events: CodexTranslatedEvent[] = [];
    if (method === "turn/completed") {
      const usage = usagePayload(params);
      if (usage) events.push({ sourceId: `turn:${turnId}:usage`, payload: usage });
    }
    events.push({ sourceId: `turn:${turnId}:status`, payload: { type: "status", status } });
    return events;
  }

  return [];
}

const APPROVAL_STATUSES = new Set(["awaitingApproval", "approvalRequired", "needsApproval", "waiting"]);

/** Translate the persisted item subset that can be represented safely in the neutral contract. */
export function translateCodexPersistedItem(item: unknown): CodexTranslatedEvent[] {
  const record = asRecord(item);
  const type = nonEmptyString(record?.type);
  const itemId = safeProviderId(record?.id);
  if (!type || !itemId) return [];

  if (type === "agentMessage") {
    const text = nonEmptyString(record?.text);
    return text
      ? [{ sourceId: `item:${itemId}:message`, payload: { type: "text", text } }]
      : [];
  }

  if (type === "plan") {
    const text = nonEmptyString(record?.text);
    return text
      ? [{ sourceId: `plan:${itemId}`, payload: { type: "progress", message: boundedDescription(text) } }]
      : [];
  }

  if (type === "fileChange") {
    const changes = record?.changes;
    return Array.isArray(changes) && changes.length <= 1000
      ? [{ sourceId: `file-change:${itemId}`, payload: { type: "progress", message: `File changes recorded (${changes.length})` } }]
      : [];
  }

  if (type === "enteredReviewMode" || type === "exitedReviewMode") {
    return [{
      sourceId: `review:${itemId}:${type === "enteredReviewMode" ? "started" : "completed"}`,
      payload: { type: "progress", message: type === "enteredReviewMode" ? "Review started" : "Review completed" },
    }];
  }

  if (type === "contextCompaction") {
    return [{
      sourceId: `compaction:${itemId}`,
      payload: { type: "progress", message: "Context compacted" },
    }];
  }

  if (type === "webSearch") {
    return [{
      sourceId: `web-search:${itemId}`,
      payload: { type: "progress", message: "Web search recorded" },
    }];
  }

  if (type === "imageView") {
    return [{
      sourceId: `image-view:${itemId}`,
      payload: { type: "progress", message: "Image view recorded" },
    }];
  }

  if (type === "functionCallOutput") {
    return [{
      sourceId: `function-output:${itemId}`,
      payload: { type: "progress", message: "Function output recorded" },
    }];
  }

  if (type === "userMessage") {
    return [{
      sourceId: `user-message:${itemId}`,
      payload: { type: "progress", message: "User input recorded" },
    }];
  }

  if (type === "mcpToolCall" && (statusType(record?.status) === "completed" || statusType(record?.status) === "failed")) {
    return [{
      sourceId: `mcp:${itemId}:status`,
      payload: {
        type: "progress",
        message: statusType(record?.status) === "completed" ? "MCP tool completed" : "MCP tool failed",
      },
    }];
  }

  if (type === "dynamicToolCall" && (statusType(record?.status) === "completed" || statusType(record?.status) === "failed")) {
    return [{
      sourceId: `dynamic:${itemId}:status`,
      payload: {
        type: "progress",
        message: statusType(record?.status) === "completed" ? "Dynamic tool completed" : "Dynamic tool failed",
      },
    }];
  }

  if (type === "collabToolCall" && (statusType(record?.status) === "completed" || statusType(record?.status) === "failed")) {
    return [{
      sourceId: `collab:${itemId}:status`,
      payload: {
        type: "progress",
        message: statusType(record?.status) === "completed" ? "Collaboration tool completed" : "Collaboration tool failed",
      },
    }];
  }

  if (type === "commandExecution" && (statusType(record?.status) === "completed" || statusType(record?.status) === "failed")) {
    return [{
      sourceId: `command:${itemId}:status`,
      payload: {
        type: "progress",
        message: statusType(record?.status) === "completed" ? "Command completed" : "Command failed",
      },
    }];
  }

  if (type === "commandExecution" && APPROVAL_STATUSES.has(statusType(record?.status) ?? "")) {
    const command = nonEmptyString(record?.command);
    return command
      ? [{
        sourceId: `approval:${itemId}`,
        payload: {
          type: "approval",
          requestId: itemId,
          tool: "command",
          description: boundedDescription(command),
        },
      }]
      : [];
  }

  return [];
}

/** Translate a persisted turn summary without exposing its native envelope. */
export function translateCodexPersistedTurn(turn: unknown): CodexTranslatedEvent[] {
  const record = asRecord(turn);
  if (!record) return [];
  const turnId = safeProviderId(record?.id);
  const status = turnStatus(statusType(record?.status));
  if (!turnId || !status) return [];
  const events: CodexTranslatedEvent[] = [];
  const usage = usagePayload(record);
  if (usage) events.push({ sourceId: `turn:${turnId}:usage`, payload: usage });
  events.push({ sourceId: `turn:${turnId}:status`, payload: { type: "status", status } });
  return events;
}

function hasSafeIdentity(method: string, params: RecordLike | null): boolean {
  if (!params) return false;
  if (method === "item/agentMessage/delta" || method === "item/commandExecution/requestApproval") {
    return safeProviderId(params.itemId) !== null;
  }
  if (method === "turn/started" || method === "turn/completed") {
    return turnIdentity(params) !== null;
  }
  if (method === "thread/tokenUsage/updated") {
    return safeProviderId(params.threadId) !== null && safeProviderId(params.turnId) !== null;
  }
  return true;
}

/** Wrap translated App Server events with the bound run and contiguous sequence. */
export async function* translateCodexAppServerStream(
  events: AsyncIterable<unknown>,
  runId: string,
): AsyncIterable<EngineEvent> {
  if (!safeProviderId(runId)) throw new Error("codex_run_id_invalid");
  let sequence = 0;
  const pendingUsage = new Map<string, EngineEventPayload>();
  for await (const event of events) {
    const record = asRecord(event);
    if (record?.kind === "codex-replay") {
      const sourceId = safeReplaySourceId(record.sourceId);
      const payload = replayPayload(record.payload);
      if (!sourceId || !payload) throw new Error("codex_replay_invalid");
      sequence += 1;
      yield { runId, eventId: `codex:${sourceId}`, sequence, payload };
      continue;
    }
    const method = nonEmptyString(record?.method);
    if (method && RECOGNIZED_METHODS.has(method) && !hasSafeIdentity(method, asRecord(record?.params))) {
      throw new Error("codex_message_invalid");
    }
    const params = asRecord(record?.params);
    if (method === "thread/tokenUsage/updated" && params) {
      const usage = tokenUsageSnapshot(params);
      if (!usage) throw new Error("codex_usage_invalid");
      pendingUsage.set(params.turnId as string, usage);
      continue;
    }
    const completedTurnId = method === "turn/completed" && params ? turnIdentity(params) : null;
    const finalUsage = completedTurnId ? pendingUsage.get(completedTurnId) : null;
    if (completedTurnId && finalUsage) {
      pendingUsage.delete(completedTurnId);
      sequence += 1;
      yield { runId, eventId: `codex:turn:${completedTurnId}:usage:${sequence}`, sequence, payload: finalUsage };
    }
    for (const translated of translateCodexAppServerEvent(event)) {
      if (finalUsage && translated.payload.type === "usage") continue;
      sequence += 1;
      yield {
        runId,
        eventId: `codex:${translated.sourceId}:${sequence}`,
        sequence,
        payload: translated.payload,
      };
    }
  }
}
