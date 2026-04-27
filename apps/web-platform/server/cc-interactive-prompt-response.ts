// `interactive_prompt_response` handler (Stage 3 — #2885).
//
// Pure decision function behind the ws-handler case. Responsibilities:
//   (a) Validate payload shape + per-kind response literal (no Zod
//       dependency; a hand-written predicate keeps the hot path allocation-
//       free and the error taxonomy narrow).
//   (b) Ownership check: `registry.consume(key, userId)` returns undefined
//       for cross-user lookups; we treat that as `not_found` (silent denial
//       per pending-prompt-registry.ts invariant (b)).
//   (c) Cross-conversation rejection: payload.conversationId MUST match the
//       record's conversationId. Caught before consume so a later correct
//       reply still lands.
//   (d) Kind-mismatch rejection: payload.kind MUST match the record's kind,
//       also caught before consume.
//   (e) Idempotency: `consume()` removes the record; a replay returns
//       `already_consumed`.
//   (f) Delivery: on success, invokes `deliverToolResult({ conversationId,
//       toolUseId, content })` so the ws-handler layer can push a tool_result
//       SDKUserMessage back into the runner's streaming-input queue.
//
// The function emits NO side effects besides the registry consume and the
// delivery callback. The ws-handler is responsible for mapping results to
// WS error codes (per `cq-silent-fallback-must-mirror-to-sentry`, the
// ws-handler must NOT silently drop on `not_found` — it mirrors to Sentry
// and replies with a structured error).

import {
  PendingPromptRegistry,
  makePendingPromptKey,
  type InteractivePromptKind,
  type PendingPromptRecord,
} from "./pending-prompt-registry";
import type { WSMessage } from "@/lib/types";
type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>;

export type HandleInteractivePromptResponseResult =
  | { ok: true }
  | {
      ok: false;
      error:
        | "invalid_payload"
        | "invalid_response"
        | "not_found"
        | "kind_mismatch"
        | "already_consumed";
    };

export interface HandleInteractivePromptResponseArgs {
  registry: PendingPromptRegistry;
  userId: string;
  payload: InteractivePromptResponse;
  deliverToolResult: (args: {
    conversationId: string;
    toolUseId: string;
    content: string;
  }) => void;
}

// Consumed-prompt tombstones — bounded per-user to distinguish "never
// existed" (not_found) from "already responded" (already_consumed). A
// plain Set would grow unbounded; we key by composite key.
//
// Reaping: `cc-dispatcher.ts` schedules a periodic interval that calls
// `registry.reap()` and `pruneTombstonesFor(registry)` at the same
// cadence. A tombstone whose source key has been reaped can't collide
// with any live prompt, so wholesale clearing on each reap pass is
// safe. The WeakMap key is the registry instance — each registry gets
// its own tombstone set, GC'd when the registry is (test isolation via
// `__resetDispatcherForTests`).
const tombstoneStore = new WeakMap<PendingPromptRegistry, Set<string>>();

function tombstonesFor(registry: PendingPromptRegistry): Set<string> {
  let set = tombstoneStore.get(registry);
  if (!set) {
    set = new Set<string>();
    tombstoneStore.set(registry, set);
  }
  return set;
}

/**
 * Clear the tombstone set for a registry. Called from the scheduled
 * reaper in `cc-dispatcher.ts` immediately after `registry.reap()` so
 * tombstone memory does not outlive the records they shadow. Also
 * exported for test cleanup.
 */
export function pruneTombstonesFor(registry: PendingPromptRegistry): number {
  const set = tombstoneStore.get(registry);
  if (!set) return 0;
  const removed = set.size;
  set.clear();
  return removed;
}

// Derive the runtime kind guard from the canonical registry union so
// adding a 7th kind to `InteractivePromptKind` automatically widens the
// guard (pattern-recognition HIGH: 4-way drift). `satisfies` verifies
// every kind has a `true` entry; the `as` cast narrows the
// `keyof typeof KIND_MAP` intersection back to `InteractivePromptKind`.
const KIND_MAP = {
  ask_user: true,
  plan_preview: true,
  diff: true,
  bash_approval: true,
  todo_write: true,
  notebook_edit: true,
} as const satisfies Record<InteractivePromptKind, true>;
const KIND_SET: ReadonlySet<InteractivePromptKind> = new Set(
  Object.keys(KIND_MAP) as InteractivePromptKind[],
);

