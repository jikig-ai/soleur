import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the egress audit read-path alert (#9545 PR2), mirroring
// `sentry-egress-ghcr-deny-alert-op-contract.test.ts`.
//
// server/egress-audit-read.ts has exactly two mirror emitters, and every op is a string literal at its call site:
//   fault("op", "message", ...)                      error level, the paged class
//   warn("op", "message", ...) / onFault("op", "m")  warning level, debounced, UNPAGED
// Every op also owns its static message: Sentry groups message events by message (level and tags are not part of the
// group), so a message shared by two ops, or by a fault and a warn, would put paged events into a group the rule
// never matches.
// The Sentry rule `egress-audit-read-failure` routes the fault ops to a person. Renaming the feature or an op on
// either side, or dropping one from the filter, would dark the page while every loader test stays green (they read
// the emitted event, not the rule), so this binds the sides by DERIVING both op sets from the code, not from
// constants kept in this file:
//   * the Terraform filter's feature value equals the loader's FEATURE constant;
//   * the ops emitted through fault() equal the filter's op set, the ops emitted through warn()/onFault() are
//     disjoint from it, and no op is emitted at both levels;
//   * the two helpers are each defined once and no other code mirrors directly (reportSilentFallback,
//     mirrorWarnWithDebounce, warnSilentFallback, infoSilentFallback), so a new emitter cannot bypass the
//     classification;
//   * the number of fault( / warn( / onFault( call sites equals the number of literal-op call sites, so a computed
//     first argument cannot hide an op from the derived sets;
//   * no static message appears under two ops or at both levels;
//   * the committed alert-reference.json entry equals the filter (sentry-alert-reference-gate.sh
//     holds the committed copy equal to the plan, so a stale copy reds the PR job).
// Comments are stripped from both the loader and the .tf so a comment naming a literal cannot satisfy an
// anchor that exists to pin the CODE (cq-assert-anchor-not-bare-token).

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const read = (rel: string): string => readFileSync(join(root, rel), "utf8");
const stripHashComments = (t: string): string =>
  t
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");
// Block comments first, then line comments (whole-line or trailing). The loader holds no "//" inside a string.
const stripJsComments = (t: string): string => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/.*$/gm, "$1");

const loader = stripJsComments(read("server/egress-audit-read.ts"));
const tf = stripHashComments(read("infra/sentry/issue-alerts.tf"));
const reference = JSON.parse(read("infra/sentry/alert-reference.json")) as Record<
  string,
  {
    enabled: boolean;
    frequency: number;
    actionFilters: { logicType: string; conditions: { type: string; comparison: { key: string; match: string; value: string } }[] }[];
  }
>;

const block = (() => {
  const m = tf.match(/resource\s+"sentry_alert"\s+"egress_audit_read_failure"\s*\{[\s\S]*?\n\}\n/);
  return m ? m[0] : "";
})();

