import type { EngineEvent, EngineEventPayload } from "./agent-engine-contract";

export interface ClaudeTranslatedEvent {
  /** Provider message/block identity used for idempotent event construction. */
  sourceId: string;
  payload: EngineEventPayload;
}

type RecordLike = Record<string, unknown>;

function asRecord(value: unknown): RecordLike | null {
  return value !== null && typeof value === "object" ? value as RecordLike : null;
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function finiteNonNegative(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null;
}

function usagePayload(message: RecordLike): EngineEventPayload | null {
  const usage = asRecord(message.usage);
  if (!usage) return null;

  const native: { unit: string; value: number }[] = [];
  for (const unit of [
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
  ]) {
    const value = finiteNonNegative(usage[unit]);
    if (value !== null) native.push({ unit, value });
  }

  const amount = finiteNonNegative(message.total_cost_usd);
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

function translateAssistant(message: RecordLike, sourceId: string): ClaudeTranslatedEvent[] {
  const envelope = asRecord(message.message);
  const content = envelope?.content;
  if (!Array.isArray(content)) return [];

  return content.flatMap((candidate, index) => {
    const block = asRecord(candidate);
    if (block?.type !== "text") return [];
    const text = nonEmptyString(block.text);
    return text === null
      ? []
      : [{ sourceId: `${sourceId}:text:${index}`, payload: { type: "text", text } as const }];
  });
}

function translateToolProgress(message: RecordLike, sourceId: string): ClaudeTranslatedEvent[] {
  const toolName = nonEmptyString(message.tool_name);
  const toolUseId = nonEmptyString(message.tool_use_id);
  const elapsed = finiteNonNegative(message.elapsed_time_seconds);
  if (!toolName || !toolUseId || elapsed === null) return [];
  return [{
    sourceId: `${sourceId}:progress`,
    payload: { type: "progress", message: `${toolName} (${elapsed}s)` },
  }];
}

function translateResult(message: RecordLike, sourceId: string): ClaudeTranslatedEvent[] {
  const subtype = nonEmptyString(message.subtype);
  if (!subtype) return [];

  const events: ClaudeTranslatedEvent[] = [];
  const usage = usagePayload(message);
  if (usage) events.push({ sourceId: `${sourceId}:usage`, payload: usage });

  const successful = subtype === "success" && message.is_error !== true;
  if (!successful) {
    // Keep the provider subtype as a bounded code; never expose SDK `errors`.
    const code = /^[a-z0-9_-]{1,64}$/i.test(subtype) ? subtype : "claude_provider_error";
    events.push({
      sourceId: `${sourceId}:error`,
      payload: { type: "error", code, retryable: false },
    });
  }
  events.push({
    sourceId: `${sourceId}:status`,
    payload: { type: "status", status: successful ? "completed" : "failed" },
  });
  return events;
}

/**
 * Translate the stable subset of Claude Agent SDK messages into the neutral
 * event payloads. Permission/tool/session callbacks stay in the transport
 * until the runner extraction can preserve their existing lifecycle hooks.
 */
export function translateClaudeSdkMessage(message: unknown): ClaudeTranslatedEvent[] {
  const record = asRecord(message);
  const sourceId = nonEmptyString(record?.uuid);
  const type = nonEmptyString(record?.type);
  if (!record || !sourceId || !type) return [];

  if (type === "assistant") return translateAssistant(record, sourceId);
  if (type === "tool_progress") return translateToolProgress(record, sourceId);
  if (type === "result") return translateResult(record, sourceId);
  return [];
}

/** Wrap translated payloads with the run identity and contiguous sequence. */
export async function* translateClaudeSdkStream(
  messages: AsyncIterable<unknown>,
  runId: string,
): AsyncIterable<EngineEvent> {
  let sequence = 0;
  for await (const message of messages) {
    for (const translated of translateClaudeSdkMessage(message)) {
      sequence += 1;
      yield {
        runId,
        eventId: `claude:${translated.sourceId}`,
        sequence,
        payload: translated.payload,
      };
    }
  }
}
