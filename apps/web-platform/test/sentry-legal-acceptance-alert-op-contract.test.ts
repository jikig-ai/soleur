import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";
import { LEGAL_OPS, STORE_FAILED_STAGES } from "@/server/approval/ops";

// Cross-artifact contract for the founder legal-acceptance alert rules (#12011, PR-C; plan Observability section).
//
// The web card (server/legal-acceptance/** and app/api/legal-acceptance/**) emits Sentry events tagged
// `feature=legal-acceptance` with one of these `op` values:
//   accepted           an accepted row was written (liveness signal, NOT paged)
//   decide_rejected    the decide RPC refused (reason tag: stale hash, expired, replaced, wrong user)  burst-paged
//   reauth_failed      the email code send or verify failed (provider error class tag)                 burst-paged
//   row_without_event  a legal_acceptance row exists with no recorded acknowledgement                   paged on every event
// Two Sentry rules route them: `legal-acceptance-failure-burst` (the two failure ops, 3 events in an hour) and
// `legal-acceptance-row-without-event` (the reconciliation op, re-pages per event). Renaming the feature or an op on
// either side, or widening a filter to the feature alone (which would email on every accepted row), would dark or
// flood the page while every handler test stays green (they read the emitted event, not the rule). This binds the
// sides: the op set is DERIVED from the server source, the rule blocks are asserted from the comment-stripped .tf,
// and the committed alert-reference.json entries must equal the Terraform filters.
// Comments (whole-line AND inline, `#` and `//`) are stripped from every file before any assertion so a comment naming
// a literal cannot satisfy an anchor that exists to pin the CODE (cq-assert-anchor-not-bare-token). The negative
// controls at the bottom prove the structural helper fails on each mutation.

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const read = (rel: string): string => readFileSync(join(root, rel), "utf8");

// String-aware HCL comment stripper: removes `#` / `//` (to end of line) and `/* */` outside double-quoted strings.
const stripHcl = (t: string): string => {
  let out = "";
  let inStr = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (inStr) {
      out += c;
      if (c === "\\" && i + 1 < t.length) out += t[++i];
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') {
      inStr = true;
      out += c;
    } else if (c === "#" || (c === "/" && t[i + 1] === "/")) {
      while (i < t.length && t[i] !== "\n") i++;
      out += "\n";
    } else if (c === "/" && t[i + 1] === "*") {
      const end = t.indexOf("*/", i + 2);
      i = end < 0 ? t.length : end + 1;
    } else out += c;
  }
  return out
    .split("\n")
    .map((l) => l.replace(/\s+$/, ""))
    .join("\n");
};
const stripJsComments = (t: string): string => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/.*$/gm, "$1");

// Every .ts/.tsx file under one directory, comment-stripped, joined. Tests (*.test.*) are excluded so a test literal
// cannot satisfy a source anchor.
const sourceOf = (rel: string): string => {
  const out: string[] = [];
  const walk = (dir: string): void => {
    let names: string[] = [];
    try {
      names = readdirSync(join(root, dir));
    } catch {
      return;
    }
    for (const n of names.sort()) {
      const p = `${dir}/${n}`;
      if (statSync(join(root, p)).isDirectory()) walk(p);
      else if (/\.tsx?$/.test(n) && !/\.test\.tsx?$/.test(n)) out.push(stripJsComments(read(p)));
    }
  };
  walk(rel);
  return out.join("\n");
};

const tfRaw = read("infra/sentry/issue-alerts.tf");
const tf = stripHcl(tfRaw);
const rootTf = readdirSync(join(root, "infra/sentry"))
  .filter((f) => f.endsWith(".tf"))
  .sort()
  .map((f) => stripHcl(read(`infra/sentry/${f}`)))
  .join("\n");
const reference = JSON.parse(read("infra/sentry/alert-reference.json")) as Record<
  string,
  {
    enabled: boolean;
    frequency: number;
    detectorIds: string[];
    actionFilters: {
      logicType: string;
      conditions: { type: string; comparison: { key: string; match: string; value: string } }[];
      actions: { type: string; targetType: string; fallthroughType: string }[];
    }[];
    triggerConditions: { type: string; comparison: unknown }[];
  }
>;

const blockOf = (src: string, label: string): string =>
  src.match(new RegExp(`resource\\s+"sentry_alert"\\s+"${label}"\\s*\\{[\\s\\S]*?\\n\\}(?:\\n|$)`))?.[0] ?? "";
