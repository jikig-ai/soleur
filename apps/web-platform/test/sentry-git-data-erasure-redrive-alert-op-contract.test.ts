import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the git-data erasure re-drive paging rules (#10914, Ref #8211).
//
// server/inngest/functions/cron-git-data-erasure-redrive.ts raises, per run:
//   reportSilentFallback (error)  tags { escalation: "20d" | "28d" }   the Art. 12(3) deadline, PAGED
//   warnSilentFallback (warning)  tags { reason: "no_erasure_progress" } fleet-wide refusal, PAGED (own rule)
//   warnSilentFallback (warning)  tags { reason: "owner_still_exists" | "live_owner_aged" }  NOT paged
//   infoSilentFallback (info)     no tags                               one per run, NOT paged
// The Sentry rules `git-data-erasure-redrive-escalation` and `git-data-erasure-redrive-no-progress` route the first
// two. Renaming the feature or a tag value on either side, or widening the filter to the feature alone (which would
// email on every 15-minute run), would dark or flood the page while every handler test stays green (they read the
// emitted event, not the rule). This binds the sides by DERIVING the tag sets from the handler source.
// Nothing in the filters reads GIT_DATA_STORE_ENABLED or an environment, so the rules are unchanged whichever way
// the ledger write is gated: ungated or gated, the same tags are emitted when a row ages out.
// Comments are stripped from both files so a comment naming a literal cannot satisfy an anchor that exists to pin
// the CODE (cq-assert-anchor-not-bare-token).

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const read = (rel: string): string => readFileSync(join(root, rel), "utf8");
const stripHashComments = (t: string): string =>
  t
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");
const stripJsComments = (t: string): string => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/.*$/gm, "$1");

const handler = stripJsComments(read("server/inngest/functions/cron-git-data-erasure-redrive.ts"));
const tf = stripHashComments(read("infra/sentry/issue-alerts.tf"));
const cronAlertsTf = stripHashComments(read("infra/sentry/cron-monitor-alerts.tf"));
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

const blockOf = (label: string): string =>
  tf.match(new RegExp(`resource\\s+"sentry_alert"\\s+"${label}"\\s*\\{[\\s\\S]*?\\n\\}\\n`))?.[0] ?? "";
const ESC = blockOf("git_data_erasure_redrive_escalation");
const NOPROG = blockOf("git_data_erasure_redrive_no_progress");
const issueStreamId = "1213799";

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

  it("the rule names are the live names and the frequencies are distinct in the root", () => {
    expect(ESC).toContain('name              = "git-data-erasure-redrive-escalation"');
    expect(NOPROG).toContain('name              = "git-data-erasure-redrive-no-progress"');
    const all = [...tf.matchAll(/frequency_minutes\s*=\s*(\d+)/g)].map((m) => m[1]);
    for (const [block, want] of [
      [ESC, "360"],
      [NOPROG, "720"],
    ] as const) {
      expect(block.match(/frequency_minutes\s*=\s*(\d+)/)?.[1]).toBe(want);
      expect(all.filter((f) => f === want)).toHaveLength(1);
    }
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
});
