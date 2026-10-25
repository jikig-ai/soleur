// Server-side diagnostic for the Claude CLI "Not logged in" reply (#10455, #10548 refs; plan
// knowledge-base/project/plans/2026-10-25-feat-agent-auth-failure-diagnostic-plan.md). A DIAGNOSTIC, not the fix: when the
// CLI replies that it has no usable credential although a validated credential was leased, this module reports ONE routed
// Sentry event (feature "agent-auth", constant message) whose ten closed-enum tags separate the competing root-cause
// hypotheses, so the cause can be read from telemetry instead of guessed.
//
// One implementation serves both runners (agent-runner.ts legacy loop; cc-dispatcher.ts realSdkQueryFactory):
//   matchAgentAuthFailure   pure   an SDK stream message -> a closed `match_kind`, or null
//   deriveAgentAuthContext  pure   the FINAL SDK options object -> closed-enum posture strings (never a value)
//   createAgentAuthFailureProbe    per Query: once-latch, per-user debounce, process-wide cap, lazy authMode lookup, emit
//   tapAgentAuthFailure     cc     in-place tap of the returned Query's async iterator (identity preserved)
//
// Safety properties (each is pinned by a test):
//   - The payload is ten closed-enum strings. No key material, env value, message body, user id, workspace path or IP can
//     reach Sentry or the pino line: every value is picked from a fixed list or falls back to "unknown".
//   - The observer never throws, never reorders or delays the stream, and every fire-and-forget branch ends in a swallowing
//     catch (crash-handlers.ts exits the process on `unhandledRejection`, so one stray async throw would end every
//     tenant's session). A swallowed fault is NOT silent: one constant-text logger.warn per probe, no err, no payload.
//   - The text arm of the matcher needs a CLI-set field (the `<synthetic>` model or `is_api_error_message`), which the model
//     cannot set: a tenant who makes the model reply with the exact CLI string must not be able to page the operator or
//     mute the real outage's email. The structured `authentication_failed` code is alone sufficient.
//   - This module touches nothing from ./observability at import time (partial vi.mock factories in the runner tests would
//     break), uses a local TTL map instead of TtlDedupMap, and imports no Supabase code (the authMode resolver is injected).
//   - There is exactly ONE emit site below. Its first argument is the literal `null` (the #8629 pino-mirror dedupe class: an
//     Error first argument makes the logger mirror a `feature=pino-mirror` capture and Sentry then drops this tagged one).
//
// REMOVAL CHECKLIST: see the header of ./agent-auth-mode.ts (one pass deletes the whole diagnostic).

import * as Sentry from "@sentry/nextjs";

import { API_KEY_ENV_VAR, OAUTH_ENV_VAR } from "./agent-auth-env-vars";
import { sandboxPostureOf, usesUnixDenyArtifact } from "./agent-sandbox-seccomp";
import {
  CLI_AUTH_FAILURE_REPLIES,
  SDK_API_KEY_SOURCES,
  SDK_AUTHENTICATION_FAILED,
  type CliAuthFailureKind,
} from "./claude-error-signatures";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

// ---------------------------------------------------------------------------
// Closed enums
// ---------------------------------------------------------------------------

export type AgentAuthRunner = "legacy" | "cc-soleur-go";
export type AgentAuthMatchKind = CliAuthFailureKind | "structured";
export type AgentAuthMode = "managed" | "api-key" | "unbound" | "unknown";

const ENUMS = {
  runner: ["legacy", "cc-soleur-go"],
  credential_scheme: ["api_key", "oauth_token", "unknown"],
  auth_env_present: ["true", "false", "unknown"],
  auth_mode: ["managed", "api-key", "unbound", "unknown"],
  cli_key_source: [...SDK_API_KEY_SOURCES, "unknown"],
  seccomp_artifact: ["base", "unixdeny", "unknown"],
  has_egress: ["true", "false", "unknown"],
  sandbox: ["on", "off", "unknown"],
  outer_wrap: ["true", "false", "unknown"],
  match_kind: ["not_logged_in", "invalid_api_key", "oauth_token_revoked", "session_expired", "structured"],
} as const satisfies Record<string, readonly string[]>;

