import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract between the Haiku "no usable answer" mirrors and the rule that
// routes them. Two call sites report `op: "no-text-block"` on the message path
// (server/domain-router.ts, server/email-triage/summarize.ts) when a Haiku 5.5 turn has no
// text block, ends at max_tokens or is refused. Before this rule nothing alerted on them,
// so a Haiku turn that spent its whole budget thinking degraded silently. The rule is a
// RATE alert, not a first-seen page: one isolated empty turn is expected noise, a run of
// them is the signal. Emit sites are DERIVED from server/ below, never hard-coded, so a
// third site added without a rule edit turns this red.

const here = dirname(fileURLToPath(import.meta.url));
const serverDir = join(here, "../server");
const sentryDir = join(here, "../infra/sentry");
const tf = readFileSync(join(sentryDir, "issue-alerts.tf"), "utf8");
const allTf = readdirSync(sentryDir)
  .filter((f) => f.endsWith(".tf"))
  .map((f) => readFileSync(join(sentryDir, f), "utf8"))
  .join("\n");

// Comments are stripped before any match so a commented-out filter, trigger or action
// cannot satisfy the assertion that it is live.
const stripComments = (s: string) =>
  s
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith(".ts") ? [p] : [];
  });
}

/** (feature, op) pairs at every `op: "no-text-block"` emit site under server/. */
function emitSites(): { file: string; feature: string; op: string }[] {
  const sites: { file: string; feature: string; op: string }[] = [];
  for (const file of walk(serverDir)) {
    const src = stripComments(readFileSync(file, "utf8"));
    for (const m of src.matchAll(/\bop:\s*"no-text-block"/g)) {
      // The emit object lists `feature` before `op`; the nearest preceding `feature:` is
      // this site's (the objects are small and un-nested up to `op`).
      const before = src.slice(Math.max(0, (m.index ?? 0) - 400), m.index);
      const feats = [...before.matchAll(/\bfeature:\s*"([^"]+)"/g)];
      if (feats.length === 0) {
        throw new Error(`fixture: an op "no-text-block" emit in ${file} has no feature tag before it`);
      }
      sites.push({ file, feature: feats[feats.length - 1][1], op: "no-text-block" });
    }
  }
  return sites;
}

function ruleBlock(): string {
  const m = stripComments(tf).match(
    /resource\s+"sentry_alert"\s+"haiku_no_text_block_rate"\s*\{[\s\S]*?\n\}/,
  );
  if (!m) throw new Error("fixture: haiku_no_text_block_rate resource block not found in issue-alerts.tf");
  return m[0];
}

/** Every tagged_event filter on `key`, anchored on the HCL key so a comment cannot satisfy it. */
function filtersFor(key: string): { match: string; value: string }[] {
  const re = new RegExp(
    `tagged_event\\s*=\\s*\\{\\s*key\\s*=\\s*"${key}"\\s*,\\s*match\\s*=\\s*"([a-z_]+)"\\s*,\\s*value\\s*=\\s*"([^"]+)"`,
    "g",
  );
  return [...ruleBlock().matchAll(re)].map((m) => ({ match: m[1], value: m[2] }));
}

function onlyFilter(key: string): { match: string; value: string } {
  const found = filtersFor(key);
  if (found.length === 0) throw new Error(`fixture: the rule's \`${key}\` filter was not found`);
  // One condition per key: a second, looser one would be ANDed in silently.
  expect(found).toHaveLength(1);
  return found[0];
}

