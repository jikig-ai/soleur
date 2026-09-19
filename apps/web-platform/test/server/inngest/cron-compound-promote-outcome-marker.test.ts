// The SOLEUR_COMPOUND_PROMOTE_OUTCOME marker must reach Better Stack as ONE
// single-line JSON row at pino WARN (40) — the shape the runbook decode, the
// #8281 follow-through probe and Vector's `app_container_warn_filter` read.
// Property under test: the emitter, called exactly as the handler calls it
// (one argument, no sink), writes through the marker module's OWN pino
// instance — never Inngest's console-backed ctx.logger, whose `warn(obj, msg)`
// renders as multi-line util.inspect text (measured 2026-09-18 23:11:54Z; see
// server/compound-promote-marker.ts for the invariant and the learning).
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

// Same seam as cron-liveness-marker.test.ts / claude-cost-marker.test.ts: the
// module builds its pino instance at load, so mocking `pino` is what lets us
// (a) observe what the DEFAULT path writes — the one the handler uses — and
// (b) capture the constructor config. Unlike those suites the mock keeps REAL
// pino serialization behind a capturing `{ write }` sink (pino calls it
// synchronously), so the assertion is on the bytes a journald row would
// carry, not on a spy's argument.
const captured = vi.hoisted(() => ({
  lines: [] as string[],
  factoryCalls: [] as unknown[][],
  warnImpl: null as null | (() => void),
}));

vi.mock("pino", async (importOriginal) => {
  // pino ships as CJS (`export =`), so the namespace's interop `default` is what
  // `import pino from "pino"` binds. Typed loosely on purpose (same seam as
  // cert-reissue-marker.test.ts).
  const actual = (await importOriginal()) as Record<string, unknown>;
  const realPino = actual.default as (o: unknown, d: unknown) => { warn: (...a: unknown[]) => void };
  const dest = {
    write: (s: string) => {
      for (const line of s.split("\n")) if (line) captured.lines.push(line);
    },
  };
  const factory = (...args: unknown[]) => {
    captured.factoryCalls.push(args);
    const real = realPino(args[0], dest);
    const warn = real.warn.bind(real);
    real.warn = (...a: unknown[]) => {
      if (captured.warnImpl) return captured.warnImpl();
      return warn(...a);
    };
    return real;
  };
  return { ...actual, default: factory };
});

import { emitOutcomeMarker } from "@/server/compound-promote-marker";

beforeEach(() => expect.hasAssertions());
afterEach(() => {
  captured.lines.length = 0;
  captured.warnImpl = null;
});

const FUNCTIONS_DIR = join(__dirname, "..", "..", "..", "server", "inngest", "functions");
const HANDLER_PATH = join(FUNCTIONS_DIR, "cron-compound-promote.ts");

