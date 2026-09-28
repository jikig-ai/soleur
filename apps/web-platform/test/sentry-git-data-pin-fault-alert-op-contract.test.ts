import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative, sep } from "node:path";
import { describe, it, expect } from "vitest";

import { GIT_DATA_PIN_FAULT_REASONS } from "@/server/git-data-pin-fault";
import { ART17_ERASURE_FEATURE, ART17_ERASURE_OP } from "@/server/account-delete";

// #8572 — cross-artifact contracts between two emitters and the rules that page on them.
//
// Guard 1: the app has exactly one writer of the `pin_fault` tag
// (server/git-data-pin-fault.ts `reportGitDataPinFault`), and
// `sentry_alert.git_data_host_key_pin_fault` routes exactly its vocabulary.
// Guard 2: `sentry_alert.art17_erasure_incomplete` routes every Art. 17 erasure outcome
// (it filters on feature+op only) and keeps re-paging while events continue.
//
// Every literal is IMPORTED from the emitter, never re-typed here, so this file cannot
// agree with itself while disagreeing with the code. Comment lines are stripped before any
// match, so a commented-out filter or trigger cannot satisfy an assertion that it is live.

const here = dirname(fileURLToPath(import.meta.url));
const appRoot = join(here, "..");
const sentryDir = join(appRoot, "infra/sentry");
const tf = readFileSync(join(sentryDir, "issue-alerts.tf"), "utf8");
// Every sentry_alert in the root: Sentry dedups identical rules at POST root-wide.
const allTf = readdirSync(sentryDir)
  .filter((f) => f.endsWith(".tf"))
  .map((f) => readFileSync(join(sentryDir, f), "utf8"))
  .join("\n");
const reference = JSON.parse(readFileSync(join(sentryDir, "alert-reference.json"), "utf8")) as Record<
  string,
  {
    enabled: boolean;
    frequency: number;
    triggerConditions: Array<{ type: string; comparison: unknown }>;
    actionFilters: Array<{
      logicType: string;
      conditions: Array<{ type: string; comparison: { key: string; match: string; value: string } }>;
      actions: Array<{ type: string; targetType: string; fallthroughType: string }>;
    }>;
  }
>;

const stripHclComments = (s: string) =>
  s
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");

function ruleBlock(address: string): string {
  const m = stripHclComments(tf).match(
    new RegExp(`resource\\s+"sentry_alert"\\s+"${address}"\\s*\\{[\\s\\S]*?\\n\\}`),
  );
  if (!m || !m[0].trim()) throw new Error(`fixture: ${address} resource block not found`);
  return m[0];
}

/** The `conditions = [ … ]` list of the rule's single action filter, one entry per line. */
function conditions(block: string): string[] {
  const m = block.match(/^\s*conditions\s*=\s*\[\n([\s\S]*?)\n\s*\]/m);
  if (!m) throw new Error("fixture: action-filter conditions not found");
  const entries = m[1]
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  if (entries.length === 0) throw new Error("fixture: zero conditions read — never a pass");
  return entries;
}

function logicTypes(block: string): string[] {
  return [...block.matchAll(/^\s*logic_type\s*=\s*"([^"]+)"/gm)].map((x) => x[1]);
}

/** Trigger entries, compared as a SET (order is not a property the rule has). */
function triggers(block: string): string[] {
  const m = block.match(/^\s*trigger_conditions\s*=\s*\[\n([\s\S]*?)\n\s*\]/m);
  if (!m) throw new Error("fixture: trigger_conditions not found");
  return m[1]
    .split("\n")
    .map((l) => l.trim().replace(/,$/, "").replace(/\s+/g, " "))
    .filter((l) => l.length > 0)
    .sort();
}

const TAGGED = (key: string) =>
  new RegExp(`^\\{ tagged_event = \\{ key = "${key}", match = "([a-z]+)", value = "([^"]+)" \\} \\},?$`);
const RE_PAGING = '{ event_frequency_count = { interval = "1h", value = 0 } }';
const TRANSITIONS = ["{ first_seen_event = {} }", "{ reappeared_event = {} }", "{ regression_event = {} }"];

function ownFrequencyIsUnique(block: string) {
  const own = block.match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
  if (!own) throw new Error("fixture: frequency_minutes not found in the rule");
  const all = [...stripHclComments(allTf).matchAll(/^\s*frequency_minutes\s*=\s*(\d+)/gm)].map((x) => x[1]);
  return { own: Number(own[1]), count: all.filter((v) => v === own[1]).length };
}

// ── Guard 1 ────────────────────────────────────────────────────────────────────────────

