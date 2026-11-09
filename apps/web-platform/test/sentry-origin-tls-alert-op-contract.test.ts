import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { beforeEach, describe, it, expect } from "vitest";

// #10479 (ADR-321 items 11 and 12) — cross-artifact contract for the origin-tls paging rule:
//   * sentry_alert.origin_tls_event   ANY event tagged feature=origin_tls
//
// The rule is deliberately as wide as its emitter: its ONLY tag filter is the feature literal, so a future op (or phase or
// reason) is paged by default and the rule can never be narrower than the thing it watches. This binds the sides by
// DERIVING the feature literal from every Sentry call site in server/origin-tls.ts at test time, never from a constant kept
// in this file, and then pins: the single filter, the four re-page triggers, the email action, a root-unique
// frequency_minutes, and the committed alert-reference.json entry equal to the Terraform rule. Comments are stripped from the
// .tf and the source before any match, so a comment naming a literal cannot satisfy an anchor that pins the CODE
// (cq-assert-anchor-not-bare-token). The graceful-shutdown suppression of the unexpected-close report is pinned in
// origin-tls.test.ts and is not repeated here.

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const read = (rel: string): string => readFileSync(join(root, rel), "utf8");

const stripHashComments = (t: string): string =>
  t
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");
const stripJsComments = (t: string): string => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/.*$/gm, "$1");

const tf = stripHashComments(read("infra/sentry/issue-alerts.tf"));
// Every .tf in the root: the POST-time dedup on frequency_minutes is root-wide.
const sentryDir = join(root, "infra/sentry");
const allTf = readdirSync(sentryDir)
  .filter((f) => f.endsWith(".tf"))
  .map((f) => stripHashComments(readFileSync(join(sentryDir, f), "utf8")))
  .join("\n");

type Condition = { type: string; comparison: { key: string; match: string; value: string } };
type Reference = {
  enabled: boolean;
  frequency: number;
  name: string;
  triggerLogicType: string;
  triggerConditions: { type: string; comparison: unknown }[];
  actionFilters: {
    logicType: string;
    conditions: Condition[];
    actions: { type: string; targetType: string; fallthroughType: string }[];
  }[];
  detectorIds: string[];
};
const reference = JSON.parse(read("infra/sentry/alert-reference.json")) as Record<string, Reference>;

function block(resource: string, text: string = tf): string {
  const m = text.match(new RegExp(`resource\\s+"sentry_alert"\\s+"${resource}"\\s*\\{[\\s\\S]*?\\n\\}\\n`));
  return m ? m[0] : "";
}

