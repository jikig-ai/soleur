import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the git-data erasure re-drive paging rules (#10914, Ref #8211).
//
// server/inngest/functions/cron-git-data-erasure-redrive.ts raises, per run:
//   reportSilentFallback (error)  tags { escalation: "20d" | "28d" }   the Art. 12(3) deadline, PAGED
//   warnSilentFallback (warning)  tags { reason: "no_erasure_progress" } fleet-wide refusal, PAGED (own rule)
//   warnSilentFallback (warning)  tags { reason: "owner_still_exists" | "live_owner_aged" }  NOT paged
//   infoSilentFallback (info)     no tags                               only on a run that claimed a row or found one pending (idle runs emit none), NOT paged
// The Sentry rules `git-data-erasure-redrive-escalation` and `git-data-erasure-redrive-no-progress` route the first
// two. Renaming the feature or a tag value on either side, or widening the filter to the feature alone (which would
// email on every 15-minute run), would dark or flood the page while every handler test stays green (they read the
// emitted event, not the rule). This binds the sides by DERIVING the tag sets from the handler source.
// Nothing in the filters reads GIT_DATA_STORE_ENABLED or an environment, so the rules are unchanged whichever way
// the ledger write is gated: ungated or gated, the same tags are emitted when a row ages out.
// Comments (whole-line AND inline, `#` and `//`) are stripped from every file before any assertion so a comment naming a
// literal cannot satisfy an anchor that exists to pin the CODE (cq-assert-anchor-not-bare-token). The rule blocks'
// structural attributes (enabled, logic_type, no count/for_each, monitor_ids, trigger list, email action) are asserted
// from the stripped .tf block itself, and the negative controls at the bottom prove the helpers fail on each mutation.

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const read = (rel: string): string => readFileSync(join(root, rel), "utf8");
// String-aware HCL comment stripper: removes `#` / `//` (to end of line) and `/* */` outside double-quoted strings, so an
// inline trailing comment cannot satisfy an assertion and a `#10914` or `https://` inside a string literal survives.
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
  // Drop the whitespace-only lines a stripped comment leaves behind and trailing blanks.
  return out
    .split("\n")
    .map((l) => l.replace(/\s+$/, ""))
    .join("\n");
};
const stripJsComments = (t: string): string => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/.*$/gm, "$1");

const handler = stripJsComments(read("server/inngest/functions/cron-git-data-erasure-redrive.ts"));
const tfRaw = read("infra/sentry/issue-alerts.tf");
const tf = stripHcl(tfRaw);
const cronAlertsTf = stripHcl(read("infra/sentry/cron-monitor-alerts.tf"));
// Every .tf in the root, comment-stripped: the frequency-uniqueness check must see a rule in ANY file.
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
    triggerConditions: { type: string }[];
  }
>;

const blockOf = (src: string, label: string): string =>
  src.match(new RegExp(`resource\\s+"sentry_alert"\\s+"${label}"\\s*\\{[\\s\\S]*?\\n\\}(?:\\n|$)`))?.[0] ?? "";
const ESC = blockOf(tf, "git_data_erasure_redrive_escalation");
const NOPROG = blockOf(tf, "git_data_erasure_redrive_no_progress");
const issueStreamId = "1213799";

// Structural assertions on ONE comment-stripped rule block, exact attributes rather than substrings. Used on the real
// .tf and, in the negative controls, on mutated copies (which must make it throw).
const squash = (t: string): string => t.replace(/\s+/g, " ").trim();
const assertRuleStructure = (stripped: string, label: string, want: { name: string; frequency: number }): void => {
  const block = blockOf(stripped, label);
  expect(block, `resource ${label} present`).not.toBe("");
  expect(block).toMatch(new RegExp(`^\\s*name\\s*=\\s*"${want.name}"\\s*$`, "m"));
  expect(block).toMatch(/^\s*enabled\s*=\s*true\s*$/m);
  expect(block).toMatch(new RegExp(`^\\s*frequency_minutes\\s*=\\s*${want.frequency}\\s*$`, "m"));
  // No meta-argument can fan the rule out, zero it, or multiply it.
  expect(block).not.toMatch(/^\s*(count|for_each)\s*=/m);
  // Exactly one detector reference, exactly the issue-stream data source.
  expect(block.match(/^\s*monitor_ids\s*=/gm)).toHaveLength(1);
  expect(block).toMatch(/^\s*monitor_ids\s*=\s*\[\s*data\.sentry_project_issue_stream_monitor\.web_platform\.id\s*\]\s*$/m);
  // The trigger list is exactly the four-trigger set (an open issue must not swallow the next escalation).
  const triggers = block.match(/^\s*trigger_conditions\s*=\s*(\[[\s\S]*?\n\s*\])/m)?.[1] ?? "";
  expect(squash(triggers)).toBe(
    '[ { first_seen_event = {} }, { reappeared_event = {} }, { regression_event = {} }, { event_frequency_count = { interval = "1h", value = 0 } }, ]',
  );
  // One action filter that requires ALL conditions (any would email on the feature alone), one email action.
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
  ["git_data_erasure_redrive_escalation", "git-data-erasure-redrive-escalation", 360],
  ["git_data_erasure_redrive_no_progress", "git-data-erasure-redrive-no-progress", 720],
] as const;
// Mutate the RAW (unstripped) tf text inside one rule block, so the stripper is exercised too. Throws when the
// pattern is absent, so a stale mutation cannot silently turn a negative control into a no-op.
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

