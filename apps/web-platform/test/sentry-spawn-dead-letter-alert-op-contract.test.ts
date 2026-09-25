import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

import {
  PAGED_DEAD_LETTER_REASONS,
  SPAWN_DEAD_LETTER_FEATURE,
  SPAWN_DEAD_LETTER_OP,
} from "@/server/spawn-dead-letter";
import { PAGES_OPERATOR } from "@/lib/failure-reason";
import { FAILURE_REASON_COPY } from "@/components/dashboard/failure-reason-copy";

// #8719 — cross-artifact contract between the leader-loop dead-letter emitter
// (server/spawn-dead-letter.ts), the paging decision (lib/failure-reason.ts
// PAGES_OPERATOR), the founder copy that promises a notification
// (components/dashboard/failure-reason-copy.ts) and the rule that routes the event
// (sentry_alert.spawn_agent_dead_letter). The rule uses `logic_type = "all"`, so a
// rename of any filtered tag on either side silently zeroes its matches. Literals
// are IMPORTED from the emitter, never re-typed here, except the pinned paged set.

const PINNED_PAGED_REASONS = [
  "acknowledgment_persist_failed",
  "anthropic_request_rejected",
  "leader_class_disabled",
  "leader_internal_error",
  "leader_refused",
  "leader_response_truncated",
  "leader_tool_invalid",
];

const PROMISED_NOTIFICATION = [
  "anthropic_request_rejected",
  "leader_class_disabled",
  "leader_internal_error",
  "leader_refused",
  "leader_tool_invalid",
];

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
// Every .tf in the root: the POST-time dedup on frequency_minutes is root-wide.
const sentryDir = join(here, "../infra/sentry");
const allTf = readdirSync(sentryDir)
  .filter((f) => f.endsWith(".tf"))
  .map((f) => readFileSync(join(sentryDir, f), "utf8"))
  .join("\n");

// Comments are STRIPPED before any match — whole-line `#`/`//` and `/* … */`
// blocks — so a commented-out filter, trigger or action cannot satisfy the
// assertion that it is live.
const stripComments = (s: string) =>
  s
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");

function ruleBlock(): string {
  const m = stripComments(tf).match(
    /resource\s+"sentry_alert"\s+"spawn_agent_dead_letter"\s*\{[\s\S]*?\n\}/,
  );
  if (!m) throw new Error("fixture: spawn_agent_dead_letter resource block not found");
  return m[0];
}

/** Every `tagged_event` condition's key, in any attribute order. */
function taggedEventKeys(): string[] {
  return [...ruleBlock().matchAll(/tagged_event\s*=\s*\{([^}]*)\}/g)].map((m) => {
    const key = m[1].match(/\bkey\s*=\s*"([^"]+)"/);
    if (!key) throw new Error(`fixture: a tagged_event without a key: ${m[0]}`);
    return key[1];
  });
}

/** Every `tagged_event` filter on `key`, anchored on the HCL key so a comment cannot satisfy it. */
function filtersFor(key: string): { match: string; value: string }[] {
  const re = new RegExp(
    `tagged_event\\s*=\\s*\\{\\s*key\\s*=\\s*"${key}"\\s*,\\s*match\\s*=\\s*"([a-z_]+)"\\s*,\\s*value\\s*=\\s*"([^"]+)"`,
    "g",
  );
  return [...ruleBlock().matchAll(re)].map((m) => ({ match: m[1], value: m[2] }));
}

function filterValue(key: string): { match: string; value: string } {
  const found = filtersFor(key);
  if (found.length === 0) throw new Error(`fixture: the rule's \`${key}\` filter was not found`);
  // Exactly one condition per key: a second, looser condition would be ANDed in
  // silently and is never what a reviewer means.
  expect(found).toHaveLength(1);
  return found[0];
}