export type AgentAuthPayload = { -readonly [K in keyof typeof ENUMS]: string };

/** The post-derivation, pre-resolution part of the payload (everything known at bindOptions time). */
export type AgentAuthContext = Pick<
  AgentAuthPayload,
  "runner" | "credential_scheme" | "auth_env_present" | "seccomp_artifact" | "has_egress" | "sandbox" | "outer_wrap"
>;

/** Pick `value` when it is a member of the closed list for `key`, else "unknown". Defends every payload value. */
function closed(key: keyof typeof ENUMS, value: unknown): string {
  return typeof value === "string" && (ENUMS[key] as readonly string[]).includes(value) ? value : "unknown";
}

const noop = (): void => undefined;
const RESOLVED: Promise<void> = Promise.resolve();

type Rec = Record<PropertyKey, unknown>;
const isRec = (v: unknown): v is Rec => typeof v === "object" && v !== null && !Array.isArray(v);

// ---------------------------------------------------------------------------
// Matcher
// ---------------------------------------------------------------------------

const MAX_REPLY_LENGTH = 200;
/** The model id the CLI stamps on messages it authors itself (measured from the real binary's stream). */
const CLI_SYNTHETIC_MODEL = "<synthetic>";

/** Cheap-first: type, then length, then the anchored regexes (no nested or overlapping quantifiers). */
function classifyReplyText(text: unknown): CliAuthFailureKind | null {
  if (typeof text !== "string") return null;
  if (text.length > MAX_REPLY_LENGTH) return null;
  const whole = text.trim();
  for (const { kind, pattern } of CLI_AUTH_FAILURE_REPLIES) {
    if (pattern.test(whole)) return kind;
  }
  return null;
}

/** The text of a message whose content is exactly ONE text block (a tool_use or a second block disqualifies it). */
function onlyTextBlock(inner: Rec): unknown {
  const content = inner.content;
  if (!Array.isArray(content) || content.length !== 1) return undefined;
  const block: unknown = content[0];
  return isRec(block) && block.type === "text" ? block.text : undefined;
}

/**
 * Classify one SDK stream message. Returns a closed `match_kind` or null; the returned value is never derived from the
 * message text (it is a member of a fixed list), so it can never carry the body.
 *
 * Text is classified FIRST and the structured code is the fallback, so `match_kind` keeps its variants (the real stream
 * carries BOTH the text and `error: "authentication_failed"` on the same message, so structured-first would flatten every
 * event to "structured"). The text arm of an assistant message additionally needs a CLI-set field, see the header.
 */
export function matchAgentAuthFailure(message: unknown): AgentAuthMatchKind | null {
  try {
    if (!isRec(message)) return null;
    if (message.type === "assistant") {
      const inner = message.message;
      if (isRec(inner) && (inner.model === CLI_SYNTHETIC_MODEL || message.is_api_error_message === true)) {
        const kind = classifyReplyText(onlyTextBlock(inner));
        if (kind !== null) return kind;
      }
      return message.error === SDK_AUTHENTICATION_FAILED ? "structured" : null;
    }
    if (message.type === "result") {
      return message.is_error === true ? classifyReplyText(message.result) : null;
    }
    return null;
  } catch {
    // A throwing getter on a hostile message object: the matcher must never throw into a runner loop.
    return null;
  }
}

// ---------------------------------------------------------------------------
// Context + payload
// ---------------------------------------------------------------------------

/**
 * Derive the posture strings from the FINAL options object handed to the SDK (after the cc seccomp recorder). Reads the
 * credential variable's PRESENCE only (a non-empty string); the value is never read into anything that is stored. The
 * seccomp artifact and egress come from the single predicate and the posture recorded by the sandbox builder, not from a
 * fourth spelling of the same expression. Anything unreadable stays "unknown"; this function never throws.
 */