/** Every `tagged_event` key in a rule block, in order (so a second filter of any kind is visible). */
const taggedKeys = (b: string): string[] => [...b.matchAll(/tagged_event\s*=\s*\{\s*key\s*=\s*"([^"]+)"/g)].map((m) => m[1]);
const tagFilter = (b: string, key: string): string | undefined =>
  b.match(new RegExp(`tagged_event\\s*=\\s*\\{\\s*key\\s*=\\s*"${key}"\\s*,\\s*match\\s*=\\s*"eq"\\s*,\\s*value\\s*=\\s*"([^"]+)"`))?.[1];
const freqOf = (b: string): string | undefined => b.match(/frequency_minutes\s*=\s*(\d+)/)?.[1];

/** How many times a frequency_minutes value is assigned across the root (1 means unique). */
const freqCount = (text: string, f: string): number =>
  [...text.matchAll(/^\s*frequency_minutes\s*=\s*(\d+)/gm)].filter((m) => m[1] === f).length;

// ---- the emitter literals, derived from the code ---------------------------------------------------------------------

const src = stripJsComments(read("server/origin-tls.ts"));
const CALL_SITES = [...src.matchAll(/\b(?:reportSilentFallback|warnSilentFallback)\(/g)].length;
const FEATURES = [...src.matchAll(/\bfeature:\s*"([^"]+)"/g)].map((m) => m[1]);
const OPS = [...src.matchAll(/\bop:\s*"([^"]+)"/g)].map((m) => m[1]);
const FEATURE = FEATURES[0];

const rule = block("origin_tls_event");

beforeEach(() => {
  expect.hasAssertions();
});

describe("origin-tls-event alert op contract", () => {
  it("the emitter's feature literal is derivable and identical at every Sentry call site", () => {
    // A refactor that hides the literals (a constant imported from elsewhere) fails loudly here instead of un-pinning the rule.
    expect(CALL_SITES).toBeGreaterThanOrEqual(7);
    expect(FEATURES).toHaveLength(CALL_SITES);
    expect(FEATURE).toBeTruthy();
    expect(new Set(FEATURES).size).toBe(1);
    // The ops are NOT pinned by the rule, but a vanished op set would mean this derivation broke.
    expect(OPS.length).toBeGreaterThanOrEqual(CALL_SITES);
    expect(OPS).toEqual(expect.arrayContaining(["listen", "load", "create", "cert_expiry"]));
  });

  it("the rule exists, is enabled, and carries the live name (a rename destroys a live paging rule)", () => {
    expect(rule).not.toBe("");
    expect(rule).toContain('name              = "origin-tls-event"');
    expect(rule).toMatch(/enabled\s*=\s*true/);
  });

  it("its ONLY tag filter is feature eq <the emitter's literal>: no op, phase or reason filter (a future op is paged by default)", () => {
    expect(taggedKeys(rule)).toEqual(["feature"]);
    expect(tagFilter(rule, "feature")).toBe(FEATURE);
  });

  it("the rule is attached to the project issue-stream monitor the siblings use, matches ALL of one condition, and carries no environment or other scope", () => {
    // monitor_ids = [] (or another monitor) leaves an enabled, correctly filtered rule attached to nothing: it would never page.
    expect(rule).toMatch(/^\s*monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]\s*$/m);
    expect(rule).toMatch(/^\s*logic_type\s*=\s*"all"\s*$/m);
    expect(rule).not.toMatch(/^\s*environment\s*=/m);
    expect(rule).toMatch(/ignore_changes\s*=\s*\[environment\]/);
    // Exactly ONE entry in the conditions list, whatever its attribute order and whatever its kind: a second condition of any
    // type (a tag in another order, a level, an attribute) would narrow the rule below its emitter.
    const conds = rule.match(/(?<![A-Za-z_])conditions\s*=\s*\[([\s\S]*?)\n\s*\]/);
    expect(conds).not.toBeNull();
    // Exact text, not a count of `{ key = {` shapes: a quoted key, a reference, merge() or concat() would slip past a count.
    expect(conds![1].replace(/\s+/g, " ").trim()).toBe(`{ tagged_event = { key = "feature", match = "eq", value = "${FEATURE}" } },`);
  });

  it("re-pages per event: the three transition triggers plus event_frequency_count {1h, 0}", () => {
    expect(rule).toContain("{ first_seen_event = {} }");
    expect(rule).toContain("{ reappeared_event = {} }");
    expect(rule).toContain("{ regression_event = {} }");
    expect(rule).toContain('{ event_frequency_count = { interval = "1h", value = 0 } }');
  });

  it("the action is an email to the issue owners with the ActiveMembers fallthrough, and nothing else", () => {
    expect(rule).toContain('{ email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } }');
    expect([...rule.matchAll(/\bactions\s*=\s*\[/g)]).toHaveLength(1);
    expect([...rule.matchAll(/\{\s*email\s*=/g)]).toHaveLength(1);
    expect(rule).not.toMatch(/\{\s*(slack|pagerduty|opsgenie|webhook|msteams|discord)\s*=/);
  });

  it("frequency_minutes is unique across the whole root (Sentry rejects a POST-time exact duplicate)", () => {
    const f = freqOf(rule);
    expect(f).toBeTruthy();
    expect(freqCount(allTf, f!)).toBe(1);
    // The root really holds many rules, so "unique" is not vacuous.
    expect([...allTf.matchAll(/^\s*frequency_minutes\s*=\s*\d+/gm)].length).toBeGreaterThan(40);
  });

  it("the committed alert-reference.json entry equals the Terraform rule", () => {
    const r = reference["origin-tls-event"];
    expect(r).toBeTruthy();
    expect(r.name).toBe("origin-tls-event");
    expect(r.enabled).toBe(true);
    expect(String(r.frequency)).toBe(freqOf(rule));
    expect(r.triggerLogicType).toBe("any-short");
    expect(r.triggerConditions.map((c) => c.type).sort()).toEqual(
      ["event_frequency_count", "first_seen_event", "reappeared_event", "regression_event"],
    );
    expect(r.triggerConditions.find((c) => c.type === "event_frequency_count")?.comparison).toEqual({ interval: "1h", value: 0 });
    expect(r.actionFilters).toHaveLength(1);
    const [f] = r.actionFilters;
    expect(f.logicType).toBe("all");
    expect(f.conditions).toHaveLength(1);
    expect(f.conditions[0]).toMatchObject({ type: "tagged_event", comparison: { key: "feature", match: "eq", value: FEATURE } });
    expect(f.actions).toEqual([
      expect.objectContaining({ type: "email", targetType: "issue_owners", fallthroughType: "ActiveMembers" }),
    ]);
    expect(r.detectorIds).toHaveLength(1);
  });

  it("no emit site interpolates a caught error's message into the event (the Sentry message stays low-cardinality and static)", () => {
    // The cert_expiry path passes an Error object whose own message is a static literal; interpolating a runtime message
    // would split one issue group into many and defeat the per-issue 47-minute throttle.
    expect(src).not.toMatch(/message:\s*`[^`]*\$\{[^}]*\.message[^}]*\}/);
    expect(src).not.toMatch(/new Error\(`[^`]*\$\{/);
  });
});

// ---- the helpers must be able to fail (a helper that cannot report is indistinguishable from one that passed) -------------

describe("origin-tls-event alert op contract: negative controls", () => {
  const withOp = rule.replace(
    /conditions = \[/,
    'conditions = [\n        { tagged_event = { key = "op", match = "eq", value = "listen" } },',
  );

  it("an op filter added to the rule is visible to the single-filter assertion", () => {
    expect(withOp).not.toBe(rule);
    expect(taggedKeys(withOp)).toEqual(["op", "feature"]);
    expect(taggedKeys(withOp)).not.toEqual(["feature"]);
  });

  it("a duplicated frequency_minutes is counted as a duplicate", () => {
    const f = freqOf(rule)!;
    expect(freqCount(`${allTf}\n  frequency_minutes = ${f}\n`, f)).toBe(2);
  });

  it("the block extractor returns nothing for an unknown label (an empty match can never be read as green)", () => {
    expect(block("origin_tls_event_renamed")).toBe("");
  });

  it("triggers in a different order with an extra comment line still satisfy the (order-free) trigger assertions", () => {
    const reordered = stripHashComments(
      rule
        .replace("{ first_seen_event = {} },", "# a comment\n    { regression_event = {} },")
        .replace("{ regression_event = {} },\n    { event_frequency_count", "{ first_seen_event = {} },\n    { event_frequency_count"),
    );
    expect(reordered).toContain("{ first_seen_event = {} }");
    expect(reordered).toContain("{ regression_event = {} }");
    expect(reordered).toContain("{ reappeared_event = {} }");
  });
});
