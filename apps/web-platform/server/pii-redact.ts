// Value-based address redaction for log and error-tracking sinks (#8532 PR-0).
//
// LEAF MODULE: imports nothing. `logger.ts`, `observability.ts` and
// `sentry-scrub.ts` all consume it, and `sentry-scrub.ts` must not pull in
// the logger or Sentry.
//
// Key-name redaction (`sensitive-keys.ts`) cannot see an address INSIDE a
// string value — an `err.message` from a throw site or a vendor SDK, a
// PostgREST `details` string — and Sentry turns `err.message` into the issue
// title. This module redacts by value. It is defense in depth: the
// primary control is that no throw site interpolates an address.
//
// Not covered, by design: a display name with no address beside it cannot be
// recognised by shape, and an address split across a line break is not
// rejoined.

export const REDACTED_EMAIL = "[redacted-email]";

// Characters that may appear in an address local part. Deliberately wide
// (unicode letters, `'`, `%`, `+`, `!#$`…) so a real recipient is not missed;
// the exclusions are the characters that delimit an address in prose, JSON,
// a URL path or a stack frame.
const LOCAL_CHAR = `[^\\s@\\uFF20<>"(),;:/\\\\\\[\\]{}]`;
// A domain label additionally excludes `.` (the label separator) and `%`.
const LABEL_CHAR = `[^\\s@\\uFF20<>"(),;:/\\\\\\[\\]{}.%]`;
// The TLD excludes digits and `_`/`-`, so a version-pinned package path in a
// stack frame (`pkg@1.2.3`) is left alone.
const TLD_CHAR = `[^\\s@\\uFF20<>"(),;:/\\\\\\[\\]{}.%\\d_-]`;

// The leading negative lookbehind makes a match start only at the BEGINNING
// of a local-part run. Without it the engine retries from every position in a
// long run with no valid address after it — O(n^2), measured at 13 s on a
// 64k-character string — and this runs on every silent-fallback emit.
// `@`, fullwidth `＠` and URL-encoded `%40` are all accepted as the separator.
const EMAIL_ADDRESS_RE = new RegExp(
  `(?<!${LOCAL_CHAR})${LOCAL_CHAR}+(?:@|\\uFF20|%40)${LABEL_CHAR}+(?:\\.${LABEL_CHAR}+)*\\.${TLD_CHAR}{2,}`,
  "gu",
);

// Input bound. The pattern is linear, so this is a second line of defense,
// and it fails CLOSED: text past the cap is dropped, never emitted unscanned.
export const MAX_REDACT_INPUT = 256 * 1024;

export function redactEmailAddresses(text: string): string {
  const bounded =
    text.length > MAX_REDACT_INPUT
      ? `${text.slice(0, MAX_REDACT_INPUT)}…[truncated ${text.length - MAX_REDACT_INPUT} chars]`
      : text;
  return bounded.replace(EMAIL_ADDRESS_RE, REDACTED_EMAIL);
}

// Past this depth a nested value is replaced, never forwarded — Sentry walks
// linked errors to depth 5 and pino-std-serializers walks the whole cause chain.
const MAX_DEPTH = 5;
const TRUNCATED = "[redaction depth exceeded]";
const HIDDEN = { writable: true, configurable: true, enumerable: false } as const;

function isPlainObject(v: object): boolean {
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

function redactValue(
  value: unknown,
  depth: number,
  seen: WeakMap<object, unknown>,
): unknown {
  if (typeof value === "string") return redactEmailAddresses(value);
  if (value === null || (typeof value !== "object" && typeof value !== "function")) {
    return value;
  }
  const obj = value as object;
  if (seen.has(obj)) return seen.get(obj);
  if (depth > MAX_DEPTH) {
    return value instanceof Error ? new Error(TRUNCATED) : TRUNCATED;
  }

  if (value instanceof Error) return redactError(value, depth, seen);
  if (Array.isArray(value)) {
    const out: unknown[] = [];
    seen.set(obj, out);
    let changed = false;
    for (const item of value) {
      const r = redactValue(item, depth + 1, seen);
      if (r !== item) changed = true;
      out.push(r);
    }
    if (!changed) seen.set(obj, value);
    return changed ? out : value;
  }
  if (!isPlainObject(obj)) return value;

  // Plain-object errors: supabase-js builds `{ error }` with JSON.parse, and
  // Resend returns `{ message, statusCode, name }` — neither is an Error.
  const out: Record<string, unknown> = {};
  seen.set(obj, out);
  let changed = false;
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    const r = redactValue(v, depth + 1, seen);
    if (r !== v) changed = true;
    out[k] = r;
  }
  if (!changed) seen.set(obj, value);
  return changed ? out : value;
}