const sortedUnique = (xs: string[]): string[] => [...new Set(xs)].sort();
const PAGED = sortedUnique([...loader.matchAll(/\bfault\(\s*"([a-z_]+)"/g)].map((m) => m[1]));
const UNPAGED = sortedUnique([...loader.matchAll(/\b(warn|onFault)\(\s*"([a-z_]+)"/g)].map((m) => m[2]));
const FILTER = (block.match(/key = "op", match = "in", value = "([^"]+)"/)?.[1] ?? "").split(",").filter(Boolean).sort();

// Every emitter call site outside the two helper definitions: [kind, op, message].
const SITES = [...loader.matchAll(/\b(fault|warn|onFault)\(\s*"([a-z_]+)"\s*,\s*"([^"]+)"/g)].map((m) => ({ kind: m[1], op: m[2], message: m[3] }));

// The text of `function <name>(...) { ... }` up to its closing brace at column 0.
const helperBody = (name: string): string => loader.match(new RegExp(`function ${name}\\([\\s\\S]*?\\n\\}\\n`))?.[0] ?? "";

describe("egress-audit-read alert op contract", () => {
  it("the loader pins one feature constant, and the rule filters on exactly that value", () => {
    const feature = loader.match(/^const FEATURE = "([^"]+)";$/m)?.[1];
    expect(feature).toBe("egress-audit-read");
    expect(loader).toMatch(/export \{ FEATURE as EGRESS_AUDIT_READ_FEATURE \};/);
    expect(block).not.toBe("");
    expect(block).toContain(`{ tagged_event = { key = "feature", match = "eq", value = "${feature}" } }`);
  });

  it("the rule name is the live name (a rename destroys a live paging rule) and its frequency is distinct", () => {
    expect(block).toContain('name              = "egress-audit-read-failure"');
    const freq = block.match(/frequency_minutes\s*=\s*(\d+)/)?.[1];
    expect(freq).toBe("41");
    const all = [...tf.matchAll(/frequency_minutes\s*=\s*(\d+)/g)].map((m) => m[1]);
    expect(all.length).toBeGreaterThan(1);
    expect(all.filter((f) => f === freq)).toHaveLength(1);
  });

  it("the ops the loader emits through fault() are exactly the Terraform filter's op set", () => {
    expect(PAGED.length).toBeGreaterThan(0);
    expect(FILTER.length).toBeGreaterThan(0);
    expect(PAGED).toEqual(FILTER);
  });

  it("the ops emitted through warn()/onFault() are decorative: none is in the filter, none is also paged", () => {
    expect(UNPAGED.length).toBeGreaterThan(0);
    for (const op of UNPAGED) {
      expect(FILTER).not.toContain(op);
      expect(PAGED).not.toContain(op);
    }
  });

  it("each emitter is defined once and nothing else mirrors directly (so no emitter bypasses the classification)", () => {
    expect(loader.match(/\bfunction fault\(/g)).toHaveLength(1);
    expect(loader.match(/\bfunction warn\(/g)).toHaveLength(1);
    expect(helperBody("fault")).not.toBe("");
    expect(helperBody("warn")).not.toBe("");
    const outside = loader.replace(helperBody("fault"), "").replace(helperBody("warn"), "");
    expect(outside).not.toMatch(/\breportSilentFallback\(/);
    expect(outside).not.toMatch(/\bmirrorWarnWithDebounce\(/);
    expect(outside).not.toMatch(/\bwarnSilentFallback\(/);
    expect(outside).not.toMatch(/\binfoSilentFallback\(/);
    // ...and each helper mirrors with err = null (so each reason is its own issue group), at the level its name says.
    expect(helperBody("fault")).toMatch(/\breportSilentFallback\(null, \{ feature: FEATURE, op, message/);
    expect(helperBody("warn")).toMatch(/\bmirrorWarnWithDebounce\(null, \{ feature: FEATURE, op, message/);
  });

  it("every emitter call site passes a string-literal op and message (a computed argument cannot hide an op)", () => {
    const outside = loader.replace(helperBody("fault"), "").replace(helperBody("warn"), "");
    for (const kind of ["fault", "warn", "onFault"]) {
      const all = (outside.match(new RegExp(`\\b${kind}\\(`, "g")) ?? []).length;
      const literal = SITES.filter((s) => s.kind === kind).length;
      expect([kind, all > 0]).toEqual([kind, true]);
      expect([kind, all]).toEqual([kind, literal]);
    }
  });

  it("no static message is shared by two ops or by a paged and an unpaged emitter (Sentry groups by message)", () => {
    expect(SITES.length).toBeGreaterThan(0);
    const byMessage = new Map<string, { ops: Set<string>; levels: Set<string> }>();
    for (const s of SITES) {
      const e = byMessage.get(s.message) ?? { ops: new Set<string>(), levels: new Set<string>() };
      e.ops.add(s.op);
      e.levels.add(s.kind === "fault" ? "fault" : "warn");
      byMessage.set(s.message, e);
    }
    for (const [message, e] of byMessage) {
      expect([message, e.ops.size]).toEqual([message, 1]);
      expect([message, e.levels.size]).toEqual([message, 1]);
    }
  });

  it("the committed alert-reference.json entry equals the Terraform filter", () => {
    const r = reference["egress-audit-read-failure"];
    expect(r).toBeTruthy();
    expect(r.enabled).toBe(true);
    expect(r.frequency).toBe(41);
    const [f] = r.actionFilters;
    expect(f.logicType).toBe("all");
    const byKey = Object.fromEntries(f.conditions.map((c) => [c.comparison.key, c.comparison]));
    expect(byKey.feature).toMatchObject({ match: "eq", value: "egress-audit-read" });
    expect(byKey.op).toMatchObject({ match: "in" });
    expect(byKey.op.value.split(",").sort()).toEqual(FILTER);
  });
});
