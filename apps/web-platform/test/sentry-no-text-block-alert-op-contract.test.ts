import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";
import { stripComments as stripTsComments } from "./helpers/strip-comments";

// Cross-artifact contract between the Haiku "no usable answer" mirrors and the rule that
// routes them. Two call sites report `op: "no-text-block"` on the message path
// (server/domain-router.ts, server/email-triage/summarize.ts) when a Haiku 5.5 turn has no
// text block, ends at max_tokens or is refused. Before this rule nothing alerted on them,
// so a Haiku turn that spent its whole budget thinking degraded silently. The rule is a
// RATE alert, not a first-seen page: one isolated empty turn is expected noise, a run of
// them is the signal. Emit sites are DERIVED from server/ below, so a third site added
// without a rule edit turns this red. Three shapes of "third site" are closed here: any quote
// style or .tsx/.mts file, an `op` that is not a literal (the token must appear exactly as
// often as there are literal emit sites), and a caller of `noTextBlockExtra` (the helper every
// emitter builds its `extra` from) whose file has no literal emit site.

const here = dirname(fileURLToPath(import.meta.url));
const serverDir = join(here, "../server");
const sentryDir = join(here, "../infra/sentry");
const tf = readFileSync(join(sentryDir, "issue-alerts.tf"), "utf8");
const allTf = readdirSync(sentryDir)
  .filter((f) => f.endsWith(".tf"))
  .map((f) => readFileSync(join(sentryDir, f), "utf8"))
  .join("\n");

// HCL comments: whole-line `#` / `//` and block comments are stripped before any match so a
// commented-out filter, trigger or action cannot satisfy the assertion that it is live. A
// TRAILING comment on a code line is not stripped, and none of the matched shapes has one.
// TypeScript under server/ is stripped by the shared parser-based helper instead.
const stripComments = (s: string) =>
  s
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");

const SOURCE_RE = /\.(?:ts|tsx|mts)$/;
const TEST_RE = /\.(?:test|spec)\.[a-z]+$/;

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return name === "__tests__" ? [] : walk(p);
    return SOURCE_RE.test(p) && !TEST_RE.test(p) ? [p] : [];
  });
}

/** The `{ ... }` literal enclosing `index`: nearest unmatched `{` backwards, its matching `}` forwards. */
function enclosingObject(src: string, index: number): string {
  let depth = 0;
  let open = -1;
  for (let i = index - 1; i >= 0; i--) {
    if (src[i] === "}") depth++;
    else if (src[i] === "{") {
      if (depth === 0) {
        open = i;
        break;
      }
      depth--;
    }
  }
  if (open < 0) throw new Error("fixture: an op \"no-text-block\" is not inside an object literal");
  depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) return src.slice(open, i + 1);
  }
  throw new Error("fixture: unterminated object literal around an op \"no-text-block\"");
}

/** Comment-stripped source of every non-test file under server/. */
function serverSources(): { file: string; src: string }[] {
  return walk(serverDir).map((file) => ({ file, src: stripTsComments(readFileSync(file, "utf8"), file) }));
}

/** (feature, op) pairs at every literal `op: "no-text-block"` emit site under server/. */
function emitSites(): { file: string; feature: string; op: string }[] {
  const sites: { file: string; feature: string; op: string }[] = [];
  for (const { file, src } of serverSources()) {
    for (const m of src.matchAll(/\bop:\s*(["'`])no-text-block\1/g)) {
      // The feature is read from the object literal that holds this `op`, so a different
      // key order, a nearer or farther sibling object, or a missing tag cannot borrow another
      // site's feature: exactly one literal `feature:` must sit in that object.
      const obj = enclosingObject(src, m.index ?? 0);
      const feats = [...obj.matchAll(/\bfeature:\s*(["'`])([^"'`]+)\1/g)];
      if (feats.length !== 1) {
        throw new Error(`fixture: an op "no-text-block" emit in ${file} needs exactly one literal feature tag in its object, found ${feats.length}`);
      }
      sites.push({ file, feature: feats[0][2], op: "no-text-block" });
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
    expect(sites.every((s) => s.feature.length > 0)).toBe(true);
  });

  it("every occurrence of the op token is a literal emit site (no constant or indirection hides one)", () => {
    const literal = emitSites().length;
    let tokens = 0;
    const perFile: string[] = [];
    for (const { file, src } of serverSources()) {
      const n = [...src.matchAll(/no-text-block/g)].length;
      tokens += n;
      if (n > 0) perFile.push(`${file}=${n}`);
    }
    // The per-file list names the offender: a constant or a string holding the token fails here.
    expect(tokens, `token counts per file: ${perFile.join(", ")}`).toBe(literal);
  });

  it("every file that builds a no-text-block `extra` also holds a literal emit site", () => {
    const emitFiles = new Set(emitSites().map((s) => s.file));
    const callers = serverSources()
      .filter(({ src }) => [...src.matchAll(/(?<!function\s)\bnoTextBlockExtra\s*\(/g)].length > 0)
      .map(({ file }) => file);
    expect(callers.length).toBeGreaterThanOrEqual(2);
    for (const f of callers) expect(emitFiles.has(f)).toBe(true);
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