function redactError(
  err: Error,
  depth: number,
  seen: WeakMap<object, unknown>,
): unknown {
  // A COPY with own data properties. `name`, `message` and `stack` are always
  // defined as OWN properties on the copy, which shadows any prototype getter
  // that reads internal state (DOMException's getters throw on a non-branded
  // receiver) — so the copy is readable even where the prototype is exotic.
  const copy = Object.create(Object.getPrototypeOf(err)) as Error;
  seen.set(err, copy);
  let changed = false;
  const put = (key: string, original: unknown, redacted: unknown, hidden: boolean) => {
    if (redacted !== original) changed = true;
    Object.defineProperty(
      copy,
      key,
      hidden ? { ...HIDDEN, value: redacted } : { ...HIDDEN, enumerable: true, value: redacted },
    );
  };

  // String() so a non-string `message`/`name` cannot make `.replace` throw.
  put("name", err.name, String(err.name), true);
  put("message", err.message, redactEmailAddresses(String(err.message)), true);
  if (typeof err.stack === "string") {
    put("stack", err.stack, redactEmailAddresses(err.stack), true);
  }

  for (const key of Object.getOwnPropertyNames(err)) {
    if (key === "name" || key === "message" || key === "stack") continue;
    const desc = Object.getOwnPropertyDescriptor(err, key);
    if (!desc) continue;
    // Accessor properties are read once and frozen into data properties; the
    // value is what a serializer would have read anyway.
    const original = "value" in desc ? desc.value : desc.get?.call(err);
    // `cause` and AggregateError's `errors` land here as own properties.
    put(key, original, redactValue(original, depth + 1, seen), !desc.enumerable);
  }
  // An inherited `cause` (a getter on a subclass prototype) is not an own
  // property but is still walked by both sinks.
  if (!Object.prototype.hasOwnProperty.call(err, "cause") && "cause" in err) {
    const original = (err as { cause?: unknown }).cause;
    put("cause", original, redactValue(original, depth + 1, seen), true);
  }

  if (!changed) {
    // Nothing to redact: forward the SAME instance, so Sentry's
    // already-captured marker on it keeps a rethrow from double-reporting.
    seen.set(err, err);
    return err;
  }
  return copy;
}

/**
 * Redact address-shaped substrings from anything about to be handed to a log
 * or error-tracking sink: an Error (its message, stack, own properties, cause
 * chain and AggregateError `errors`), a plain-object error, an array, or a
 * string. The caller's value is never mutated. A value with nothing to
 * redact is returned as the same instance.
 *
 * NEVER THROWS. On any internal failure it returns a placeholder Error that
 * carries only the original `name` and a string `code`, never the original
 * message — a redaction failure must not become either a crash in the
 * caller's catch block or an unredacted emit.
 */
export function redactErrorForEmit(err: unknown): unknown {
  try {
    return redactValue(err, 0, new WeakMap());
  } catch {
    const placeholder = new Error("[error withheld: redaction failed]");
    try {
      const e = err as { name?: unknown; code?: unknown } | null;
      if (e && typeof e.name === "string") placeholder.name = e.name;
      if (e && typeof e.code === "string") {
        (placeholder as Error & { code?: string }).code = e.code;
      }
    } catch {
      // Reading name/code threw too; the bare placeholder is the answer.
    }
    return placeholder;
  }
}