describe("spawn_agent_dead_letter — emitter/rule contract (#8719)", () => {
  it("the paged set is exactly the pinned reasons, derived from PAGES_OPERATOR", () => {
    expect([...PAGED_DEAD_LETTER_REASONS]).toEqual(PINNED_PAGED_REASONS);
    const fromDecision = Object.entries(PAGES_OPERATOR)
      .filter(([, pages]) => pages)
      .map(([r]) => r)
      .sort();
    expect(fromDecision).toEqual(PINNED_PAGED_REASONS);
  });

  it("has exactly three tag conditions — feature, op, reason — and nothing else ANDed in", () => {
    expect(taggedEventKeys().sort()).toEqual(["feature", "op", "reason"]);
  });

  it("filters on feature and op with `eq`, joined by `all`", () => {
    expect(filterValue("feature")).toEqual({ match: "eq", value: SPAWN_DEAD_LETTER_FEATURE });
    expect(filterValue("op")).toEqual({ match: "eq", value: SPAWN_DEAD_LETTER_OP });
    expect(ruleBlock()).toMatch(/^\s*logic_type\s*=\s*"all"/m);
    expect(ruleBlock()).not.toMatch(/logic_type\s*=\s*"any"/);
  });

  it("filters `reason` with `in` over exactly the pinned paged set, which is non-empty", () => {
    const { match, value } = filterValue("reason");
    expect(match).toBe("in");
    // Comma-separated with no spaces, like the other `in` rules.
    expect(value).not.toMatch(/\s/);
    const tfSet = value.split(",").map((s) => s.trim()).filter((s) => s.length > 0).sort();
    // A broken extraction must not compare two empty sets.
    expect(tfSet.length).toBeGreaterThan(0);
    expect(tfSet).toEqual(PINNED_PAGED_REASONS);
    const expected = [...PAGED_DEAD_LETTER_REASONS].join(",");
    expect(
      tfSet,
      `the rule's reason list must equal PAGED_DEAD_LETTER_REASONS — paste value = "${expected}", then regenerate infra/sentry/alert-reference.json (README "Adding or editing a rule")`,
    ).toEqual([...PAGED_DEAD_LETTER_REASONS]);
  });

  it("emails a person: issue_owners with an ActiveMembers fallthrough, never NoOne", () => {
    // The project has no ownership rule, so `issue_owners` alone resolves to nobody.
    expect(ruleBlock()).toMatch(
      /email\s*=\s*\{\s*target_type\s*=\s*"issue_owners"\s*,\s*fallthrough_type\s*=\s*"ActiveMembers"\s*\}/,
    );
    expect(ruleBlock()).not.toMatch(/fallthrough_type\s*=\s*"NoOne"/);
  });

  it("pages on the first event AND keeps paging while a reason persists", () => {
    const block = ruleBlock();
    const triggers = block.match(/trigger_conditions\s*=\s*\[([\s\S]*?)\n\s*\]/);
    if (!triggers) throw new Error("fixture: trigger_conditions not found in the rule");
    // One trigger per line: anchor on the line-leading `{` so a nested key
    // (`interval = …` inside event_frequency_count) is not read as a trigger.
    const kinds = [...triggers[1].matchAll(/^\s*\{\s*([a-z_]+)\s*=/gm)].map((m) => m[1]).sort();
    expect(kinds).toEqual([
      "event_frequency_count",
      "first_seen_event",
      "reappeared_event",
      "regression_event",
    ]);
    expect(block).toMatch(
      /\{\s*event_frequency_count\s*=\s*\{\s*interval\s*=\s*"1h"\s*,\s*value\s*=\s*0\s*\}\s*\}/,
    );
    expect(block).toMatch(/^\s*enabled\s*=\s*true/m);
  });

  it("uses a frequency_minutes no other rule in the root uses (Sentry dedups identical rules at POST)", () => {
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

describe("spawn dead-letter — the founder copy's promise matches the paging decision (#8719)", () => {
  it("the rows promising a notification are exactly the pinned set, and each pages", () => {
    // "notif" / "alert" / "paged" cover the ways copy can promise a human was told.
    const promised = Object.entries(FAILURE_REASON_COPY)
      .filter(([, row]) => /notif|alert|paged/i.test(row.copy))
      .map(([r]) => r)
      .sort();
    expect(promised).toEqual(PROMISED_NOTIFICATION);
    for (const r of promised) {
      expect(PAGES_OPERATOR[r as keyof typeof PAGES_OPERATOR], `${r} promises a notification`).toBe(true);
    }
  });
});