// Handler facts, derived from source.
const FEATURE = handler.match(/^const CRON_NAME = "([^"]+)";$/m)?.[1];
const TIERS = [...(handler.match(/const tier: ([^=]+)=/)?.[1] ?? "").matchAll(/"(\d+d)"/g)].map((m) => m[1]).sort();
const REASONS = [...handler.matchAll(/tags:\s*\{\s*reason:\s*"([a-z_]+)"/g)].map((m) => m[1]);

describe("git-data erasure re-drive alert op contract", () => {
  it("the handler pins one feature constant, and both rules filter on exactly that value", () => {
    expect(FEATURE).toBe("cron-git-data-erasure-redrive");
    for (const block of [ESC, NOPROG]) {
      expect(block).not.toBe("");
      expect(filterOf(block, "feature")).toEqual({ match: "eq", value: FEATURE });
    }
  });

  it("the escalation rule's tier set equals the tiers the handler can emit, and it keys on the tag, never the feature alone", () => {
    expect(TIERS).toEqual(["20d", "28d"]);
    const f = filterOf(ESC, "escalation");
    expect(f?.match).toBe("in");
    expect((f?.value ?? "").split(",").sort()).toEqual(TIERS);
    // The tag the handler emits is the one the filter reads.
    expect(handler).toMatch(/tags:\s*\{\s*escalation:\s*tier\s*\}/);
  });

  it("the escalation tiers are emitted at ERROR level through reportSilentFallback, with err = null (one issue per tier)", () => {
    const at = handler.indexOf("tags: { escalation: tier }");
    expect(at).toBeGreaterThan(0);
    const callStart = handler.lastIndexOf("SilentFallback(", at);
    expect(handler.slice(callStart - "reportSilentFallback".length + "SilentFallback".length, callStart + "SilentFallback(null".length)).toBe(
      "reportSilentFallback(null",
    );
    // Sentry groups message events by message: the two tiers must carry different static messages.
    const msgs = [
      ...handler.matchAll(/tier === "28d"\s*\?\s*"([^"]+)"\s*:\s*"([^"]+)"/g),
    ][0];
    expect(msgs).toBeTruthy();
    expect(msgs[1]).not.toBe(msgs[2]);
  });

  it("the no-progress rule filters on the one reason the handler emits at warning level; the other reasons are not paged", () => {
    expect(filterOf(NOPROG, "reason")).toEqual({ match: "eq", value: "no_erasure_progress" });
    expect(REASONS).toContain("no_erasure_progress");
    const at = handler.indexOf('tags: { reason: "no_erasure_progress" }');
    const callStart = handler.lastIndexOf("SilentFallback(", at);
    expect(handler.slice(callStart - "warn".length, callStart + "SilentFallback".length)).toBe("warnSilentFallback");
    for (const r of REASONS.filter((x) => x !== "no_erasure_progress")) {
      expect(NOPROG).not.toContain(r);
      expect(ESC).not.toContain(r);
    }
  });

  it("the per-run info event carries no escalation or reason tag, so neither rule can match it", () => {
    const m = handler.match(/infoSilentFallback\(null, \{[\s\S]*?\n\s*\}\);/);
    expect(m).toBeTruthy();
    expect(m![0]).not.toMatch(/\btags:/);
  });

  it("neither rule reads a flag or an environment (robust to gating the ledger write on GIT_DATA_STORE_ENABLED)", () => {
    for (const block of [ESC, NOPROG]) {
      expect(block).not.toMatch(/GIT_DATA_STORE_ENABLED/);
      expect(block).not.toMatch(/key = "environment"/);
      expect(block).toContain("data.sentry_project_issue_stream_monitor.web_platform.id");
    }
  });

  it("each rule's enabled, logic_type, meta-arguments, detector reference, trigger list, email action and name are exact in the .tf block", () => {
    for (const [label, name, frequency] of RULES) assertRuleStructure(tf, label, { name, frequency });
  });

  it("the frequencies are distinct across every .tf in the root, not just issue-alerts.tf", () => {
    assertFrequenciesDistinct(rootTf, [
      [ESC, "360"],
      [NOPROG, "720"],
    ]);
  });

  it("both rules re-page per event (an open issue must not swallow the next escalation) and email ActiveMembers", () => {
    for (const block of [ESC, NOPROG]) {
      expect(block).toContain('{ event_frequency_count = { interval = "1h", value = 0 } }');
      expect(block).toContain('{ email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } }');
    }
  });

  it("the committed alert-reference.json entries equal the Terraform filters", () => {
    const want: Record<string, { freq: number; conds: Record<string, { match: string; value: string }> }> = {
      "git-data-erasure-redrive-escalation": {
        freq: 360,
        conds: { feature: { match: "eq", value: FEATURE! }, escalation: { match: "in", value: "20d,28d" } },
      },
      "git-data-erasure-redrive-no-progress": {
        freq: 720,
        conds: { feature: { match: "eq", value: FEATURE! }, reason: { match: "eq", value: "no_erasure_progress" } },
      },
    };
    for (const [name, w] of Object.entries(want)) {
      const r = reference[name];
      expect(r).toBeTruthy();
      expect(r.enabled).toBe(true);
      expect(r.frequency).toBe(w.freq);
      // Bound to the project issue stream, the same detector as art17-erasure-incomplete (known at plan time).
      expect(r.detectorIds).toEqual(reference["art17-erasure-incomplete"].detectorIds);
      expect(r.detectorIds).toEqual([issueStreamId]);
      expect(r.actionFilters).toHaveLength(1);
      const [f] = r.actionFilters;
      expect(f.logicType).toBe("all");
      expect(f.actions).toEqual([
        { fallthroughType: "ActiveMembers", targetIdentifier: null, targetType: "issue_owners", type: "email" },
      ]);
      const byKey = Object.fromEntries(f.conditions.map((c) => [c.comparison.key, c.comparison]));
      expect(Object.keys(byKey).sort()).toEqual(Object.keys(w.conds).sort());
      for (const [k, v] of Object.entries(w.conds)) expect(byKey[k]).toMatchObject(v);
      expect(r.triggerConditions.map((t) => t.type)).toEqual([
        "first_seen_event",
        "reappeared_event",
        "regression_event",
        "event_frequency_count",
      ]);
    }
  });

  // TEMPORARY TOMBSTONE: this case pins the state between PR 1 and PR 2 of the README's two-PR rule. When PR 2 moves
  // scheduled_git_data_erasure_redrive into cron_monitor_failure.monitor_ids, INVERT it (assert the monitor IS routed
  // and absent from cron_monitor_alert_unrouted) or delete it; it is not a permanent invariant.
  it("the cron monitor stays declared-unrouted until the second PR (a not-yet-existing monitor id cannot be in monitor_ids)", () => {
    const routed = cronAlertsTf.match(/monitor_ids\s*=\s*\[([\s\S]*?)\]/)?.[1] ?? "";
    expect(routed).not.toContain("scheduled_git_data_erasure_redrive");
    expect(cronAlertsTf).toMatch(/scheduled_git_data_erasure_redrive\s*=\s*"[^"]*\(#10914\)"/);
    expect(reference["cron-monitor-failure"].detectorIds.length).toBeGreaterThan(0);
  });

  it("the escalation messages name the rule that routes them and no longer claim 'no paging rule yet'", () => {
    expect(handler).toContain("git-data-erasure-redrive-escalation");
    expect(handler).not.toMatch(/no paging rule yet/);
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
      ["a trigger removed", /\n\s*\{ regression_event = \{\} \},/, ""],
      [
        "the email target changed",
        /target_type = "issue_owners"/,
        'target_type = "team"',
      ],
    ];
    for (const [label, name, frequency] of RULES) {
      it(`${label}: the unmutated copy passes`, () => {
        expect(() => assertRuleStructure(stripHcl(tfRaw), label, { name, frequency })).not.toThrow();
      });
      for (const [what, from, to] of mutations) {
        it(`${label}: ${what} is caught`, () => {
          const mutated = mutateRule(tfRaw, label, from, to);
          expect(mutated).not.toBe(tfRaw);
          expect(() => assertRuleStructure(stripHcl(mutated), label, { name, frequency })).toThrow();
        });
      }
    }

    it("a duplicate frequency in another root file is caught", () => {
      const dup = `${rootTf}\nresource "sentry_alert" "x" {\n  frequency_minutes = 360\n}\n`;
      expect(() =>
        assertFrequenciesDistinct(dup, [
          [ESC, "360"],
          [NOPROG, "720"],
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
