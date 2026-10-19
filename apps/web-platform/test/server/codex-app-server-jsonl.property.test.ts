import { describe, expect, it } from "vitest";
import fc from "fast-check";
import {
  decodeCodexJsonlLine,
  decodeCodexJsonlStream,
  encodeCodexJsonl,
} from "@/server/codex-app-server-jsonl";

// Property-based suite (fast-check) — round-trip + rejection-taxonomy classes.
// Convention: when a property fails, fast-check prints `seed` + `path`;
// shrink, then pin the counterexample as a permanent it() labelled
// `// regression fixture: fast-check seed <seed> path <path>`.
// Never commit { seed } params — the stream must keep moving.
// See apps/web-platform/test/README.md "Property-based tests" and
// scripts/lib/property-harness.md.

// Arbitrary Codex RPC messages: JSON-compatible objects. fc.dictionary over
// fc.jsonValue gives nested objects/arrays/scalars while staying strictly
// JSON-serializable.
const messageArb = fc.dictionary(fc.string(), fc.jsonValue());

// encode/decode contract is the WIRE form: JSON has no -0 (it serializes to
// 0) and no distinct NaN/undefined — jsonValue() can still emit -0, so the
// oracle is the canonical JSON form of the message, not the raw reference.
const canonical = (m: unknown): unknown => JSON.parse(JSON.stringify(m));

async function collect(
  stream: AsyncIterable<Record<string, unknown>>,
): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = [];
  for await (const m of stream) out.push(m);
  return out;
}

describe("codex-app-server-jsonl — encode/decode round-trip (property)", () => {
  it("decode(encode(m)) reproduces the canonical JSON form of m", () => {
    fc.assert(
      fc.property(messageArb, (m) => {
        const frame = encodeCodexJsonl(m);
        expect(frame.endsWith("\n")).toBe(true);
        expect(decodeCodexJsonlLine(frame)).toEqual(canonical(m));
      }),
    );
  });

  it("stream reassembly is invariant under arbitrary chunk splits", async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.array(messageArb, { maxLength: 8 }),
        fc.array(fc.nat(), { maxLength: 16 }),
        async (messages, rawCuts) => {
          const wire = messages.map(encodeCodexJsonl).join("");
          // Split at arbitrary string offsets — including mid-codepoint and
          // immediately after a frame's newline.
          const cuts = rawCuts
            .map((c) => c % (wire.length + 1))
            .sort((a, b) => a - b);
          const chunks: string[] = [];
          let prev = 0;
          for (const c of cuts) {
            chunks.push(wire.slice(prev, c));
            prev = c;
          }
          chunks.push(wire.slice(prev));
          const got = await collect(decodeCodexJsonlStream(chunks));
          expect(got).toEqual(messages.map(canonical));
        },
      ),
    );
  });

  it("encodeCodexJsonl rejects every non-object input with codex_rpc_frame_invalid", () => {
    const nonObject = fc.oneof(
      fc.array(fc.jsonValue()),
      fc.constant(null),
      fc.string(),
      fc.integer(),
      fc.boolean(),
    );
    fc.assert(
      fc.property(nonObject, (x) => {
        try {
          encodeCodexJsonl(x);
        } catch (err) {
          expect((err as Error & { code?: string }).code).toBe(
            "codex_rpc_frame_invalid",
          );
          return;
        }
        throw new Error("encodeCodexJsonl accepted a non-object input");
      }),
    );
  });

  it("decodeCodexJsonlLine rejects lines that do not yield a JSON object", () => {
    // Lines that are blank, not JSON, or JSON non-objects must all throw. The
    // filter mirrors the decoder's strip order (\n then \r) so we only feed
    // inputs with no legal decode.
    const nonObjectLine = fc.string().filter((s) => {
      let v: unknown;
      try {
        v = JSON.parse(s.replace(/\n$/, "").replace(/\r$/, ""));
      } catch {
        return true;
      }
      return !(v !== null && typeof v === "object" && !Array.isArray(v));
    });
    fc.assert(
      fc.property(nonObjectLine, (line) => {
        expect(() => decodeCodexJsonlLine(line)).toThrow();
      }),
    );
  });

  it("rejects frames above the 1 MiB bound (example — codex_rpc_frame_too_large)", () => {
    const tooBig = { data: "x".repeat(1_100_000) };
    try {
      encodeCodexJsonl(tooBig);
    } catch (err) {
      expect((err as Error & { code?: string }).code).toBe(
        "codex_rpc_frame_too_large",
      );
      return;
    }
    throw new Error("encodeCodexJsonl accepted an over-bound frame");
  });

  // Negative control: the harness must be able to fail. A property that can
  // only pass proves nothing (anti-vacuity, AC6).
  it("negative control: a deliberately-false property throws and prints a seed", () => {
    let threw = false;
    try {
      fc.assert(fc.property(fc.integer(), () => false));
    } catch (err) {
      threw = true;
      expect(/seed/i.test((err as Error).message)).toBe(true);
    }
    expect(threw).toBe(true);
  });
});