export function deriveAgentAuthContext(runner: AgentAuthRunner, scheme: unknown, options: unknown): AgentAuthContext {
  const ctx: AgentAuthContext = {
    runner: closed("runner", runner),
    credential_scheme: closed("credential_scheme", scheme),
    auth_env_present: "unknown",
    seccomp_artifact: "unknown",
    has_egress: "unknown",
    sandbox: "unknown",
    outer_wrap: "unknown",
  };
  try {
    if (!isRec(options)) return ctx;
    const envVar = scheme === "api_key" ? API_KEY_ENV_VAR : scheme === "oauth_token" ? OAUTH_ENV_VAR : undefined;
    const env = options.env;
    if (envVar !== undefined && isRec(env)) {
      const present = env[envVar];
      ctx.auth_env_present = typeof present === "string" && present.length > 0 ? "true" : "false";
    }
    const sandbox = options.sandbox;
    ctx.sandbox = isRec(sandbox) && sandbox.enabled !== false ? "on" : "off";
    if (isRec(sandbox)) {
      const posture = sandboxPostureOf(sandbox);
      if (posture) {
        ctx.has_egress = posture.hasEgress ? "true" : "false";
        ctx.seccomp_artifact = usesUnixDenyArtifact(posture.hasEgress, posture.unixDenyFlag) ? "unixdeny" : "base";
      }
    }
    ctx.outer_wrap = typeof options.spawnClaudeCodeProcess === "function" ? "true" : "false";
  } catch {
    // Return whatever was derived before the throw; every remaining field stays "unknown".
  }
  return ctx;
}

/** Only `managed` and `api-key` pass; null is a conversation with no engine-run row; anything else is never echoed. */
export function normalizeAuthMode(raw: unknown): AgentAuthMode {
  if (raw === null) return "unbound";
  return raw === "managed" || raw === "api-key" ? raw : "unknown";
}

/** The ONE object `tags` and `extra` are both built from: ten keys, every value from a closed list. */
export function buildAgentAuthPayload(input: {
  context: AgentAuthContext;
  authMode: unknown;
  cliKeySource: unknown;
  matchKind: unknown;
}): AgentAuthPayload {
  const { context } = input;
  return {
    runner: closed("runner", context.runner),
    credential_scheme: closed("credential_scheme", context.credential_scheme),
    auth_env_present: closed("auth_env_present", context.auth_env_present),
    auth_mode: closed("auth_mode", input.authMode),
    cli_key_source: closed("cli_key_source", input.cliKeySource),
    seccomp_artifact: closed("seccomp_artifact", context.seccomp_artifact),
    has_egress: closed("has_egress", context.has_egress),
    sandbox: closed("sandbox", context.sandbox),
    outer_wrap: closed("outer_wrap", context.outer_wrap),
    match_kind: closed("match_kind", input.matchKind),
  };
}

// ---------------------------------------------------------------------------
// Emit (the single chokepoint)
// ---------------------------------------------------------------------------

function emitAgentAuthFailure(payload: AgentAuthPayload): void {
  let ran = false;
  const emit = (): void => {
    ran = true;
    // First argument is the literal `null`: the message path (see the header, #8629). With a null first argument the helper
    // sends `extra: { err: null, ...payload }` and the pino object `{ err: null, feature, op, ...payload }`, so the
    // contract is "extra equals the payload plus err:null". `extra` duplicates the tags because only `extra` reaches the pino
    // line (Better Stack), the second sink that still works if Sentry capture is the broken part.
    reportSilentFallback(null, {
      feature: "agent-auth",
      op: "cli-auth-failure",
      message: "agent-auth: the Claude CLI reported an authentication failure",
      tags: payload,
      extra: { ...payload },
    });
  };

  // The logger mirrors every warn+ line from every tenant into the process-wide scope as breadcrumbs, and that scope may
  // carry a user: run the capture on an isolated clone with both cleared so neither rides on this event. Where the SDK
  // does not expose withIsolationScope (partial mocks), the unscoped emit is the fallback.
  let withIsolationScope: unknown;
  try {
    withIsolationScope = Sentry.withIsolationScope;
  } catch {
    withIsolationScope = undefined;
  }
  if (typeof withIsolationScope !== "function") {
    emit();
    return;
  }
  // Under the SDK's default stack strategy (no async-context strategy installed, as in a bare unit test) withIsolationScope
  // hands back the SAME process-wide isolation scope instead of a clone, so clearing it would wipe every tenant's
  // breadcrumbs and user globally. Clear only a scope that really is a clone; production runs `Sentry.init` first
  // (server/index.ts imports sentry.server.config), which installs the AsyncLocalStorage strategy that clones.
  let outer: unknown;
  try {
    outer = Sentry.getIsolationScope();
  } catch {
    outer = undefined;
  }
  try {
    (withIsolationScope as typeof Sentry.withIsolationScope)((scope) => {
      if (scope !== outer) {
        scope.clearBreadcrumbs();
        scope.setUser(null);
      }
      emit();
    });
  } catch (err) {
    if (ran) throw err; // the emit itself failed: the caller releases the claim
    emit(); // the scope machinery failed before the emit: report unscoped rather than lose the event
  }
}