const BURST = blockOf(tf, "legal_acceptance_failure_burst");
const ROWEV = blockOf(tf, "legal_acceptance_row_without_event");
const issueStreamId = "1213799";

const squash = (t: string): string => t.replace(/\s+/g, " ").trim();
const BURST_TRIGGERS = '[ { event_frequency_count = { interval = "1h", value = 3 } }, ]';
const ROWEV_TRIGGERS =
  '[ { first_seen_event = {} }, { reappeared_event = {} }, { regression_event = {} }, { event_frequency_count = { interval = "1h", value = 0 } }, ]';

const assertRuleStructure = (
  stripped: string,
  label: string,
  want: { name: string; frequency: number; triggers: string },
): void => {
  const block = blockOf(stripped, label);
  expect(block, `resource ${label} present`).not.toBe("");
  expect(block).toMatch(new RegExp(`^\\s*name\\s*=\\s*"${want.name}"\\s*$`, "m"));
  expect(block).toMatch(/^\s*enabled\s*=\s*true\s*$/m);
  expect(block).toMatch(new RegExp(`^\\s*frequency_minutes\\s*=\\s*${want.frequency}\\s*$`, "m"));
  expect(block).not.toMatch(/^\s*(count|for_each)\s*=/m);
  expect(block.match(/^\s*monitor_ids\s*=/gm)).toHaveLength(1);
  expect(block).toMatch(/^\s*monitor_ids\s*=\s*\[\s*data\.sentry_project_issue_stream_monitor\.web_platform\.id\s*\]\s*$/m);
  const triggers = block.match(/^\s*trigger_conditions\s*=\s*(\[[\s\S]*?\n\s*\])/m)?.[1] ?? "";
  expect(squash(triggers)).toBe(want.triggers);
  expect(block.match(/^\s*logic_type\s*=/gm)).toHaveLength(1);
  expect(block).toMatch(/^\s*logic_type\s*=\s*"all"\s*$/m);
  expect(block.match(/\bemail\s*=/g)).toHaveLength(1);
  expect(block).toMatch(
    /^\s*\{ email = \{ target_type = "issue_owners", fallthrough_type = "ActiveMembers" \} \},\s*$/m,
  );
};
const assertFrequenciesDistinct = (rootStripped: string, blocks: readonly [string, string][]): void => {
  const all = [...rootStripped.matchAll(/^\s*frequency_minutes\s*=\s*(\d+)\s*$/gm)].map((m) => m[1]);
  for (const [block, want] of blocks) {
    expect(block.match(/^\s*frequency_minutes\s*=\s*(\d+)/m)?.[1]).toBe(want);
    expect(all.filter((f) => f === want)).toHaveLength(1);
  }
};
const RULES = [
  ["legal_acceptance_failure_burst", "legal-acceptance-failure-burst", 45, BURST_TRIGGERS],
  ["legal_acceptance_row_without_event", "legal-acceptance-row-without-event", 46, ROWEV_TRIGGERS],
] as const;

const mutateRule = (raw: string, label: string, from: RegExp, to: string): string => {
  const start = raw.search(new RegExp(`resource\\s+"sentry_alert"\\s+"${label}"`));
  expect(start).toBeGreaterThanOrEqual(0);
  const head = raw.slice(0, start);
  const rest = raw.slice(start);
  expect(rest.search(from), `mutation ${from} applies`).toBeGreaterThanOrEqual(0);
  return head + rest.replace(from, to);
};

const filterOf = (block: string, key: string): { match: string; value: string } | undefined => {
  const m = block.match(new RegExp(`key = "${key}", match = "(\\w+)", value = "([^"]+)"`));
  return m ? { match: m[1], value: m[2] } : undefined;
};

// Emitter facts, derived from the server source of the web card (comment-stripped, tests excluded).
// The legal op registry is LEGAL_OPS in server/approval/ops.ts (NOT APPROVAL_OPS: the gate's ops keep another feature),
// so that file is scanned too.
const emitter = [
  sourceOf("server/legal-acceptance"),
  sourceOf("app/api/legal-acceptance"),
  stripJsComments(read("server/approval/ops.ts")),
].join("\n");

