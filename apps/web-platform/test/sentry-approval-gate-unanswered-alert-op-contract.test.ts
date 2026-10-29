import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

import { APPROVAL_OPS } from "@/server/approval/ops";

// #4672 — cross-artifact contract for the two approval-queue Sentry alerts:
//   * sentry_alert.approval_gate_unanswered   feature=approval-queue, op=gate_unanswered
//   * sentry_alert.art17_approval_anonymise_failed   feature=account-delete, op=anonymise-approval-request
//
// Both rules use `logic_type = "all"` on tag filters, so renaming a tag on either side silently zeroes the rule while
// every emitter test stays green (they read the emitted event, not the rule). This binds the sides by DERIVING the
// emitter literals from the code at test time, never from constants kept in this file:
//   * the approval feature literal is read from server/approval/ops.ts, the op literal from the APPROVAL_OPS registry;
//   * the account-delete feature/op literals are read from every emitter call site in server/account-delete.ts;
//   * the Terraform filter and the committed alert-reference.json entry equal those literals;
//   * both rules carry the event_frequency_count trigger (without it a single issue group, which is how a message
//     event with no stack trace groups, would email once ever), and distinct frequency_minutes values.
// Comments are stripped from the .tf and the sources before any match, so a comment naming a literal cannot satisfy
// an anchor that exists to pin the CODE (cq-assert-anchor-not-bare-token).

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
  actionFilters: { logicType: string; conditions: Condition[]; actions: { type: string }[] }[];
};
const reference = JSON.parse(read("infra/sentry/alert-reference.json")) as Record<string, Reference>;

function block(resource: string): string {
  const m = tf.match(new RegExp(`resource\\s+"sentry_alert"\\s+"${resource}"\\s*\\{[\\s\\S]*?\\n\\}\\n`));
  return m ? m[0] : "";
}

const tagFilter = (b: string, key: string): string | undefined =>
  b.match(new RegExp(`tagged_event\\s*=\\s*\\{\\s*key\\s*=\\s*"${key}"\\s*,\\s*match\\s*=\\s*"eq"\\s*,\\s*value\\s*=\\s*"([^"]+)"`))?.[1];

const freqOf = (b: string): string | undefined => b.match(/frequency_minutes\s*=\s*(\d+)/)?.[1];

// ---- the emitter literals, derived from the code --------------------------------------------------------------------

const opsSrc = stripJsComments(read("server/approval/ops.ts"));
const APPROVAL_FEATURE = opsSrc.match(/^const FEATURE = "([^"]+)";$/m)?.[1];
const GATE_UNANSWERED_OP = APPROVAL_OPS.gateUnanswered.op;

const deleteSrc = stripJsComments(read("server/account-delete.ts"));
// Every reportSilentFallback call in the anonymise step names its feature/op as string literals.
const ANONYMISE_SITES = [...deleteSrc.matchAll(/reportSilentFallback\([^;]*?\bfeature:\s*"([^"]+)",\s*op:\s*"(anonymise-approval-request)"/g)].map((m) => ({
  feature: m[1],
  op: m[2],
}));

const ruleGate = block("approval_gate_unanswered");
const ruleAnon = block("art17_approval_anonymise_failed");