// ---------------------------------------------------------------------------
// Dedupe: per-user x tuple debounce plus a process-wide cap (a local TTL map, see the header)
// ---------------------------------------------------------------------------

export const AGENT_AUTH_DEBOUNCE_MS = 5 * 60 * 1000;
/** At most this many events per window across ALL users, so a flood of tenant-triggered failures is bounded. */
export const AGENT_AUTH_GLOBAL_CAP = 10;
export const AGENT_AUTH_MODE_TIMEOUT_MS = 1500;
const MAX_CLAIMS = 1024;

const claims = new Map<string, number>(); // key -> expiry (ms)
let globalWindow = { start: 0, count: 0 };
let suppressed = 0;

function globalHasRoom(at: number): boolean {
  if (at - globalWindow.start >= AGENT_AUTH_DEBOUNCE_MS || at < globalWindow.start) globalWindow = { start: at, count: 0 };
  return globalWindow.count < AGENT_AUTH_GLOBAL_CAP;
}

function claim(key: string, at: number): boolean {
  const expiry = claims.get(key);
  if (expiry !== undefined && expiry > at) return false;
  if (claims.size >= MAX_CLAIMS) {
    for (const [k, exp] of claims) if (exp <= at) claims.delete(k);
    // Still full: evict the oldest insertion (Map iteration order).
    if (claims.size >= MAX_CLAIMS) {
      const oldest = claims.keys().next();
      if (!oldest.done) claims.delete(oldest.value);
    }
  }
  claims.delete(key);
  claims.set(key, at + AGENT_AUTH_DEBOUNCE_MS);
  globalWindow.count += 1;
  return true;
}

function release(key: string): void {
  claims.delete(key);
  globalWindow.count = Math.max(0, globalWindow.count - 1);
}

/** Test seam: forget every claim, the cap window and the suppressed counter. */
export function __resetAgentAuthDedupeForTests(): void {
  claims.clear();
  globalWindow = { start: 0, count: 0 };
  suppressed = 0;
}

/** Events dropped by the process-wide cap since start (a bounded in-memory counter; never logged at warn). */
export function agentAuthSuppressedCount(): number {
  return suppressed;
}

// ---------------------------------------------------------------------------
// Probe
// ---------------------------------------------------------------------------

export interface AgentAuthFailureProbe {
  /** Identity function: derives the closed-enum context EAGERLY from the final options and retains no reference to them. */
  bindOptions<T>(options: T): T;
  /** Never throws, never rejects; the returned promise settles after the (fire-and-forget) emit and exists for tests. */
  observe(message: unknown): Promise<void>;
}

export interface AgentAuthProbeArgs {
  runner: AgentAuthRunner;
  /** The leased credential's scheme; anything outside `api_key | oauth_token` is reported as unknown. */
  credentialScheme: string;
  /** The user id: an in-process map key only. It is never emitted, never logged. */
  dedupeToken: string;
  /** Lazy, failure-path-only lookup of the persisted engine binding's auth mode (see ./agent-auth-mode). */
  resolveAuthMode?: () => Promise<string | null>;
  /** Test seam: clock for the debounce. */
  now?: () => number;
  /** Test seam: bound on the authMode lookup (default 1.5 s). */
  timeoutMs?: number;
}

