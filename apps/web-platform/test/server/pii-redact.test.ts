import { describe, it, expect } from "vitest";

import {
  MAX_REDACT_INPUT,
  REDACTED_EMAIL,
  redactEmailAddresses,
  redactErrorForEmit,
} from "../../server/pii-redact";
import { OutboundComplianceError } from "../../server/email-triage/outbound-compliance";

// Synthesized, distinctive tokens: a leak of either half is detectable
// without matching generic words.
const LOCAL = "qzv8tkl";
const DOMAIN = "mailbox-r7x.example";
const ADDR = `${LOCAL}@${DOMAIN}`;

/** Every string reachable from `v`, including non-enumerable own properties. */
function allText(v: unknown, seen = new Set<unknown>()): string {
  if (v === null || v === undefined) return "";
  if (typeof v === "string") return v;
  if (typeof v !== "object" && typeof v !== "function") return String(v);
  if (seen.has(v)) return "";
  seen.add(v);
  const parts: string[] = [];
  for (const key of Object.getOwnPropertyNames(v)) {
    try {
      parts.push(allText((v as Record<string, unknown>)[key], seen));
    } catch {
      // A throwing getter is not text a sink could have read either.
    }
  }
  return parts.join("\n");
}

function expectClean(label: string, v: unknown): void {
  const text = allText(v);
  expect(text, `${label} leaked the local part`).not.toContain(LOCAL);
  expect(text, `${label} leaked the domain`).not.toContain(DOMAIN);
}

describe("instrument self-test", () => {
  it("allText/expectClean detect a leak in a message, a stack, a nested field and a cause", () => {
    for (const leaky of [
      new Error(ADDR),
      Object.assign(new Error("x"), { details: ADDR }),
      { message: "ok", nested: { deeper: ADDR } },
      new Error("wrap", { cause: new Error(ADDR) }),
    ]) {
      expect(() => expectClean("leaky fixture", leaky)).toThrow();
    }
  });
});

describe("redactEmailAddresses — what it redacts and what it keeps", () => {
  const REDACT: string[] = [
    ADDR,
    `o'neil@${DOMAIN}`,
    `jane+tag@${DOMAIN}`,
    `${LOCAL.toUpperCase()}@MAILBOX-R7X.EXAMPLE`,
    `${LOCAL}@sub.${DOMAIN}`,
    `${LOCAL}@x.io`,
    `${LOCAL}@x.de`,
    `jösé${LOCAL}@bücher-${LOCAL}.de`,
    `${LOCAL}%40${DOMAIN}`,
    `${LOCAL}＠${DOMAIN}`,
    `<${ADDR}>`,
    `"${ADDR}"`,
    `Key (email)=(${ADDR}) already exists.`,
  ];
  for (const input of REDACT) {
    it(`redacts ${JSON.stringify(input)}`, () => {
      const out = redactEmailAddresses(input);
      expect(out).toContain(REDACTED_EMAIL);
      expect(out).not.toMatch(new RegExp(LOCAL, "i"));
    });
  }

  const KEEP: string[] = [
    "pkg@1.2.3",
    // A two-digit last segment: the case the digit-free TLD rule exists for
    // (a single-digit segment is already excluded by the 2-char minimum).
    "lodash@4.17.21",
    "at fn (/app/node_modules/.pnpm/lodash@4.17.21/node_modules/lodash/lodash.js:1:1)",
    "at fn (/app/node_modules/@scope/pkg@1.2.3/dist/index.js:10:5)",
    "at fn (/app/node_modules/.pnpm/next@15.3.0_react@19.1.0/node_modules/next/x.js:1:1)",
    "user@localhost",
    "plain prose with no address",
  ];
  for (const input of KEEP) {
    it(`leaves ${JSON.stringify(input)} unchanged`, () => {
      expect(redactEmailAddresses(input)).toBe(input);
    });
  }

  it("redacts two addresses on one line independently", () => {
    const out = redactEmailAddresses(`${ADDR} and other-${LOCAL}@x.io`);
    expect(out).toBe(`${REDACTED_EMAIL} and ${REDACTED_EMAIL}`);
  });
});

