// Corpus eval + Guard Contract rows for the untrusted-content scorer (#4671, ADR-287).
// The fixtures are synthetic, instruction-shaped DATA. They are only passed to classify().

import { describe, it, expect, vi, afterEach } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const impl = vi.hoisted(() => ({
  classify: null as null | ((t: string, s: string) => unknown),
  actual: null as null | ((t: string, s: string) => never),
}));
vi.mock("@/server/untrusted-content", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/untrusted-content")>();
  impl.actual = actual.classify as never;
  return {
    ...actual,
    classify: (t: string, s: Parameters<typeof actual.classify>[1]) =>
      impl.classify ? impl.classify(t, s) : actual.classify(t, s),
  };
});
// scripts/untrusted-content-eval.ts imports "../server/untrusted-content", which resolves to the
// same module id as "@/server/untrusted-content", so the stub above applies to it too.
import { runEval, loadCorpus, THRESHOLDS, type Fixture } from "../scripts/untrusted-content-eval";
// The REAL classifier (the module export is the stubbable proxy above).
const realClassify = (t: string, s: "web_fetch") =>
  (impl.actual as unknown as typeof import("@/server/untrusted-content").classify)(t, s);

afterEach(() => {
  impl.classify = null;
});

const SERVER_DIR = join(__dirname, "..", "server");
function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith(".ts") || p.endsWith(".tsx") ? [p] : [];
  });
}

describe("corpus eval (the measured control)", () => {
  it("meets the published thresholds on the full set AND the frozen holdout", () => {
    const r = runEval();
    expect(r.failures).toEqual([]);
    expect(r.recall).toBeGreaterThanOrEqual(0.9);
    expect(r.fpr).toBeLessThanOrEqual(0.05);
    expect(r.obviousOverride).toBeGreaterThanOrEqual(0.95);
    expect(r.holdoutRecall).toBeGreaterThanOrEqual(0.9);
  });

  it("anchors the thresholds: weakening one is a visible diff in THIS file", () => {
    expect(THRESHOLDS).toEqual({
      recall: 0.9,
      fpr: 0.05,
      obviousOverride: 0.95,
      holdoutRecall: 0.9,
      summaryRecall: 0.8,
      minAttack: 75,
      minBenign: 75,
      minHoldout: 35,
    });
  });

  it("fixture floors: >=150 fixtures, >=75 attack incl >=35 holdout, >=75 benign incl hard negatives, summary-shaped present", () => {
    const f = loadCorpus();
    expect(f.length).toBeGreaterThanOrEqual(150);
    expect(f.filter((x) => x.label === "attack").length).toBeGreaterThanOrEqual(75);
    expect(f.filter((x) => x.label === "attack" && x.holdout).length).toBeGreaterThanOrEqual(35);
    expect(f.filter((x) => x.label === "benign").length).toBeGreaterThanOrEqual(75);
    expect(f.filter((x) => x.category === "security-blog").length).toBeGreaterThanOrEqual(5);
    expect(f.filter((x) => x.summaryShaped).length).toBeGreaterThanOrEqual(5);
    expect(new Set(f.map((x) => x.id)).size).toBe(f.length);
  });

  it("the holdout is attack-only: its FPR side does not exist, so FPR is in-sample (stated in ADR-287)", () => {
    const holdout = loadCorpus().filter((x) => x.holdout);
    expect(holdout.length).toBeGreaterThan(0);
    expect(holdout.every((x) => x.label === "attack")).toBe(true);
  });

  it("every hard-negative category stays unflagged (named, not just inside the aggregate FPR)", () => {
    const hard = new Set(["security-blog", "prompt-docs", "rfc", "base64-image", "long", "code"]);
    const flagged = loadCorpus()
      .filter((x) => x.label === "benign" && hard.has(x.category))
      .filter((x) => realClassify(x.text, "web_fetch").flagged)
      .map((x) => x.id);
    expect(flagged).toEqual([]);
  });

  it("loadCorpus rejects a malformed fixture instead of silently dropping it", async () => {
    const { writeFileSync, mkdtempSync } = await import("node:fs");
    const { tmpdir } = await import("node:os");
    const dir = mkdtempSync(join(tmpdir(), "uc-corpus-"));
    const bad = join(dir, "c.json");
    writeFileSync(bad, JSON.stringify({ fixtures: [{ id: "x", label: "atack", category: "c", source: "web_fetch", holdout: false, summaryShaped: false, text: "t" }] }));
    expect(() => loadCorpus(bad)).toThrow(/malformed/);
  });

  it("harness row: an empty or deleted corpus FAILS on fixture floors (success is not fail == 0)", () => {
    expect(runEval([]).failures.join(" ")).toMatch(/attack fixtures 0/);
    const noAttacks = loadCorpus().filter((x) => x.label !== "attack");
    expect(runEval(noAttacks).failures.join(" ")).toMatch(/attack fixtures 0/);
  });

  it("must-PASS: a security article quoting the phrase and a benign email with a base64 image stay unflagged", () => {
    const f = loadCorpus();
    const quoted = f.find((x) => x.category === "security-blog" && x.text.includes("```"));
    const image = f.find((x) => x.category === "base64-image");
    expect(quoted).toBeDefined();
    expect(image).toBeDefined();
    expect(realClassify(quoted!.text, "web_fetch").flagged).toBe(false);
    expect(realClassify(image!.text, "web_fetch").flagged).toBe(false);
  });
});

