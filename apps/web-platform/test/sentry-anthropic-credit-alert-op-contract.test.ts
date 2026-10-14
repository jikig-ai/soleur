import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

import {
  ANTHROPIC_CREDIT_EXHAUSTED_FEATURE,
  ANTHROPIC_CREDIT_EXHAUSTED_OP,
} from "@/server/anthropic-credit";

// #8505 — cross-artifact contract between the credit-exhaustion emitter
// (server/anthropic-credit.ts) and the rule that routes it
// (sentry_alert.anthropic_credit_exhausted). The rule uses `logic_type = "all"`,
// so a rename of either tag on either side silently zeroes its matches. The
// literals are IMPORTED from the emitter, never re-typed here, so this file
// cannot agree with itself while disagreeing with the code.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
// Every sentry_alert in the root, not only issue-alerts.tf: the POST-time dedup is
// root-wide, and #8630 added a rule in cron-monitor-alerts.tf with the same action shape.
const sentryDir = join(here, "../infra/sentry");
const allTf = readdirSync(sentryDir)
  .filter((f) => f.endsWith(".tf"))
  .map((f) => readFileSync(join(sentryDir, f), "utf8"))
  .join("\n");

// Comment lines are STRIPPED before any match, so a commented-out filter, trigger or
// action cannot satisfy the assertion that it is live.
const stripComments = (s: string) =>
  s
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");

function ruleBlock(): string {
  const m = stripComments(tf).match(
    /resource\s+"sentry_alert"\s+"anthropic_credit_exhausted"\s*\{[\s\S]*?\n\}/,
  );
  if (!m) throw new Error("fixture: anthropic_credit_exhausted resource block not found");
  return m[0];
}

/** The value of a `tagged_event` filter, anchored on the HCL key so a comment cannot satisfy it. */
function filterValue(key: string): { match: string; value: string } {
  const re = new RegExp(
    `tagged_event\\s*=\\s*\\{\\s*key\\s*=\\s*"${key}"\\s*,\\s*match\\s*=\\s*"([a-z]+)"\\s*,\\s*value\\s*=\\s*"([^"]+)"`,
  );
  const m = ruleBlock().match(re);
  if (!m) throw new Error(`fixture: the rule's \`${key}\` filter was not found`);
  return { match: m[1], value: m[2] };
}

describe("anthropic_credit_exhausted — emitter/rule contract (#8505)", () => {
  it("the imported literals are non-empty and each appears exactly once as a filter value", () => {
    for (const lit of [ANTHROPIC_CREDIT_EXHAUSTED_FEATURE, ANTHROPIC_CREDIT_EXHAUSTED_OP]) {
      expect(lit.length).toBeGreaterThan(0);
      expect(ruleBlock().split(`value = "${lit}"`).length - 1).toBe(1);
    }
  });

  it("filters on feature and op with `eq`, joined by `all`", () => {
    expect(filterValue("feature")).toEqual({ match: "eq", value: ANTHROPIC_CREDIT_EXHAUSTED_FEATURE });
    expect(filterValue("op")).toEqual({ match: "eq", value: ANTHROPIC_CREDIT_EXHAUSTED_OP });
    expect(ruleBlock()).toMatch(/^\s*logic_type\s*=\s*"all"/m);
  });

  it("emails a person: issue_owners with an ActiveMembers fallthrough, never NoOne", () => {
    // The project has no ownership rule, so `issue_owners` alone resolves to
    // nobody; the fallthrough is what makes the email land.
    expect(ruleBlock()).toMatch(
      /email\s*=\s*\{\s*target_type\s*=\s*"issue_owners"\s*,\s*fallthrough_type\s*=\s*"ActiveMembers"\s*\}/,
    );
    expect(ruleBlock()).not.toMatch(/fallthrough_type\s*=\s*"NoOne"/);
  });

  it("pages on the first event AND keeps paging while exhaustion persists", () => {
    const block = ruleBlock();
    expect(block).toMatch(/\{\s*first_seen_event\s*=\s*\{\}\s*\}/);
    expect(block).toMatch(/\{\s*event_frequency_count\s*=\s*\{\s*interval\s*=\s*"1h"\s*,\s*value\s*=\s*0\s*\}\s*\}/);
    expect(block).toMatch(/^\s*enabled\s*=\s*true/m);
  });

  it("uses a frequency_minutes no other rule uses (Sentry dedups identical rules at POST)", () => {
    const own = ruleBlock().match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
    if (!own) throw new Error("fixture: frequency_minutes not found in the rule");
    const all = [...stripComments(allTf).matchAll(/^\s*frequency_minutes\s*=\s*(\d+)/gm)].map((x) => x[1]);
    expect(all.filter((v) => v === own[1])).toHaveLength(1);
  });

  it("is attached to the web-platform issue stream", () => {
    expect(ruleBlock()).toMatch(
      /^\s*monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]/m,
    );
  });
});
