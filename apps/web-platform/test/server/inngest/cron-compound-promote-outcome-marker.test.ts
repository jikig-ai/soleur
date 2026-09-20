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

  // -- Guard 3 (#8427): the refusal_detail sink transform -------------------
  //
  // `detail` is attacker-influenced. At two `checkDiffPaths` arms it is not
  // git's diagnosis at all but a VERBATIM MODEL-CHOSEN string, so without a
  // transform a prompt-injected proposer gets a free-text write channel into a
  // third-party processor, weekly, on every refused cluster. These rows pin the
  // transform, its ORDER, and its totality over entries.

  /** Emit one refusal row and return the parsed `refusal_detail` array. */
  const emitDetail = (
    entries: Parameters<typeof emitOutcomeMarker>[0]["refusal_detail"],
  ): Record<string, unknown>[] => {
    emitOutcomeMarker({ status: "completed", refusal_detail: entries });
    expect(captured.lines).toHaveLength(1);
    const row = JSON.parse(captured.lines[0]) as Record<string, unknown>;
    return row.refusal_detail as Record<string, unknown>[];
  };

  it("redacts credential shapes in `detail` before they reach the sink", () => {
    const out = emitDetail([
      {
        cluster_hash: "abc",
        reason: "diff-underivable-apply",
        detail: "error: cannot read ghp_0123456789012345678901234567890123456789",
      },
    ]);
    expect(out[0].detail).not.toMatch(/ghp_0123456789/);
    expect(String(out[0].detail)).toMatch(/redacted/);
  });

  it("CLASSIFIES path-shaped tokens rather than relaying them", () => {
    // The write-channel control. An allowlisted prefix is preserved (that IS
    // the diagnostic the marker owes — which corpus was targeted) and the
    // model-chosen remainder is elided.
    const out = emitDetail([
      {
        cluster_hash: "abc",
        reason: "diff-path-refused",
        detail: "plugins/soleur/skills/attacker-chosen-slug/SKILL.md",
      },
    ]);
    expect(out[0].detail).toBe("plugins/soleur/skills/[elided]");
    expect(String(out[0].detail)).not.toMatch(/attacker-chosen-slug/);
  });

  it("collapses an UNRECOGNISED path to a constant, carrying no model-chosen bytes", () => {
    const out = emitDetail([
      {
        cluster_hash: "abc",
        reason: "diff-path-refused",
        detail: "../../etc/evil-payload-the-model-picked",
      },
    ]);
    expect(out[0].detail).toBe("[unclassified-path]");
    expect(String(out[0].detail)).not.toMatch(/evil-payload/);
  });

  it("leaves NON-path stderr intact — the classification is per token, not whole-string", () => {
    const out = emitDetail([
      { cluster_hash: "abc", reason: "diff-underivable-apply", detail: "error: corrupt patch at line 3" },
    ]);
    expect(out[0].detail).toBe("error: corrupt patch at line 3");
  });

  it("caps AFTER redaction, not before", () => {
    // Order row. `redactGithubSourcedText` substitutes markers that can be
    // LONGER than what they replace, so a cap applied first can be exceeded by
    // the time the row is written. The output must respect the cap regardless.
    const long = "x".repeat(400);
    const out = emitDetail([
      { cluster_hash: "abc", reason: "diff-underivable-apply", detail: long },
    ]);
    expect(Array.from(String(out[0].detail)).length).toBeLessThanOrEqual(200);
  });

  it("the cap counts CODE POINTS and never leaves a lone surrogate", () => {
    // `.slice(0, 200)` counts UTF-16 code units and can split an astral pair.
    const out = emitDetail([
      { cluster_hash: "abc", reason: "diff-underivable-apply", detail: "\u{1F600}".repeat(300) },
    ]);
    const detail = String(out[0].detail);
    expect(Array.from(detail).length).toBeLessThanOrEqual(200);
    // A lone surrogate would survive a round-trip as U+FFFD; assert none.
    expect(detail).not.toMatch(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])/);
    expect(detail).not.toMatch(/(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/);
  });

  it("the transform is TOTAL over entries — every entry, not just the first", () => {
    // A `.map` that transformed only [0], or a loop with an early break, passes
    // a single-entry fixture. The second member is where that fails.
    const out = emitDetail([
      { cluster_hash: "a", reason: "diff-path-refused", detail: "secret/one-slug/x.md" },
      { cluster_hash: "b", reason: "diff-path-refused", detail: "secret/two-slug/y.md" },
      { cluster_hash: "c", reason: "diff-path-refused", detail: "secret/three-slug/z.md" },
    ]);
    expect(out).toHaveLength(3);
    for (const e of out) expect(e.detail).toBe("[unclassified-path]");
  });

  it("relays the diff-shape fields untouched and carries no diff body", () => {
    const out = emitDetail([
      {
        cluster_hash: "abc",
        reason: "diff-empty",
        detail: "empty or whitespace-only diff",
        diff_len: 0,
        diff_fenced: false,
        diff_header_pair: false,
        diff_hunk: false,
      },
    ]);
    expect(out[0]).toMatchObject({
      diff_len: 0,
      diff_fenced: false,
      diff_header_pair: false,
      diff_hunk: false,
    });
  });

  it("REBUILDS each entry: an unknown field is dropped, never relayed around the transform", () => {
    // The spread-vs-destructure row. `{...entry, detail: t(entry.detail)}`
    // would relay every future field — and an allowlist that decides which
    // ENTRIES pass is not an allowlist of what they CARRY.
    const rogue = {
      cluster_hash: "abc",
      reason: "diff-path-refused",
      detail: "error: nothing",
      smuggled: "model-chosen-payload",
    } as unknown as NonNullable<Parameters<typeof emitOutcomeMarker>[0]["refusal_detail"]>[number];
    const out = emitDetail([rogue]);
    expect(out[0]).not.toHaveProperty("smuggled");
    expect(JSON.stringify(out)).not.toMatch(/model-chosen-payload/);
  });

  it("the entry cap still applies, and the transform runs on the surviving entries", () => {
    const many = Array.from({ length: 30 }, (_, i) => ({
      cluster_hash: `h${i}`,
      reason: "diff-path-refused",
      detail: "unknown/slug/path.md",
    }));
    const out = emitDetail(many);
    expect(out).toHaveLength(20);
    for (const e of out) expect(e.detail).toBe("[unclassified-path]");
  });

  it("the discriminator keys survive an outcome that tries to shadow them", () => {
    // They are written AFTER the spread. Before #8427 they were before it, so a
    // widened or dynamically assembled outcome could overwrite the top-level
    // boolean every reader keys on — and TypeScript's excess-property check
    // does not fire on a spread.
    const shadowing = {
      status: "completed",
      SOLEUR_COMPOUND_PROMOTE_OUTCOME: false,
      fn: "not-the-cron",
    } as unknown as Parameters<typeof emitOutcomeMarker>[0];
    emitOutcomeMarker(shadowing);
    const row = JSON.parse(captured.lines[0]) as Record<string, unknown>;
    expect(row.SOLEUR_COMPOUND_PROMOTE_OUTCOME).toBe(true);
    expect(row.fn).toBe("cron-compound-promote");
  });

  it("the handler never passes a bare `detail` to the ctx logger", () => {
    // That logger reaches the SAME Better Stack source as the marker, and
    // `verdict.detail` is now the untruncated, unredacted, unclassified form.
    const handler = stripComments(
      readFileSync(
        join(__dirname, "..", "..", "..", "server", "inngest", "functions", "cron-compound-promote.ts"),
        "utf-8",
      ),
    );
    // Scoped to the ctx-logger CALL, not the whole file: the in-memory
    // ClusterOutcome return legitimately carries `detail: pathVerdict.detail`
    // — that value is the sink transform's INPUT, and narrowing here is what
    // keeps this row about the log line rather than about the data flow.
    const call = handler.match(/logger\.warn\([\s\S]*?"diff-path-refused"/);
    expect(call).not.toBeNull();
    expect(call?.[0]).not.toMatch(/detail:/);
    // ...and the Sentry copy goes through safeDetail.
    expect(handler).toMatch(/detail:\s*safeDetail\(pathVerdict\.detail\)/);
  });

  it("shape-scrubs error_message — the one free-text field — on the DEFAULT path", () => {
    // The instance carries no `redact` paths (sibling-marker boundary), so the
    // emitter must scrub the field itself; a mutant deleting that call must
    // red here, not in a handler harness that cannot reach the catch block.
    emitOutcomeMarker({
      status: "error",
      error_class: "Error",
      error_message:
        "git push failed: https://x-access-token:ghs_abcdefghijklmnopqrstuvwxyz0123456789@github.test/o/r for me@example.test",
    });
    expect(captured.lines).toHaveLength(1);
    const row = JSON.parse(captured.lines[0]) as Record<string, unknown>;
    const msg = String(row.error_message);
    expect(msg).not.toContain("ghs_abcdefghij");
    expect(msg).not.toContain("me@example.test");
    expect(msg).toMatch(/\[redacted-/);
    expect(msg).toContain("git push failed");
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