function isValidPayload(payload: unknown): payload is InteractivePromptResponse {
  if (!payload || typeof payload !== "object") return false;
  const p = payload as Record<string, unknown>;
  if (p.type !== "interactive_prompt_response") return false;
  if (typeof p.promptId !== "string" || p.promptId.length === 0) return false;
  if (typeof p.conversationId !== "string" || p.conversationId.length === 0) return false;
  if (typeof p.kind !== "string") return false;
  if (!KIND_SET.has(p.kind as InteractivePromptKind)) return false;
  return true;
}

// Matches `prompt-injection-wrap.ts` MAX_USER_INPUT_BYTES — any free-form
// user-supplied `ask_user` response loops back into the SDK as tool_result
// content and must be bounded so a legitimate response cannot be weaponized
// as a token-cost amplifier against the same-user cost cap.
const MAX_ASK_USER_RESPONSE_BYTES = 8192;

function normalizeResponse(
  kind: InteractivePromptKind,
  response: unknown,
): { ok: true; content: string } | { ok: false } {
  switch (kind) {
    case "ask_user": {
      if (typeof response === "string") {
        return { ok: true, content: response.slice(0, MAX_ASK_USER_RESPONSE_BYTES) };
      }
      if (
        Array.isArray(response) &&
        response.every((r) => typeof r === "string")
      ) {
        return {
          ok: true,
          content: (response as string[]).join(", ").slice(0, MAX_ASK_USER_RESPONSE_BYTES),
        };
      }
      return { ok: false };
    }
    case "plan_preview":
      return response === "accept" || response === "iterate"
        ? { ok: true, content: response }
        : { ok: false };
    case "bash_approval":
      return response === "approve" || response === "deny"
        ? { ok: true, content: response }
        : { ok: false };
    case "diff":
    case "todo_write":
    case "notebook_edit":
      return response === "ack" ? { ok: true, content: "ack" } : { ok: false };
    default: {
      const _exhaustive: never = kind;
      void _exhaustive;
      return { ok: false };
    }
  }
}

export function handleInteractivePromptResponse(
  args: HandleInteractivePromptResponseArgs,
): HandleInteractivePromptResponseResult {
  const { registry, userId, payload, deliverToolResult } = args;

  if (!isValidPayload(payload)) {
    return { ok: false, error: "invalid_payload" };
  }

  const key = makePendingPromptKey(userId, payload.conversationId, payload.promptId);

  // Peek first (no consume) so cross-conversation / kind-mismatch do NOT
  // destroy the record — a correct retry must still work.
  const record: PendingPromptRecord | undefined = registry.get(key, userId);
  if (!record) {
    // Distinguish replay from truly-missing. Tombstones are per-registry
    // and bounded by the WeakMap; a reaped record leaves a tombstone
    // that the next replay reads. See module header.
    if (tombstonesFor(registry).has(key)) {
      return { ok: false, error: "already_consumed" };
    }
    return { ok: false, error: "not_found" };
  }

  // No explicit conversation_mismatch branch: the composite key already
  // embeds conversationId, so a cross-conversation probe with a crafted
  // payload never reaches this point (registry.get returns undefined —
  // reported above as not_found). This is the registry's silent-denial
  // invariant; see pending-prompt-registry.ts §(b).
  if (record.kind !== payload.kind) {
    return { ok: false, error: "kind_mismatch" };
  }

  // biome-ignore lint/suspicious/noExplicitAny: payload.response is a
  // union of literal unions; we defer validation to normalizeResponse so
  // an exhaustive switch over the record's kind enforces it.
  const normalized = normalizeResponse(record.kind, (payload as any).response);
  if (!normalized.ok) {
    return { ok: false, error: "invalid_response" };
  }

  // All checks passed — consume + deliver.
  registry.consume(key, userId);
  tombstonesFor(registry).add(key);

  deliverToolResult({
    conversationId: record.conversationId,
    toolUseId: record.toolUseId,
    content: normalized.content,
  });

  return { ok: true };
}