/** A ctx.logger call whose FIRST object key is a `SOLEUR_*` marker (literal or computed `[X_MARKER]`). */
const CTX_LOGGER_MARKER_RE = /\blogger\.\w+\(\s*\{\s*(SOLEUR_|\[\w*MARKER)/;

/** Whole-line comment strip (cannot truncate code; `/*` inside a string is inert). */
const stripComments = (src: string) => src.replace(/^\s*(\/\/|\/?\*).*$/gm, "");

describe("SOLEUR_COMPOUND_PROMOTE_OUTCOME marker shape (#8281)", () => {
  it("the DEFAULT path — one argument, as the handler calls it — writes one single-line JSON row at WARN", () => {
    emitOutcomeMarker({
      trigger: "manual",
      run_id: "01TESTRUNID",
      status: "error",
      error_class: "AnthropicApiError",
      error_message: "Anthropic API 400",
      refusals: ["diff-path-refused"],
    });
    expect(captured.lines).toHaveLength(1);
    const row = JSON.parse(captured.lines[0]) as Record<string, unknown>;
    // 40 = pino WARN, the literal `app_container_warn_filter` gates on (>= 40).
    expect(row.level).toBe(40);
    expect(row.SOLEUR_COMPOUND_PROMOTE_OUTCOME).toBe(true);
    expect(row.fn).toBe("cron-compound-promote");
    expect(row.component).toBe("compound-promote");
    expect(row.msg).toBe("compound promote outcome");
    expect(row.trigger).toBe("manual");
    expect(row.status).toBe("error");
    expect(row.run_id).toBe("01TESTRUNID");
    expect(row.refusals_total).toBe(1);
    // No pid/hostname: `base` is overridden, matching the sibling markers.
    expect(row).not.toHaveProperty("pid");
    expect(row).not.toHaveProperty("hostname");
  });

  it("builds ONE dedicated pino instance like the sibling *-marker.ts modules: bare `pino({ base })`, no destination, no level override, no logMethod hook", () => {
    expect(captured.factoryCalls).toHaveLength(1);
    const [opts, ...rest] = captured.factoryCalls[0] as [Record<string, unknown>, ...unknown[]];
    expect(rest).toHaveLength(0);
    expect(opts).toEqual({ base: { component: "compound-promote" } });
  });

  it("is fail-open: a throwing sink never propagates into the cron", () => {
    captured.warnImpl = () => {
      throw new Error("sink exploded");
    };
    expect(() => emitOutcomeMarker({ status: "completed" })).not.toThrow();
    expect(captured.lines).toHaveLength(0);
  });

  it("wire: the handler imports the emitter from the marker module and every call passes exactly ONE argument", () => {
    const src = stripComments(readFileSync(HANDLER_PATH, "utf-8"));
    expect(src).toMatch(/^import \{[^}]*\bemitOutcomeMarker\b[^}]*\} from "@\/server\/compound-promote-marker";$/m);
    expect(src).not.toMatch(/^import pino\b/m);
    // Balance parens per call so a sink smuggled in as a SECOND argument (the
    // original defect, `emitOutcomeMarker(logger, …)`, or its mirror with the
    // sink last) is caught wherever it sits — an identifier regex on argument
    // position 1 was measured blind to the position-2 form.
    const calls: number[] = [];
    const re = /\bemitOutcomeMarker\s*\(/g;
    for (let m = re.exec(src); m; m = re.exec(src)) {
      let depth = 1;
      let topLevelCommas = 0;
      let i = m.index + m[0].length;
      for (; i < src.length && depth > 0; i++) {
        const c = src[i];
        if (c === "(" || c === "{" || c === "[") depth++;
        else if (c === ")" || c === "}" || c === "]") depth--;
        else if (c === "," && depth === 1) topLevelCommas++;
      }
      calls.push(topLevelCommas);
    }
    // Derived, not magic: the census suite pins the count of terminal returns
    // (MIN_TERMINAL_RETURNS); here only the SHAPE of each call is pinned.
    expect(calls.length).toBeGreaterThan(0);
    expect(calls.every((n) => n === 0)).toBe(true);
  });

  it("class guard: no Inngest function writes a SOLEUR_* marker object (first key) through ctx.logger", () => {
    // The class this marker's defect belongs to. Measured 2026-09-18: two
    // emitters (this one and SOLEUR_RUN_REPORT_SWEEP) rendered multi-line
    // through the console-backed ctx.logger while their runbook decodes
    // returned nothing. Every SOLEUR_* object marker goes through a
    // server/*-marker.ts pino instance; ctx.logger is for diagnostics only.
    const offenders: string[] = [];
    for (const f of readdirSync(FUNCTIONS_DIR)) {
      if (!f.endsWith(".ts") || f.endsWith(".test.ts")) continue;
      const src = stripComments(readFileSync(join(FUNCTIONS_DIR, f), "utf-8"));
      const re = new RegExp(CTX_LOGGER_MARKER_RE.source, "g");
      for (let m = re.exec(src); m; m = re.exec(src)) offenders.push(`${f}: ${m[0].trim()}`);
    }
    expect(offenders).toEqual([]);
    // Non-vacuity: both shapes the class was measured in trip the regex.
    expect(`logger.warn({ [RUN_REPORT_SWEEP_MARKER]: true, ...summary }, "x")`).toMatch(CTX_LOGGER_MARKER_RE);
    expect(`logger.warn({ SOLEUR_COMPOUND_PROMOTE_OUTCOME: true, fn }, "x")`).toMatch(CTX_LOGGER_MARKER_RE);
    expect(`log.warn({ SOLEUR_COMPOUND_PROMOTE_OUTCOME: true }, "x")`).not.toMatch(CTX_LOGGER_MARKER_RE);
  });
});
