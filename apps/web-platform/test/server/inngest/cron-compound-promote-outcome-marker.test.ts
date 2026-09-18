// The SOLEUR_COMPOUND_PROMOTE_OUTCOME marker must reach Better Stack as ONE
// single-line JSON row at pino WARN (40) — the shape the runbook decode, the
// #8281 follow-through probe and Vector's `app_container_warn_filter` all
// read. Before this suite it was written through Inngest's `ctx.logger`, the
// console-backed ProxyLogger the client deliberately leaves unconfigured
// (server/inngest/client.ts), so `warn(obj, msg)` rendered via util.inspect as
// MULTI-LINE text: `  SOLEUR_COMPOUND_PROMOTE_OUTCOME: true,` on one row,
// `} compound promote outcome` on another. Measured on the 2026-09-18 23:10:59Z
// manual fire (PR #8276 post-merge): the marker landed 55 s after the fire and
// every field-isolated reader reported it absent for twenty minutes. The cost
// marker that DOES decode (server/claude-cost-marker.ts) writes through a pino
// instance; this suite pins that the outcome marker does the same.
import { beforeEach, describe, expect, it, vi } from "vitest";
// The module's import graph reaches the Inngest client, which asserts
// INNGEST_SIGNING_KEY at startup outside the build phase (same preamble as
// cron-compound-promote-allowlist.test.ts).
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Writable } from "node:stream";

import {
  OUTCOME_MARKER_COMPONENT,
  createOutcomeMarkerLogger,
  emitOutcomeMarker,
  outcomeMarkerLogger,
} from "@/server/inngest/functions/cron-compound-promote";

beforeEach(() => expect.hasAssertions());

const SRC_PATH = join(
  __dirname,
  "..",
  "..",
  "..",
  "server",
  "inngest",
  "functions",
  "cron-compound-promote.ts",
);

function capture(): { lines: string[]; dest: Writable } {
  const lines: string[] = [];
  const dest = new Writable({
    write(chunk, _enc, cb) {
      for (const line of String(chunk).split("\n")) {
        if (line) lines.push(line);
      }
      cb();
    },
  });
  return { lines, dest };
}

describe("SOLEUR_COMPOUND_PROMOTE_OUTCOME marker shape (#8281)", () => {
  it("emits exactly one single-line JSON row at level 40 with the marker fields", () => {
    const { lines, dest } = capture();
    const sink = createOutcomeMarkerLogger(dest);
    emitOutcomeMarker(
      {
        trigger: "manual",
        run_id: "01TESTRUNID",
        status: "error",
        error_class: "AnthropicApiError",
        error_message: "Anthropic API 400",
        refusals: ["diff-path-refused"],
      },
      sink,
    );
    // pino writes synchronously to a Writable destination when sync:true is
    // not set only after flush; the factory pins `sync: true` so the row is
    // on the stream before this line runs.
    expect(lines).toHaveLength(1);
    const row = JSON.parse(lines[0]) as Record<string, unknown>;
    expect(row.level).toBe(40);
    expect(row.SOLEUR_COMPOUND_PROMOTE_OUTCOME).toBe(true);
    expect(row.fn).toBe("cron-compound-promote");
    expect(row.component).toBe(OUTCOME_MARKER_COMPONENT);
    expect(row.msg).toBe("compound promote outcome");
    expect(row.trigger).toBe("manual");
    expect(row.status).toBe("error");
    expect(row.run_id).toBe("01TESTRUNID");
    expect(row.refusals_total).toBe(1);
  });

  it("the default sink is a pino instance tagged with the component, not a ctx.logger", () => {
    // A pino logger carries `bindings()`; Inngest's ProxyLogger does not. The
    // component binding is what a Better Stack query scopes on.
    expect(typeof outcomeMarkerLogger.bindings).toBe("function");
    expect(outcomeMarkerLogger.bindings().component).toBe(OUTCOME_MARKER_COMPONENT);
    expect(outcomeMarkerLogger.levelVal).toBeLessThanOrEqual(40);
  });

  it("wire: no call site in the handler passes the Inngest ctx logger to the emitter", () => {
    // Comment-stripped source assertion anchored on the CALL FORM. The defect
    // was `emitOutcomeMarker(logger, {...})` with `logger` = ctx.logger; the
    // emitter now owns its sink, so the two-argument form must not survive
    // anywhere in the handler.
    const src = readFileSync(SRC_PATH, "utf-8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");
    const calls = src.match(/emitOutcomeMarker\s*\(/g) ?? [];
    expect(calls.length).toBeGreaterThanOrEqual(7);
    expect(src.match(/emitOutcomeMarker\s*\(\s*logger\b/g)).toBeNull();
    // The default sink must be constructed from pino, not from any ctx value.
    expect(src).toMatch(/const outcomeMarkerLogger\s*=\s*createOutcomeMarkerLogger\(\)/);
    expect(src).toMatch(/^import pino from "pino";$/m);
  });
});