describe("legal-acceptance alert op contract", () => {
  it("the server source emits feature legal-acceptance and each paged op as a string literal", () => {
    // The tag KEY and VALUE together: a bare literal elsewhere (a path, a log label) must not satisfy this.
    expect(emitter).toMatch(/\bfeature:\s*["']legal-acceptance["']/);
    // The op KEY and VALUE together (`op: "x"` in the registry), so a stray literal elsewhere cannot satisfy it.
    for (const op of ["decide_rejected", "reauth_failed", "row_without_event", "accepted", "page_read_failed", "record_invalid", "store_failed"]) {
      expect(emitter, `op ${op} emitted`).toMatch(new RegExp(`\\bop:\\s*["']${op}["']`));
    }
    // Every emitted op is reported through the legal helper, never the gate's (which would tag feature=approval-queue).
    expect(emitter).toMatch(/\bexport function reportLegalOp\(/);
  });

  // PR-D (#12011): every emitted op is either routed by one of the two rules or named here, so a NEW op cannot ship
  // unrouted by accident. This is a plain list, not a ratchet: nothing counts it down. `record_invalid` and
  // `store_failed` page nobody until the paging-rule follow-up (#12195) lands; `accepted` is the liveness signal and
  // `page_read_failed` is recorded, not paged (both stated above).
  const UNPAGED_OPS = ["accepted", "page_read_failed", "record_invalid", "store_failed"] as const;

  // The legal op registry as written in the source (comment-stripped), and as loaded: they must be the same set, so a
  // reader that only sees one of them cannot be fooled by the other. The op value may contain any of [A-Za-z0-9_-].
  const registrySrc = stripJsComments(read("server/approval/ops.ts"));
  const legalBlock = registrySrc.slice(registrySrc.indexOf("export const LEGAL_OPS"), registrySrc.indexOf("export type LegalOpKey"));
  const derivedOps = [...legalBlock.matchAll(/\bop:\s*"([A-Za-z0-9_-]+)"/g)].map((m) => m[1]).sort();

  it("the derived op set equals LEGAL_OPS, and equals the routed ops plus the plain unpaged list (a new op must be placed in one of them)", () => {
    expect(legalBlock.length, "LEGAL_OPS block extracted").toBeGreaterThan(200);
    const actual = Object.values(LEGAL_OPS)
      .map((o) => o.op as string)
      .sort();
    expect(derivedOps, "every `op:` in the source block is a LEGAL_OPS member and vice versa").toEqual(actual);
    // Cardinality: one op literal per registry entry (an extra literal in the block would be an unregistered emission).
    expect(derivedOps).toHaveLength(Object.keys(LEGAL_OPS).length);
    const routed = [...(filterOf(BURST, "op")?.value ?? "").split(","), filterOf(ROWEV, "op")?.value ?? ""];
    expect([...routed, ...UNPAGED_OPS].sort()).toEqual(derivedOps);
    for (const op of UNPAGED_OPS) expect(routed, `${op} is not both routed and exempt`).not.toContain(op);
  });

  it("the feature tag is emitted from reportLegalOp only: no other source under server/ or app/api/ can emit a legal-acceptance event", () => {
    const FEATURE_EMISSION = /\bfeature:\s*["']legal-acceptance["']|\bLEGAL_FEATURE\b/g;
    const others: string[] = [];
    for (const dir of ["server", "app/api"]) {
      const walk = (d: string): void => {
        for (const n of readdirSync(join(root, d)).sort()) {
          const rel = `${d}/${n}`;
          if (statSync(join(root, rel)).isDirectory()) walk(rel);
          else if (/\.tsx?$/.test(n) && !/\.test\.tsx?$/.test(n) && rel !== "server/approval/ops.ts") {
            if (FEATURE_EMISSION.test(stripJsComments(read(rel)))) others.push(rel);
            FEATURE_EMISSION.lastIndex = 0;
          }
        }
      };
      walk(dir);
    }
    expect(others, "files that emit feature legal-acceptance outside reportLegalOp").toEqual([]);
    const inOps = registrySrc.match(FEATURE_EMISSION) ?? [];
    expect(inOps, "ops.ts emits the feature exactly once, inside reportLegalOp").toHaveLength(1);
    const fnStart = registrySrc.indexOf("export function reportLegalOp(");
    expect(fnStart).toBeGreaterThan(registrySrc.indexOf("export type LegalOpKey"));
    expect(registrySrc.slice(fnStart).search(FEATURE_EMISSION)).toBeGreaterThan(0);
  });

  it("every storeFailed report carries a tags.stage from the closed set (and the set is the five documented stages)", () => {
    expect([...STORE_FAILED_STAGES]).toEqual(["verify", "ack_state", "ack", "registry", "config"]);
    const files: string[] = [];
    for (const dir of ["server", "app/api"]) {
      const walk = (d: string): void => {
        for (const n of readdirSync(join(root, d)).sort()) {
          const rel = `${d}/${n}`;
          if (statSync(join(root, rel)).isDirectory()) walk(rel);
          else if (/\.tsx?$/.test(n) && !/\.test\.tsx?$/.test(n)) files.push(rel);
        }
      };
      walk(dir);
    }
    let sites = 0;
    const stages = new Set<string>();
    for (const rel of files) {
      const src = stripJsComments(read(rel));
      for (const m of src.matchAll(/reportLegalOp\(\s*"storeFailed"/g)) {
        sites++;
        // The balanced argument text of this call.
        let depth = 0;
        let i = m.index! + "reportLegalOp".length;
        const from = i;
        for (; i < src.length; i++) {
          if (src[i] === "(") depth++;
          else if (src[i] === ")" && --depth === 0) break;
        }
        const args = src.slice(from, i + 1);
        const lit = /tags:\s*\{\s*stage:\s*"([a-z_]+)"\s*\}/.exec(args);
        if (lit) {
          expect(STORE_FAILED_STAGES as readonly string[], `${rel}: stage ${lit[1]}`).toContain(lit[1]);
          stages.add(lit[1]);
        } else {
          // Shorthand `{ stage }` is allowed only where the variable is typed with the closed union in that file.
          expect(args, `${rel}: storeFailed without a stage tag`).toMatch(/tags:\s*\{\s*stage\s*\}/);
          expect(src, `${rel}: shorthand stage must be typed StoreFailedStage`).toMatch(/\bstage:\s*StoreFailedStage\b/);
        }
      }
    }
    expect(sites, "storeFailed call sites found").toBeGreaterThanOrEqual(3);
    // The literal stages used somewhere in source; the typed shorthand covers verify, ack_state and registry.
    expect([...stages].sort()).toEqual(["ack", "config"]);
  });

  it("both rules filter on exactly the emitted feature value", () => {
    for (const block of [BURST, ROWEV]) {
      expect(block).not.toBe("");
      expect(filterOf(block, "feature")).toEqual({ match: "eq", value: "legal-acceptance" });
    }
  });

  it("the burst rule pages the two failure ops and the row rule pages the reconciliation op; accepted is never matched", () => {
    const burst = filterOf(BURST, "op");
    expect(burst?.match).toBe("in");
    expect((burst?.value ?? "").split(",").sort()).toEqual(["decide_rejected", "reauth_failed"]);
    expect(filterOf(ROWEV, "op")).toEqual({ match: "eq", value: "row_without_event" });
    for (const block of [BURST, ROWEV]) expect(block).not.toMatch(/accepted/);
    // page_read_failed (a page could not read the founder's rows) is a recorded signal, not paged by either rule.
    for (const block of [BURST, ROWEV]) expect(block).not.toMatch(/page_read_failed/);
  });

  it("the burst rule counts a threshold of events (a single failure is not a page); the row rule fires on every event", () => {
    expect(squash(BURST)).toContain('{ event_frequency_count = { interval = "1h", value = 3 } }');
    expect(BURST).not.toMatch(/first_seen_event/);
    expect(squash(ROWEV)).toContain('{ event_frequency_count = { interval = "1h", value = 0 } }');
  });

  it("neither rule reads a flag or an environment, and both bind the project issue stream", () => {
    for (const block of [BURST, ROWEV]) {
      expect(block).not.toMatch(/approval-queue/);
      expect(block).not.toMatch(/key = "environment"/);
      expect(block).toContain("data.sentry_project_issue_stream_monitor.web_platform.id");
    }
  });

  it("each rule's enabled, logic_type, meta-arguments, detector reference, trigger list, email action and name are exact in the .tf block", () => {
    for (const [label, name, frequency, triggers] of RULES) assertRuleStructure(tf, label, { name, frequency, triggers });
  });

  it("the frequencies are distinct across every .tf in the root, not just issue-alerts.tf", () => {
    assertFrequenciesDistinct(rootTf, [
      [BURST, "45"],
      [ROWEV, "46"],
    ]);
  });

  it("the committed alert-reference.json entries equal the Terraform filters", () => {
    const want: Record<string, { freq: number; op: { match: string; value: string }; triggers: string[]; count: number }> = {
      "legal-acceptance-failure-burst": {
        freq: 45,
        op: { match: "in", value: "decide_rejected,reauth_failed" },
        triggers: ["event_frequency_count"],
        count: 3,
      },
      "legal-acceptance-row-without-event": {
        freq: 46,
        op: { match: "eq", value: "row_without_event" },
        triggers: ["first_seen_event", "reappeared_event", "regression_event", "event_frequency_count"],
        count: 0,
      },
    };
    for (const [name, w] of Object.entries(want)) {
      const r = reference[name];
      expect(r, `${name} in alert-reference.json`).toBeTruthy();
      expect(r.enabled).toBe(true);
      expect(r.frequency).toBe(w.freq);
      expect(r.detectorIds).toEqual(reference["art17-erasure-incomplete"].detectorIds);
      expect(r.detectorIds).toEqual([issueStreamId]);
      expect(r.actionFilters).toHaveLength(1);
      const [f] = r.actionFilters;
      expect(f.logicType).toBe("all");
      expect(f.actions).toEqual([
        { fallthroughType: "ActiveMembers", targetIdentifier: null, targetType: "issue_owners", type: "email" },
      ]);
      const byKey = Object.fromEntries(f.conditions.map((c) => [c.comparison.key, c.comparison]));
      expect(Object.keys(byKey).sort()).toEqual(["feature", "op"]);
      expect(byKey.feature).toMatchObject({ match: "eq", value: "legal-acceptance" });
      expect(byKey.op).toMatchObject(w.op);
      expect(r.triggerConditions.map((t) => t.type)).toEqual(w.triggers);
      const count = r.triggerConditions.find((t) => t.type === "event_frequency_count");
      expect(count?.comparison).toEqual({ interval: "1h", value: w.count });
    }
  });

  describe("negative controls: the structural assertions fail on each mutation of a sandbox copy of the tf text", () => {
    const mutations: [string, RegExp, string][] = [
      ['logic_type "all" -> "any"', /logic_type\s*=\s*"all"/, 'logic_type = "any"'],
      ["enabled = false", /enabled\s*=\s*true/, "enabled           = false"],
      ["count = 0", /enabled\s*=\s*true/, "enabled           = true\n  count             = 0"],
      [
        "monitor_ids = [] with the old text in an inline comment",
        /monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]/,
        "monitor_ids       = [] # monitor_ids = [data.sentry_project_issue_stream_monitor.web_platform.id]",
      ],
      ["the count trigger changed", /event_frequency_count = \{ interval = "1h", value = \d+ \}/, 'event_frequency_count = { interval = "1h", value = 99 }'],
      ["the email target changed", /target_type = "issue_owners"/, 'target_type = "team"'],
    ];
    for (const [label, name, frequency, triggers] of RULES) {
      it(`${label}: the unmutated copy passes`, () => {
        expect(() => assertRuleStructure(stripHcl(tfRaw), label, { name, frequency, triggers })).not.toThrow();
      });
      for (const [what, from, to] of mutations) {
        it(`${label}: ${what} is caught`, () => {
          const mutated = mutateRule(tfRaw, label, from, to);
          expect(mutated).not.toBe(tfRaw);
          expect(() => assertRuleStructure(stripHcl(mutated), label, { name, frequency, triggers })).toThrow();
        });
      }
    }

    it("a duplicate frequency in another root file is caught", () => {
      const dup = `${rootTf}\nresource "sentry_alert" "x" {\n  frequency_minutes = 45\n}\n`;
      expect(() =>
        assertFrequenciesDistinct(dup, [
          [BURST, "45"],
          [ROWEV, "46"],
        ]),
      ).toThrow();
    });

    it("the stripper removes inline and whole-line comments but keeps # and // inside string literals", () => {
      const out = stripHcl('a = 1 # drop\n// drop\nb = "x#y//z" // drop\n/* drop */c = 2\n');
      expect(out).toContain("a = 1");
      expect(out).toContain('b = "x#y//z"');
      expect(out).toContain("c = 2");
      expect(out).not.toMatch(/drop/);
    });
  });
});
