import { redactCommandForDisplay } from "@/lib/safety/redaction-allowlist";
import { reportSilentFallback } from "@/server/observability";
import { buildToolLabel } from "./tool-labels";
import { debugRedactionProbeTrips } from "./debug-probes";
import { capUtf8Bytes, COMMAND_STREAM_TOTAL_CAP_BYTES } from "./command-stream-caps";

// feat-debug-mode-stream — pure, unit-testable construction of a `debug_event`
// WS frame from a single SDK harness event. The whole redaction + DROP-first
// policy lives here so `test/server/debug-event.test.ts` can assert the WIRE
// BYTES directly (not "the redactor was called") without standing up the SDK
// loop. cc-dispatcher's emit callbacks are thin wrappers over `emitDebugEvent`.
//
// `capUtf8Bytes` + `COMMAND_STREAM_TOTAL_CAP_BYTES` are REUSED from
// `./command-stream-caps` (no new cap constants — plan §Phase 3.2). That
// module holds the canonical definitions; `cc-dispatcher.ts` re-exports them,
// so this path shares the exact same caps with zero cc-dispatcher coupling.

export type DebugEventKind = "tool_use" | "reasoning" | "result";

export interface DebugEventFrame {
  type: "debug_event";
  kind: DebugEventKind;
  label?: string;
  body: string;
}

// The DROP placeholder body for a tool_use whose redacted input still tripped
// the probe. The tool_use frame STAYS visible (the operator sees a tool ran);
// only the input is withheld. Never carries the raw tool name or input.
const DROP_PLACEHOLDER = "[input withheld: failed redaction probe]";

// A property key whose final segment (or whole name) is a credential noun.
// When an object property is credential-keyed, its ENTIRE string value is
// redacted to `[redacted-key]` regardless of the value's own shape (P0-6): in
// structured JSON the key and value are SEPARATE leaves, so a value leaf like
// `"Bearer abc123"` or a generic `"hunter2"` has LOST its `Authorization:` /
// `X_TOKEN=` anchor — the redactor (which anchors on the assignment/header
// form) cannot see the credential context, but the KEY can. This is the
// structured-JSON complement to per-leaf redaction.
const CREDENTIAL_KEY_SEGMENTS = new Set([
  "token", "key", "secret", "password", "passwd", "pat", "credential",
  "credentials", "auth", "authorization", "apikey", "bearer", "cookie",
  "session", "jwt", "privatekey", "accesskey", "clientsecret",
]);

function isCredentialKey(key: string): boolean {
  const lower = key.toLowerCase();
  if (CREDENTIAL_KEY_SEGMENTS.has(lower)) return true;
  return key
    .split(/[_\-.\s]+/)
    .some((seg) => CREDENTIAL_KEY_SEGMENTS.has(seg.toLowerCase()));
}

/**
 * Recursively redact every STRING LEAF of a parsed JSON value; the caller then
 * serializes the result. Two complementary gates (P0-6):
 *   1. Per-leaf SELF-ANCHORED redaction — `redactCommandForDisplay` on each
 *      string value catches shapes that carry their own anchor (sk-ant-/ghp_/
 *      AKIA/Stripe/JWT/conn-string/email/uuid/ip/phone, and an in-ONE-string
 *      `export X_TOKEN=…` / `Authorization: Bearer …` as in a Bash command).
 *   2. KEY-AWARE redaction — when the property key is a credential noun, the
 *      WHOLE value is dropped to `[redacted-key]`. Restores the credential
 *      context that `JSON.stringify` strips (`"X_TOKEN":"v"` /
 *      `"Authorization":"Bearer v"` — separate key + value leaves), which
 *      neither per-leaf redaction nor the JSON-blob probe can recover.
 * The `keyContext` is the enclosing object property name (undefined for array
 * elements / the root).
 */
