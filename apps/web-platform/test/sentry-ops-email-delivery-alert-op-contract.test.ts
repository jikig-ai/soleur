import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the ops-email delivery-failure alert (#7989).
//
// Three Inngest crons send operator alerts through Resend. Two of them sent
// from an unverified domain and discarded the response, so the vendor refused
// every message for 111 days while the paths reported success.
//
// The repair mirrors a non-OK response through `reportSilentFallback`. That
// makes the failure QUERYABLE; it does not make it ALERTED. Review found no
// rule matched the new tags, so "the alert channel is dead again" would have
// landed in the issue stream and paged nobody — the same posture that let the
// original defect live. `sentry_alert.ops_email_delivery_failure` closes it.
//
// That rule ANDs on TWO tags, so both are load-bearing and both are pinned here.
// The `op` half is the fragile one: until #7989 the emit used the kebab spelling
// and the enclosing catch used camelCase, so a rule ANDing on `op` would have
// matched the throw path and missed every vendor rejection. A future rename in
// either artifact silently zeroes the rule's matches, which is invisible in a
// green run — this test is what turns that into a CI failure.
const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");

const OP_TAG = "notify-ops-email";
const OLD_OP_TAG = "notifyOpsEmail";

/** feature tag -> the producer that emits it. */
const PRODUCERS: Record<string, string> = {
  "cron-oauth-probe": "../server/inngest/functions/cron-oauth-probe.ts",
  "cron-github-app-drift-guard":
    "../server/inngest/functions/cron-github-app-drift-guard.ts",
  "cron-bug-fixer": "../server/inngest/functions/cron-bug-fixer.ts",
};

/** The feature list the live rule actually filters on. */
function featuresInAlertFilter(): string[] {
  const block = tf.slice(tf.indexOf('resource "sentry_alert" "ops_email_delivery_failure"'));
  const m = block.match(
    /key = "feature", match = "in", value = "([^"]+)"/,
  );
  return m ? m[1].split(",").map((s) => s.trim()).sort() : [];
}

describe("ops-email-delivery-failure alert op contract", () => {
  it("issue-alerts.tf declares the alert resource", () => {
    // apply-sentry-infra.yml plans the sentry root FULL, so declaring the
    // resource IS what applies it and deleting this block destroys the live rule.
    expect(tf).toContain(
      'resource "sentry_alert" "ops_email_delivery_failure"',
    );
  });

  it("the rule's feature list is exactly the set of ops-email producers", () => {
    // Derived from the .tf rather than restated, so the two cannot drift: a
    // producer added to one and not the other fails here rather than silently
    // sending its delivery failures to a rule that does not match them.
    expect(featuresInAlertFilter()).toEqual(Object.keys(PRODUCERS).sort());
  });

  it("the rule ANDs on the op tag", () => {
    expect(tf).toContain(
      `{ tagged_event = { key = "op", match = "eq", value = "${OP_TAG}" } }`,
    );
  });

  for (const [feature, rel] of Object.entries(PRODUCERS)) {
    describe(feature, () => {
      const producer = readFileSync(join(here, rel), "utf8");

      it("emits the feature tag the rule filters on", () => {
        expect(producer).toContain(`feature: "${feature}"`);
      });

      it("emits the op tag the rule ANDs on", () => {
        expect(producer).toContain(`op: "${OP_TAG}"`);
      });

      it("emits no ops-email failure under the superseded op spelling", () => {
        // The camelCase spelling escapes the rule entirely. `notifyOpsEmail`
        // remains a legitimate FUNCTION name here; only the quoted tag VALUE is
        // forbidden, so this cannot fire on the declaration or the call site.
        expect(producer).not.toContain(`op: "${OLD_OP_TAG}"`);
      });
    });
  }
});