/** A probe that observes nothing: the fallback when constructing the real one throws. */
export const NOOP_AGENT_AUTH_PROBE: AgentAuthFailureProbe = Object.freeze({
  bindOptions: <T>(options: T): T => options,
  observe: (): Promise<void> => RESOLVED,
});

/** One constant-text warn per owner (no err, no payload): a defect in the diagnostic is visible but never an event. */
function makeWarnOnce(): () => void {
  let warned = false;
  return () => {
    if (warned) return;
    warned = true;
    try {
      createChildLogger("auth-failure-probe").warn("auth-failure probe: observer error swallowed");
    } catch {
      // The logger is unavailable (a partial mock): nothing more to do.
    }
  };
}

const TIMED_OUT = Symbol("auth-mode-timeout");

/** Bounded, never-rejecting lookup: any failure, timeout or out-of-set value is "unknown". */
async function resolveAuthModeBounded(
  resolver: (() => Promise<string | null>) | undefined,
  timeoutMs: number,
): Promise<AgentAuthMode> {
  if (typeof resolver !== "function") return "unknown";
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const lookup = new Promise<unknown>((resolve) => resolve(resolver()));
    // The race loser must never surface as an unhandled rejection (a slow lookup can reject after the timeout won).
    lookup.catch(noop);
    const timeout = new Promise<typeof TIMED_OUT>((resolve) => {
      timer = setTimeout(() => resolve(TIMED_OUT), timeoutMs);
      (timer as { unref?: () => void }).unref?.();
    });
    const outcome = await Promise.race([lookup, timeout]);
    return outcome === TIMED_OUT ? "unknown" : normalizeAuthMode(outcome);
  } catch {
    return "unknown";
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

export function createAgentAuthFailureProbe(args: AgentAuthProbeArgs): AgentAuthFailureProbe {
  const clock = args.now ?? Date.now;
  const timeoutMs = args.timeoutMs ?? AGENT_AUTH_MODE_TIMEOUT_MS;
  const dedupeToken = String(args.dedupeToken);
  const warnOnce = makeWarnOnce();

  let context = deriveAgentAuthContext(args.runner, args.credentialScheme, undefined);
  let keySource = "unknown";
  // Once per turn: reset on every `result` (a warm cc Query serves many turns; the debounce is the cross-turn rate limit).
  let latched = false;

  const tupleKey = (): string =>
    [
      dedupeToken,
      context.runner,
      context.credential_scheme,
      context.auth_env_present,
      keySource,
      context.seccomp_artifact,
      context.has_egress,
      context.sandbox,
      context.outer_wrap,
    ].join("|");

  const emitAfterLookup = (matchKind: AgentAuthMatchKind, key: string): Promise<void> => {
    // Snapshot: the slot is claimed on this tuple, so the event must report the same one.
    const ctx = context;
    const source = keySource;
    return resolveAuthModeBounded(args.resolveAuthMode, timeoutMs)
      .then((authMode) => {
        emitAgentAuthFailure(buildAgentAuthPayload({ context: ctx, authMode, cliKeySource: source, matchKind }));
      })
      .catch(() => {
        release(key); // a burned window must not swallow the next event
        warnOnce();
      });
  };

  return {
    bindOptions<T>(options: T): T {
      try {
        context = deriveAgentAuthContext(args.runner, args.credentialScheme, options);
      } catch {
        warnOnce();
      }
      return options;
    },

    observe(message: unknown): Promise<void> {
      try {
        if (!isRec(message)) return RESOLVED;
        const type = message.type;
        if (type === "system") {
          if (message.subtype === "init") keySource = closed("cli_key_source", message.apiKeySource);
          return RESOLVED;
        }
        const isResult = type === "result";
        if (type !== "assistant" && !isResult) return RESOLVED;

        const matchKind = matchAgentAuthFailure(message);
        const wasLatched = latched;
        if (isResult) latched = false;
        if (matchKind === null || wasLatched) return RESOLVED;
        if (!isResult) latched = true;

        // The cap is checked FIRST so a flood cannot evict per-user entries; a suppressed event is only counted.
        const at = clock();
        if (!globalHasRoom(at)) {
          if (suppressed < Number.MAX_SAFE_INTEGER) suppressed += 1;
          return RESOLVED;
        }
        // Claim the slot synchronously (the tuple is complete here: `init` precedes the failure message), THEN look up
        // authMode and emit: the claim caps the lookup at one per tuple per window.
        const key = tupleKey();
        if (!claim(key, at)) return RESOLVED;
        return emitAfterLookup(matchKind, key);
      } catch {
        warnOnce();
        return RESOLVED;
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Tap (cc path)
// ---------------------------------------------------------------------------

const TAPPED = new WeakSet<object>();

type IterResult = { done?: boolean; value?: unknown };

/**
 * Observe the messages a Query yields without touching its identity, ordering or lifecycle. Overrides
 * `[Symbol.asyncIterator]` in place (the object is returned, not a wrapper). The real SDK Query returns an internal
 * single-use Stream from that method and `for await` only ever calls that object's `next`/`return`/`throw`, so the wrapper
 * delegates to the object the original method returned and NEVER calls that object's own iterator method (it throws on a
 * second call). `next()` returns the ORIGINAL promise and observes on a side branch, so the consumer's path gains no
 * `await` and cannot reorder against a concurrent close. `return` and `throw` are delegated untouched.
 *
 * Boundary: a direct `query.next()` caller is not observed (none exists in soleur-go-runner or cc-dispatcher; a runner test
 * pins that `consumeStream` still iterates with `for await`). A frozen, non-extensible or non-writable object, a
 * non-iterable value, or a second tap of the same object is returned untouched.
 */
export function tapAgentAuthFailure<T>(query: T, probe: { observe(message: unknown): unknown }): T {
  try {
    if (query === null || (typeof query !== "object" && typeof query !== "function")) return query;
    const target = query as unknown as Rec;
    if (TAPPED.has(target)) return query;
    if (!probe || typeof probe.observe !== "function") return query;
    const original = target[Symbol.asyncIterator];
    if (typeof original !== "function") return query;
    const bound = (original as () => AsyncIterator<unknown>).bind(query);
    const warnOnce = makeWarnOnce();

    const observeSafely = (value: unknown): void => {
      try {
        const out = probe.observe(value);
        if (out !== null && typeof out === "object" && typeof (out as Promise<unknown>).then === "function") {
          (out as Promise<unknown>).then(undefined, noop);
        }
      } catch {
        warnOnce();
      }
    };

    const tappedIterator = (): AsyncIterator<unknown> => {
      const it = bound();
      const tapped: AsyncIterator<unknown> & { [Symbol.asyncIterator]?: () => unknown } = {
        next(...args: [] | [undefined]) {
          const pending = it.next(...args);
          try {
            if (pending !== null && typeof pending === "object" && typeof (pending as Promise<IterResult>).then === "function") {
              (pending as Promise<IterResult>).then((r) => {
                if (r && r.done !== true) observeSafely(r.value);
              }, noop);
            } else if (pending && (pending as IterResult).done !== true) {
              observeSafely((pending as IterResult).value);
            }
          } catch {
            warnOnce();
          }
          return pending;
        },
      };
      if (typeof it.return === "function") tapped.return = (...a: [] | [unknown]) => it.return!(...a);
      if (typeof it.throw === "function") tapped.throw = (e?: unknown) => it.throw!(e);
      tapped[Symbol.asyncIterator] = () => tapped;
      return tapped;
    };

    Object.defineProperty(target, Symbol.asyncIterator, {
      value: tappedIterator,
      writable: true,
      configurable: true,
      enumerable: false,
    });
    TAPPED.add(target);
    return query;
  } catch {
    return query;
  }
}
