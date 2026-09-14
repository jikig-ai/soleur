import type { EngineEvent, EngineEventPayload } from "./agent-engine-contract";

export interface CodexTranslatedEvent {
  sourceId: string;
  payload: EngineEventPayload;
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

const RECOGNIZED_METHODS = new Set([
  "item/agentMessage/delta",
  "item/commandExecution/requestApproval",
  "turn/started",
  "turn/completed",
]);

function turnStatus(value: unknown): Extract<EngineEventPayload, { type: "status" }> ["status"] | null {
  switch (value) {
    case "started":
    case "in_progress":
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
    const turnId = safeProviderId(params.turnId);
    const status = turnStatus(method === "turn/started" ? "started" : params.status);
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

function hasSafeIdentity(method: string, params: RecordLike | null): boolean {
  if (!params) return false;
  if (method === "item/agentMessage/delta" || method === "item/commandExecution/requestApproval") {
    return safeProviderId(params.itemId) !== null;
  }
  if (method === "turn/started" || method === "turn/completed") {
    return safeProviderId(params.turnId) !== null;
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
  for await (const event of events) {
    const record = asRecord(event);
    const method = nonEmptyString(record?.method);
    if (method && RECOGNIZED_METHODS.has(method) && !hasSafeIdentity(method, asRecord(record?.params))) {
      throw new Error("codex_message_invalid");
    }
    for (const translated of translateCodexAppServerEvent(event)) {
      sequence += 1;
      yield {
        runId,
        eventId: `codex:${translated.sourceId}`,
        sequence,
        payload: translated.payload,
      };
    }
  }
}