describe("haiku_no_text_block_rate — emitter/rule contract", () => {
  it("finds the no-text-block emit sites by scanning server/, and there are at least two", () => {
    const sites = emitSites();
    // A broken scan must not compare an empty set to an empty set.
    expect(sites.length).toBeGreaterThanOrEqual(2);
    expect(new Set(sites.map((s) => s.feature))).toEqual(new Set(["domain-router", "email-triage"]));
  });

  it("filters op with `eq` and feature with `in`, and the feature list covers every emit site exactly", () => {
    const sites = emitSites();
    const op = onlyFilter("op");
    expect(op).toEqual({ match: "eq", value: "no-text-block" });
    for (const s of sites) expect(s.op).toBe(op.value);

    const feature = onlyFilter("feature");
    expect(feature.match).toBe("in");
    // Comma-separated with no spaces, like the other `in` rules.
    expect(feature.value).not.toMatch(/\s/);
    const tfSet = feature.value.split(",").filter((s) => s.length > 0).sort();
    expect(tfSet.length).toBeGreaterThan(0);
    // Equal, not a superset: a feature the rule lists but nothing emits is dead weight, and
    // an emitter the rule omits is the silent gap this contract exists to close.
    expect(tfSet).toEqual([...new Set(sites.map((s) => s.feature))].sort());
  });

  it("has exactly two tag conditions — feature and op — joined by `all`", () => {
    const keys = [...ruleBlock().matchAll(/tagged_event\s*=\s*\{([^}]*)\}/g)].map((m) => {
      const k = m[1].match(/\bkey\s*=\s*"([^"]+)"/);
      if (!k) throw new Error(`fixture: a tagged_event without a key: ${m[0]}`);
      return k[1];
    });
    expect(keys.sort()).toEqual(["feature", "op"]);
    expect(ruleBlock()).toMatch(/^\s*logic_type\s*=\s*"all"/m);
    expect(ruleBlock()).not.toMatch(/logic_type\s*=\s*"any"/);
  });

  it("triggers on a RATE (event_frequency_count, value of at least 1), never on first-seen", () => {
    const block = ruleBlock();
    const triggers = block.match(/trigger_conditions\s*=\s*\[([\s\S]*?)\n\s*\]/);
    if (!triggers) throw new Error("fixture: trigger_conditions not found in the rule");
    const kinds = [...triggers[1].matchAll(/^\s*\{\s*([a-z_]+)\s*=/gm)].map((m) => m[1]);
    // A first-seen/regression/reappeared trigger would page on one isolated empty turn.
    expect(kinds).toEqual(["event_frequency_count"]);
    const value = triggers[1].match(
      /event_frequency_count\s*=\s*\{\s*interval\s*=\s*"[0-9]+[mhd]"\s*,\s*value\s*=\s*(\d+)\s*\}/,
    );
    if (!value) throw new Error("fixture: event_frequency_count interval/value not parseable");
    expect(Number(value[1])).toBeGreaterThanOrEqual(1);
    expect(block).toMatch(/^\s*enabled\s*=\s*true/m);
  });

  it("emails a person: issue_owners with an ActiveMembers fallthrough, never NoOne", () => {
    // The project has no ownership rule, so `issue_owners` alone resolves to nobody.
    expect(ruleBlock()).toMatch(
      /email\s*=\s*\{\s*target_type\s*=\s*"issue_owners"\s*,\s*fallthrough_type\s*=\s*"ActiveMembers"\s*\}/,
    );
    expect(ruleBlock()).not.toMatch(/fallthrough_type\s*=\s*"NoOne"/);
  });

  it("uses a frequency_minutes no other rule in the root uses (Sentry dedups identical rules at POST)", () => {
    const own = ruleBlock().match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
    if (!own) throw new Error("fixture: frequency_minutes not found in the rule");
    const all = [...stripComments(allTf).matchAll(/^\s*frequency_minutes\s*=\s*(\d+)/gm)].map((x) => x[1]);
    expect(all.filter((v) => v === own[1])).toHaveLength(1);
  });

  it("is attached to the web-platform issue stream and ignores drift only on environment", () => {
    expect(ruleBlock()).toMatch(
      /^\s*monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]/m,
    );
    expect(ruleBlock()).toMatch(/ignore_changes\s*=\s*\[environment\]/);
  });
});
