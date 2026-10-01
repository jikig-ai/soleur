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

function safeSourceId(value: unknown): string | null {
  const candidate = nonEmptyString(value);
  if (!candidate || candidate.length > 128) return null;
  if ([...candidate].some((character) => {
    const code = character.charCodeAt(0);
    return code < 32 || code === 127 || code === 0x2028 || code === 0x2029;
  })) return null;
  return candidate;
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

const CLAUDE_ASSISTANT_ERROR_CODES = new Set([
  "authentication_failed",
  "oauth_org_not_allowed",
  "billing_error",
  "rate_limit",
  "overloaded",
  "invalid_request",
  "model_not_found",
  "server_error",
  "unknown",
  "max_output_tokens",
]);
const CLAUDE_RETRYABLE_ERRORS = new Set(["rate_limit", "overloaded", "server_error"]);

function translateAssistant(message: RecordLike, sourceId: string): ClaudeTranslatedEvent[] {
  const events: ClaudeTranslatedEvent[] = [];
  const providerError = nonEmptyString(message.error);
  if (providerError) {
    const code = CLAUDE_ASSISTANT_ERROR_CODES.has(providerError)
      ? providerError
      : "claude_provider_error";
    events.push({
      sourceId: `${sourceId}:error`,
      payload: { type: "error", code, retryable: CLAUDE_RETRYABLE_ERRORS.has(providerError) },
    });
  }
  const envelope = asRecord(message.message);
  const content = envelope?.content;
  if (!Array.isArray(content)) return events;

  events.push(...content.flatMap((candidate, index) => {
    const block = asRecord(candidate);
    if (block?.type !== "text") return [];
    const text = nonEmptyString(block.text);
    return text === null
      ? []
      : [{ sourceId: `${sourceId}:text:${index}`, payload: { type: "text", text } as const }];
  }));
  return events;
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
  const sourceId = safeSourceId(record?.uuid);
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
  if (!safeSourceId(runId)) throw new Error("claude_run_id_invalid");
  let sequence = 0;
  for await (const message of messages) {
    const record = asRecord(message);
    const type = nonEmptyString(record?.type);
    if (
      (type === "assistant" || type === "tool_progress" || type === "result")
      && !safeSourceId(record?.uuid)
    ) {
      throw new Error("claude_message_invalid");
    }
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