describe("approval-gate-unanswered alert op contract", () => {
  it("the emitter's feature and op literals are derivable (a refactor that hides them fails loudly, not silently)", () => {
    expect(APPROVAL_FEATURE).toBeTruthy();
    expect(GATE_UNANSWERED_OP).toBeTruthy();
    // ...and the reporter tags every event with that feature constant.
    expect(opsSrc).toMatch(/feature:\s*FEATURE,/);
    expect(opsSrc).toMatch(/op:\s*def\.op,/);
  });

  it("the rule exists and filters on exactly the registry's feature and op", () => {
    expect(ruleGate).not.toBe("");
    expect(tagFilter(ruleGate, "feature")).toBe(APPROVAL_FEATURE);
    expect(tagFilter(ruleGate, "op")).toBe(GATE_UNANSWERED_OP);
  });

  it("gate_unanswered is the only approval op the rule routes, and it is the one the cron emits at warn level", () => {
    expect(APPROVAL_OPS.gateUnanswered.level).toBe("warn");
    const cron = stripJsComments(read("server/inngest/functions/cron-approval-expiry.ts"));
    expect(cron).toMatch(/reportApprovalOp\("gateUnanswered"/);
    // Another registry op with the routed op name would put unrelated events into the paged group.
    const same = Object.values(APPROVAL_OPS).filter((o) => o.op === GATE_UNANSWERED_OP);
    expect(same).toHaveLength(1);
    // Sentry groups message events by message: the op's message is unique across the registry.
    const msgs = Object.values(APPROVAL_OPS).filter((o) => o.message === APPROVAL_OPS.gateUnanswered.message);
    expect(msgs).toHaveLength(1);
  });

  it("re-pages per event: the three transition triggers plus event_frequency_count {1h, 0}", () => {
    expect(ruleGate).toContain("{ first_seen_event = {} }");
    expect(ruleGate).toContain("{ reappeared_event = {} }");
    expect(ruleGate).toContain("{ regression_event = {} }");
    expect(ruleGate).toContain('{ event_frequency_count = { interval = "1h", value = 0 } }');
  });

  it("the committed alert-reference.json entry equals the Terraform rule", () => {
    const r = reference["approval-gate-unanswered"];
    expect(r).toBeTruthy();
    expect(r.name).toBe("approval-gate-unanswered");
    expect(r.enabled).toBe(true);
    expect(String(r.frequency)).toBe(freqOf(ruleGate));
    expect(r.triggerLogicType).toBe("any-short");
    expect(r.triggerConditions.map((c) => c.type).sort()).toEqual(
      ["event_frequency_count", "first_seen_event", "reappeared_event", "regression_event"],
    );
    expect(r.triggerConditions.find((c) => c.type === "event_frequency_count")?.comparison).toEqual({ interval: "1h", value: 0 });
    const [f] = r.actionFilters;
    expect(f.logicType).toBe("all");
    const byKey = Object.fromEntries(f.conditions.map((c) => [c.comparison.key, c.comparison]));
    expect(byKey.feature).toMatchObject({ match: "eq", value: APPROVAL_FEATURE });
    expect(byKey.op).toMatchObject({ match: "eq", value: GATE_UNANSWERED_OP });
  });
});

describe("art17-approval-anonymise-failed alert op contract", () => {
  it("the saga mirrors BOTH failure shapes (RPC error and throw) with the same feature/op literals", () => {
    expect(ANONYMISE_SITES.length).toBeGreaterThanOrEqual(2);
    expect(new Set(ANONYMISE_SITES.map((s) => s.feature)).size).toBe(1);
    expect(new Set(ANONYMISE_SITES.map((s) => s.op)).size).toBe(1);
  });

  it("the rule exists and filters on exactly the literals the saga emits", () => {
    expect(ruleAnon).not.toBe("");
    expect(tagFilter(ruleAnon, "feature")).toBe(ANONYMISE_SITES[0].feature);
    expect(tagFilter(ruleAnon, "op")).toBe(ANONYMISE_SITES[0].op);
  });

  it("re-pages per event (a failed deletion is owed to the data subject; an open issue must not swallow the next one)", () => {
    expect(ruleAnon).toContain("{ first_seen_event = {} }");
    expect(ruleAnon).toContain("{ reappeared_event = {} }");
    expect(ruleAnon).toContain("{ regression_event = {} }");
    expect(ruleAnon).toContain('{ event_frequency_count = { interval = "1h", value = 0 } }');
  });

  it("the committed alert-reference.json entry equals the Terraform rule", () => {
    const r = reference["art17-approval-anonymise-failed"];
    expect(r).toBeTruthy();
    expect(r.name).toBe("art17-approval-anonymise-failed");
    expect(r.enabled).toBe(true);
    expect(String(r.frequency)).toBe(freqOf(ruleAnon));
    expect(r.triggerConditions.map((c) => c.type).sort()).toEqual(
      ["event_frequency_count", "first_seen_event", "reappeared_event", "regression_event"],
    );
    const [f] = r.actionFilters;
    expect(f.logicType).toBe("all");
    const byKey = Object.fromEntries(f.conditions.map((c) => [c.comparison.key, c.comparison]));
    expect(byKey.feature).toMatchObject({ match: "eq", value: ANONYMISE_SITES[0].feature });
    expect(byKey.op).toMatchObject({ match: "eq", value: ANONYMISE_SITES[0].op });
  });
});

describe("approval alerts: names and frequency_minutes", () => {
  it("each rule name is the live name (a rename destroys a live paging rule)", () => {
    expect(ruleGate).toContain('name              = "approval-gate-unanswered"');
    expect(ruleAnon).toContain('name              = "art17-approval-anonymise-failed"');
  });

  it("frequency_minutes is unique root-wide for each rule (Sentry rejects a POST-time exact duplicate)", () => {
    const all = [...allTf.matchAll(/^\s*frequency_minutes\s*=\s*(\d+)/gm)].map((m) => m[1]);
    expect(all.length).toBeGreaterThan(2);
    for (const rule of [ruleGate, ruleAnon]) {
      const f = freqOf(rule);
      expect(f).toBeTruthy();
      expect(all.filter((x) => x === f)).toHaveLength(1);
    }
    expect(freqOf(ruleGate)).not.toBe(freqOf(ruleAnon));
  });
});
