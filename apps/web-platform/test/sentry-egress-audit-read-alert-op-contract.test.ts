import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the egress audit read-path alert (#9545 PR2), mirroring
// `sentry-egress-ghcr-deny-alert-op-contract.test.ts`.
//
// server/egress-audit-read.ts mirrors faults with feature=egress-audit-read and the reason in `op`.
// The Sentry rule `egress-audit-read-failure` routes three of those ops to a person. Renaming the
// feature or an op on either side, or dropping one from the filter, would dark the page while every
// loader test stays green (they read the emitted event, not the rule), so this binds the sides:
//   * the Terraform filter's feature value equals the loader's FEATURE constant;
//   * each paged op is emitted by the loader and listed in the filter, and the card-hint / collection
//     ops (warning-level, debounced, decorative) are NOT in the filter;
//   * the committed alert-reference.json entry equals the filter (sentry-alert-reference-gate.sh
//     holds the committed copy equal to the plan, so a stale copy reds the PR job).
// Whole-line `#` comments are stripped from the .tf so a comment naming a literal cannot satisfy an
// anchor that exists to pin the CODE (cq-assert-anchor-not-bare-token).

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const read = (rel: string): string => readFileSync(join(root, rel), "utf8");
const stripHashComments = (t: string): string =>
  t
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");

const loader = read("server/egress-audit-read.ts");
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

const PAGED_OPS = ["rpc_error", "rpc_timeout", "workspace_read_error"] as const;
const UNPAGED_OPS = ["hint_timeout", "hint_rpc_error", "org_read", "flag_eval"] as const;

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
    const others = [...tf.matchAll(/frequency_minutes\s*=\s*(\d+)/g)].map((m) => m[1]).filter((_, i, all) => all.length > 0);
    expect(others.filter((f) => f === freq)).toHaveLength(1);
  });

  it("the op filter lists exactly the paged ops, each emitted by the loader, and none of the decorative ones", () => {
    const filter = block.match(/key = "op", match = "in", value = "([^"]+)"/)?.[1] ?? "";
    expect(filter.split(",").sort()).toEqual([...PAGED_OPS].sort());
    for (const op of PAGED_OPS) expect(loader).toMatch(new RegExp(`"${op}"`));
    for (const op of UNPAGED_OPS) {
      expect(filter.split(",")).not.toContain(op);
      expect(loader).toMatch(new RegExp(`"${op}"`));
    }
  });

  it("faults are mirrored with err = null and a static message, so each reason is its own issue group", () => {
    expect(loader).toMatch(/reportSilentFallback\(null, \{ feature: FEATURE, op, message \}\)/);
    expect(loader).not.toMatch(/reportSilentFallback\(\s*err\b/);
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
    expect(byKey.op).toMatchObject({ match: "in", value: PAGED_OPS.join(",") });
  });
});