function redactStringLeaves(value: unknown, keyContext?: string): unknown {
  if (typeof value === "string") {
    if (keyContext && isCredentialKey(keyContext)) return "[redacted-key]";
    return redactCommandForDisplay(value);
  }
  if (Array.isArray(value)) {
    // Array elements inherit the enclosing key's credential context (e.g.
    // `{"secrets":["a","b"]}` → both elements dropped).
    return value.map((v) => redactStringLeaves(v, keyContext));
  }
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = redactStringLeaves(v, k);
    }
    return out;
  }
  // number / boolean / null / undefined — no string content to redact.
  return value;
}

/**
 * Build a `debug_event` frame from one SDK harness event. Returns `null` when
 * the frame should not be emitted (empty body, or a `reasoning`/`result` whose
 * redacted output still tripped the probe → DROP the whole frame).
 *
 * For `tool_use`, `rawValue` is the PARSED tool_input object; the body is the
 * per-string-leaf-redacted serialization (or the DROP placeholder on a probe
 * trip — but the frame still emits, so the operator knows a tool ran). The
 * `label` is ALWAYS `buildToolLabel(name, undefined, …)` — the human tool
 * category, NEVER the raw SDK tool name (#2138/PR#2115) and NEVER input-derived
 * (passing `undefined` for input avoids leaking e.g. a Grep pattern into the
 * label).
 */
export function buildDebugEvent(args: {
  kind: DebugEventKind;
  /** tool_use: the parsed tool_input object. reasoning/result: a string. */
  rawValue: unknown;
  /** tool_use only — raw SDK tool name, fed to buildToolLabel. */
  toolName?: string;
  workspacePath?: string;
}): DebugEventFrame | null {
  const { kind, rawValue, toolName, workspacePath } = args;

  if (kind === "tool_use") {
    const label = buildToolLabel(toolName ?? "", undefined, workspacePath);

    const redactedObj = redactStringLeaves(rawValue ?? {});
    let serialized: string;
    try {
      serialized = JSON.stringify(redactedObj) ?? "";
    } catch {
      // Circular / unserializable input → emit an empty body, not a throw.
      serialized = "";
    }
    const body = capUtf8Bytes(serialized, COMMAND_STREAM_TOTAL_CAP_BYTES).text;

    if (debugRedactionProbeTrips(body)) {
      return { type: "debug_event", kind: "tool_use", label, body: DROP_PLACEHOLDER };
    }
    return { type: "debug_event", kind: "tool_use", label, body };
  }

  // reasoning / result — rawValue is a string. No label.
  const raw = typeof rawValue === "string" ? rawValue : "";
  const body = capUtf8Bytes(
    redactCommandForDisplay(raw),
    COMMAND_STREAM_TOTAL_CAP_BYTES,
  ).text;
  if (body.length === 0) return null;
  // A prose secret that survived redaction (e.g. a sentinel key narrated in
  // assistant text) → DROP the whole frame. Unlike tool_use there is no
  // structured label worth preserving.
  if (debugRedactionProbeTrips(body)) return null;
  return { type: "debug_event", kind, body };
}

/**
 * Gated emit wrapper. Builds the frame and `send`s it ONLY when `enabled`
 * (the per-dispatch `debugPosture && debugEligible` gate). The `catch` logs
 * ONLY `{userId, conversationId, kind}` — NEVER `body`/`rawValue`, which may
 * carry the unredacted secret that triggered the failure (Sentry-value PII
 * discipline; AC7).
 */
export function emitDebugEvent(args: {
  enabled: boolean;
  kind: DebugEventKind;
  rawValue: unknown;
  toolName?: string;
  workspacePath?: string;
  userId: string;
  conversationId: string;
  send: (frame: DebugEventFrame) => void;
}): void {
  if (!args.enabled) return;
  try {
    const frame = buildDebugEvent({
      kind: args.kind,
      rawValue: args.rawValue,
      toolName: args.toolName,
      workspacePath: args.workspacePath,
    });
    if (frame) args.send(frame);
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cc-dispatcher",
      op: "emitDebugEvent",
      extra: {
        userId: args.userId,
        conversationId: args.conversationId,
        kind: args.kind,
      },
    });
  }
}