describe("redactEmailAddresses — linear time on adversarial input", () => {
  // The pre-fix pattern was O(n^2) here: 13 s at 64k characters. Each input
  // below is a long run with no valid address after it. 500 ms is two orders
  // of magnitude above the measured linear cost and below the quadratic one.
  const N = 100_000;
  const ADVERSARIAL: Record<string, string> = {
    "letters, no @": "a".repeat(N),
    "hex blob": "0123456789abcdef".repeat(N / 16),
    "dotted run": "a.".repeat(N / 2),
    "@ then dotted": `a@${"b.".repeat(N / 2)}`,
    "@ then dashes": `a@${"b-".repeat(N / 2)}`,
    "numeric TLD": `${"a".repeat(N)}@1.1.1`,
  };
  for (const [name, input] of Object.entries(ADVERSARIAL)) {
    it(`${name} (${input.length} chars) finishes in under 500 ms`, () => {
      const t = performance.now();
      redactEmailAddresses(input);
      expect(performance.now() - t).toBeLessThan(500);
    });
  }

  it("fails closed past MAX_REDACT_INPUT: the tail is dropped, never emitted unscanned", () => {
    const input = `${"x ".repeat(MAX_REDACT_INPUT)} ${ADDR}`;
    const out = redactEmailAddresses(input);
    expect(out).not.toContain(LOCAL);
    expect(out).toContain("[truncated ");
  });
});

describe("redactErrorForEmit — every shape a sink walks", () => {
  it("an error with nothing to redact is returned as the SAME instance", () => {
    const e = new Error("plain failure");
    expect(redactErrorForEmit(e)).toBe(e);
    const o = { message: "ok", code: 1 };
    expect(redactErrorForEmit(o)).toBe(o);
  });

  it("redacts the message, keeps the subclass and its code, and does not mutate the caller's error", () => {
    const original = new OutboundComplianceError("invalid_address", `bad ${ADDR}`, "to");
    const out = redactErrorForEmit(original) as OutboundComplianceError;
    expect(out).toBeInstanceOf(OutboundComplianceError);
    expect(out.code).toBe("invalid_address");
    expect(out.field).toBe("to");
    expect(out.name).toBe("OutboundComplianceError");
    expectClean("copy", out);
    expect(original.message).toContain(LOCAL);
  });

  it("redacts an address that is in the stack only", () => {
    const e = new Error("clean message");
    e.stack = `Error: clean message\n    at send (${ADDR})`;
    const out = redactErrorForEmit(e);
    expect(out).not.toBe(e);
    expectClean("stack-only", out);
  });

  it("walks the cause chain", () => {
    const e = new Error("send failed", { cause: new Error("inner", { cause: new Error(ADDR) }) });
    expectClean("cause chain", redactErrorForEmit(e));
  });

  it("walks own enumerable properties (PostgREST details/hint)", () => {
    const e = Object.assign(new Error("duplicate key"), {
      code: "23505",
      details: `Key (email)=(${ADDR}) already exists.`,
      hint: null,
    });
    const out = redactErrorForEmit(e) as typeof e;
    expectClean("details", out);
    expect(out.code).toBe("23505");
  });

  it("walks a plain-object error (supabase-js / Resend shape)", () => {
    const out = redactErrorForEmit({ name: "validation_error", message: `Invalid to: ${ADDR}`, statusCode: 422 });
    expectClean("plain object", out);
    expect((out as { statusCode: number }).statusCode).toBe(422);
  });

  it("walks AggregateError.errors", () => {
    const out = redactErrorForEmit(new AggregateError([new Error(ADDR)], "several"));
    expectClean("aggregate", out);
  });

  it("redacts a string err", () => {
    expect(redactErrorForEmit(`failed for ${ADDR}`)).not.toContain(LOCAL);
  });

  it("maps a self-referential cause onto the copy instead of re-emitting the original", () => {
    const e = new Error(ADDR);
    (e as Error & { cause?: unknown }).cause = e;
    const out = redactErrorForEmit(e) as Error & { cause?: unknown };
    expectClean("cycle", out);
    expect(out.cause).toBe(out);
  });

  it("replaces a chain deeper than the cap rather than forwarding it", () => {
    let e: Error = new Error(ADDR);
    for (let i = 0; i < 10; i++) e = new Error(`level ${i}`, { cause: e });
    expectClean("deep chain", redactErrorForEmit(e));
  });

  it("does not throw on a non-string message or a null stack", () => {
    const e = new Error("x");
    Object.defineProperty(e, "message", { value: 42 });
    (e as { stack: unknown }).stack = null;
    expect(() => redactErrorForEmit(e)).not.toThrow();
  });

  it("produces a readable copy of a DOMException carrying an address", () => {
    const out = redactErrorForEmit(new DOMException(`bad ${ADDR}`, "SyntaxError")) as Error;
    expect(() => `${out.name}: ${out.message}`).not.toThrow();
    expect(out.message).not.toContain(LOCAL);
  });

  it("returns a placeholder carrying no message when a property getter throws", () => {
    const e = new Error(ADDR) as Error & { code?: string };
    e.code = "E_BOOM";
    Object.defineProperty(e, "boom", {
      enumerable: true,
      get() {
        throw new Error("getter exploded");
      },
    });
    const out = redactErrorForEmit(e) as Error & { code?: string };
    expectClean("placeholder", out);
    expect(out.message).toMatch(/redaction failed/);
    expect(out.code).toBe("E_BOOM");
  });
});