describe("git_data_host_key_pin_fault — emitter/rule contract (#8572, Guard 1)", () => {
  const block = () => ruleBlock("git_data_host_key_pin_fault");

  it("has exactly one condition, a pin_fault `in` filter, under `all`", () => {
    const c = conditions(block());
    expect(c).toHaveLength(1);
    const m = c[0].match(TAGGED("pin_fault"));
    if (!m) throw new Error(`fixture: the single condition is not a pin_fault tagged_event: ${c[0]}`);
    expect(m[1]).toBe("in");
    expect(logicTypes(block())).toEqual(["all"]);
  });

  it("routes exactly the emitter's vocabulary: nothing missing, nothing extra", () => {
    const m = conditions(block())[0].match(TAGGED("pin_fault"))!;
    expect(new Set(m[2].split(","))).toEqual(new Set(GIT_DATA_PIN_FAULT_REASONS));
    expect(m[2].split(",")).toHaveLength(GIT_DATA_PIN_FAULT_REASONS.length);
  });

  it("the reference entry mirrors the same set", () => {
    const ref = reference["git-data-host-key-pin-fault"];
    if (!ref) throw new Error("fixture: git-data-host-key-pin-fault missing from alert-reference.json");
    expect(ref.actionFilters).toHaveLength(1);
    expect(ref.actionFilters[0].logicType).toBe("all");
    expect(ref.actionFilters[0].conditions).toHaveLength(1);
    const cmp = ref.actionFilters[0].conditions[0].comparison;
    expect(cmp.key).toBe("pin_fault");
    expect(cmp.match).toBe("in");
    const values = cmp.value.split(",");
    expect(new Set(values)).toEqual(new Set(GIT_DATA_PIN_FAULT_REASONS));
    expect(values).toHaveLength(GIT_DATA_PIN_FAULT_REASONS.length);
  });

  it("pages on the transitions AND keeps re-paging while a fault persists", () => {
    expect(triggers(block())).toEqual([...TRANSITIONS, RE_PAGING].sort());
  });

  it("is enabled and emails a person (issue_owners → ActiveMembers, never NoOne)", () => {
    expect(block()).toMatch(/^\s*enabled\s*=\s*true/m);
    expect(block()).toMatch(
      /email\s*=\s*\{\s*target_type\s*=\s*"issue_owners"\s*,\s*fallthrough_type\s*=\s*"ActiveMembers"\s*\}/,
    );
    expect(block()).not.toMatch(/fallthrough_type\s*=\s*"NoOne"/);
  });

  it("uses a frequency_minutes no other rule uses (Sentry dedups identical rules at POST)", () => {
    const { own, count } = ownFrequencyIsUnique(block());
    expect(own).toBe(240);
    expect(count).toBe(1);
  });

  it("is attached to the web-platform issue stream", () => {
    expect(block()).toMatch(/^\s*monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]/m);
  });
});

// ── Guard 1 census: the single writer ──────────────────────────────────────────────────

/** Strip `/* … *\/` blocks (JSDoc included) and `//` line comments that start a line or follow whitespace. */
const stripTsComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/.*$/gm, "$1");

function walk(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    if (name === "node_modules" || name.startsWith(".")) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(name) && !/\.(test|spec)\.(ts|tsx)$/.test(name)) out.push(p);
  }
  return out;
}

describe("pin_fault census — one writer in the app (#8572, Guard 1)", () => {
  const files = ["server", "app", "lib"].flatMap((d) => walk(join(appRoot, d)));
  const rel = (p: string) => relative(appRoot, p).split(sep).join("/");

  it("walked the real tree (floor: the writer, and a file two directories deep)", () => {
    const visited = files.map(rel);
    expect(visited).toContain("server/git-data-pin-fault.ts");
    expect(visited.some((f) => f.split("/").length >= 4)).toBe(true);
  });

  it("only server/git-data-pin-fault.ts writes the pin_fault tag", () => {
    const writers = files
      .filter((f) => /["']?pin_fault["']?\s*:/.test(stripTsComments(readFileSync(f, "utf8"))))
      .map(rel);
    expect(writers).toEqual(["server/git-data-pin-fault.ts"]);
  });

  it("only server/git-data-replication.ts imports reportGitDataPinFault", () => {
    const importers = files
      .filter((f) => rel(f) !== "server/git-data-pin-fault.ts")
      .filter((f) => /\breportGitDataPinFault\b/.test(stripTsComments(readFileSync(f, "utf8"))))
      .map(rel);
    expect(importers).toEqual(["server/git-data-replication.ts"]);
  });
});

// ── Guard 2 ────────────────────────────────────────────────────────────────────────────

describe("art17_erasure_incomplete — stays unnarrowed and re-paging (#8572, Guard 2)", () => {
  const block = () => ruleBlock("art17_erasure_incomplete");

  it("has exactly two conditions, feature and op, both `eq` on the emitter's literals, under `all`", () => {
    const c = conditions(block());
    // Exactly two entries of ANY kind: a level filter or a narrowing erasure_outcome /
    // erasure_reason filter would drop outcomes the user is told "will be completed".
    expect(c).toHaveLength(2);
    const feature = c.map((l) => l.match(TAGGED("feature"))).find(Boolean);
    const op = c.map((l) => l.match(TAGGED("op"))).find(Boolean);
    if (!feature || !op) throw new Error(`fixture: expected feature and op filters, read: ${c.join(" | ")}`);
    expect([feature[1], feature[2]]).toEqual(["eq", ART17_ERASURE_FEATURE]);
    expect([op[1], op[2]]).toEqual(["eq", ART17_ERASURE_OP]);
    expect(logicTypes(block())).toEqual(["all"]);
  });

  it("pages on the transitions AND re-pages per event", () => {
    expect(triggers(block())).toEqual([...TRANSITIONS, RE_PAGING].sort());
  });

  it("the reference entry mirrors it", () => {
    const ref = reference["art17-erasure-incomplete"];
    if (!ref) throw new Error("fixture: art17-erasure-incomplete missing from alert-reference.json");
    expect(ref.actionFilters[0].conditions.map((c) => [c.comparison.key, c.comparison.match, c.comparison.value])).toEqual([
      ["feature", "eq", ART17_ERASURE_FEATURE],
      ["op", "eq", ART17_ERASURE_OP],
    ]);
    const efc = ref.triggerConditions.filter((t) => t.type === "event_frequency_count");
    expect(efc).toEqual([{ type: "event_frequency_count", comparison: { interval: "1h", value: 0 } }]);
    expect(ref.enabled).toBe(true);
  });

  it("is enabled and keeps its 5-minute throttle", () => {
    expect(block()).toMatch(/^\s*enabled\s*=\s*true/m);
    expect(block()).toMatch(/^\s*frequency_minutes\s*=\s*5$/m);
  });
});
