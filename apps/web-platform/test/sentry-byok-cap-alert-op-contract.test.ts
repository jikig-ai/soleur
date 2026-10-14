import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the BYOK delegation refusal slugs (#7829).
//
// WHY. This PR rewrote the entire slug-production mechanism — from
// message-substring matching on the RPC's `error` arm to a `REFUSAL_DISPATCH`
// table on its `data` arm — and nothing gated the rename. The
// `byok_cap_exceeded` rule uses `logic_type = "all"`, so a rename of either
// filter dimension on either side silently zeroes its matches. Ten sibling
// rules already have a test of this shape; this one did not.
//
// WHAT THIS DOES NOT CLAIM. Being routed is not being delivered. The rule's
// email action is `target_type = "issue_owners"` with
// `fallthrough_type = "NoOne"`, and the project has no ownership rule — so
// `issue_owners` resolves to nobody. That routing question is #7829's other
// half and is deliberately untouched here (see the standing note in
// issue-alerts.tf). This test pins the JOIN, not the delivery.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const costWriter = readFileSync(join(here, "../server/cost-writer.ts"), "utf8");

/** The `byok_cap_exceeded` resource block, so a sibling rule cannot satisfy us. */
function capRuleBlock(): string {
  const m = tf.match(/resource\s+"sentry_alert"\s+"byok_cap_exceeded"\s*\{[\s\S]*?\n\}/);
  if (!m) throw new Error("fixture: byok_cap_exceeded resource block not found");
  return m[0];
}

/** Slugs the rule filters on, parsed from its `op` tagged_event condition. */
function routedOpSlugs(): string[] {
  const m = capRuleBlock().match(
    /key\s*=\s*"op"[^}]*?value\s*=\s*"([^"]+)"/,
  );
  if (!m) throw new Error("fixture: the rule's `op` filter was not found");
  return m[1].split(",").map((s) => s.trim()).filter(Boolean);
}

describe("byok_cap_exceeded — emitter/rule op contract", () => {
  it("the rule filters on exactly the two cap slugs", () => {
    expect(routedOpSlugs().sort()).toEqual(["daily-cap-exceeded", "hourly-cap-exceeded"]);
  });

  it("every slug the rule filters on is actually emitted by cost-writer", () => {
    // The direction that matters: a rule filtering on a slug nothing emits is
    // an alert that can never fire.
    for (const slug of routedOpSlugs()) {
      expect(costWriter, `cost-writer.ts must emit op "${slug}"`).toContain(`"${slug}"`);
    }
  });

  it("the rule also filters on the feature tag the emitter sets", () => {
    expect(capRuleBlock()).toMatch(/key\s*=\s*"feature"[^}]*?value\s*=\s*"byok-delegations"/);
    expect(costWriter).toContain('feature: "byok-delegations"');
  });

  it("records which emitted slugs are UNROUTED, so the set cannot grow silently", () => {
    // Six of the eight ops this path emits match no rule at all. That is the
    // current, deliberate state — but it must be visible, not discovered later
    // by someone wondering why a fail-closed branch never surfaced. If a slug
    // leaves this list it should be because a rule now covers it.
    const knownUnrouted = [
      "revoke-past-grace",
      "consent-withdrawn",
      "expired",
      "caller-not-grantee",
      "unknown-refusal-reason",
      "unreadable-refusal-shape",
    ];
    const routed = routedOpSlugs();
    for (const slug of knownUnrouted) {
      expect(costWriter, `"${slug}" is expected to be emitted`).toContain(`"${slug}"`);
      expect(routed, `"${slug}" is documented as unrouted`).not.toContain(slug);
    }
  });
});