describe("Guard 1 mutation rows (each edit must turn the eval RED)", () => {
  it("row 2: classify() that flags nothing", () => {
    impl.classify = () => ({ scored: true, score: 0, flagged: false, reasons: [], truncated: false });
    const r = runEval();
    expect(r.failures.join(" ")).toMatch(/(^|; )recall 0\.000/);
  });

  it("row 3: classify() that flags everything (reject-everything guard) fails on benign FPR", () => {
    impl.classify = () => ({ scored: true, score: 9, flagged: true, reasons: ["override-phrase"], truncated: false });
    const r = runEval();
    expect(r.failures.join(" ")).toMatch(/fpr/);
  });

  it("row 1: losing the override-phrase detector drops obvious-override recall below its floor", () => {
    impl.classify = (t, s) => {
      const c = realClassify(t, s as "web_fetch");
      const reasons = c.reasons.filter((x) => x !== "override-phrase");
      return { ...c, reasons, flagged: reasons.length > 0 && c.flagged };
    };
    const r = runEval();
    expect(r.failures.join(" ")).toMatch(/obvious-override recall/);
  });
});

describe("sweep sentinel + table completeness (Guard 1 rows 6, 7)", () => {
  it("no server module defines its own UNTRUSTED_CONTENT_ENVELOPE (counts ALL definitions)", () => {
    const defs = walk(SERVER_DIR).filter((p) => /\b(?:const|let|var)\s+UNTRUSTED_CONTENT_ENVELOPE\b/.test(readFileSync(p, "utf8")));
    expect(defs).toEqual([]);
  });

  it("all three MCP tool modules source their framing from the shared module", () => {
    const consumers = ["email-triage-tools.ts", "inbox-tools.ts", join("crm", "crm-tools.ts")];
    for (const c of consumers) {
      const src = readFileSync(join(SERVER_DIR, c), "utf8");
      expect(src).toMatch(/from "@\/server\/untrusted-content"/);
      // The import alone proves nothing: the module must still CALL the shared builder.
      expect(src).toMatch(/sharedUntrustedRowsResponse\("(?:email|inbox|crm)", /);
    }
  });

  it("the preamble table has an entry (containing UNTRUSTED) for every UntrustedSource", async () => {
    const { UNTRUSTED_PREAMBLES } = await import("@/server/untrusted-content");
    const sources = readFileSync(join(SERVER_DIR, "untrusted-content.ts"), "utf8").match(
      /export type UntrustedSource = ([^;]+);/,
    )?.[1];
    expect(sources).toBeDefined();
    const declared = [...sources!.matchAll(/"([a-z_]+)"/g)].map((m) => m[1]).sort();
    expect(Object.keys(UNTRUSTED_PREAMBLES).sort()).toEqual(declared);
    for (const p of Object.values(UNTRUSTED_PREAMBLES)) expect(p).toContain("UNTRUSTED");
  });
});

export type { Fixture };
