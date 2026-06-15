import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the outbound-email send-failure alert (#5325
// follow-up).
//
// The `outbound-email-send-failure` Sentry issue-alert filters on
// `feature == "outbound-email"` ONLY (no `op` filter). Every event
// server/email-triage/outbound.ts emits carries that feature tag via
// `reportSilentFallback` and is operator-actionable:
//   - outbound.suppression_check / outbound.dedup_check — fail-closed DB errors
//     that silently HALT outbound sends.
//   - outbound.send_error — the Resend send failed (email never went).
//   - outbound.record_error — the email WENT OUT but the WORM `outbound_sends`
//     audit row is missing (a GDPR Art. 30 accountability gap).
// Feature-only matching covers all four and future-proofs new failure ops, the
// same rationale as workspace_sync_health.
//
// Because the match is feature-only, two things are load-bearing and pinned here
// so a regression breaks CI instead of silently zeroing the alert's matches
// (the user-reports-it-before-we-know failure mode):
//   1. The `feature` tag string itself must appear in BOTH artifacts (a rename
//      in either silently darks the alert).
//   2. The feature-only filter is SAFE ONLY IF every emit under
//      `feature: "outbound-email"` is an error-level `reportSilentFallback`. A
//      future routine `reportSilentInfo` / `warnSilentFallback` emit under the
//      same feature would over-page the founder. The reverse-guard below fails
//      closed if a non-error emit is ever added — forcing the author to either
//      change the emit level or narrow the alert to an `op` IS_IN filter.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const producer = readFileSync(
  join(here, "../server/email-triage/outbound.ts"),
  "utf8",
);

const FEATURE_TAG = "outbound-email";

describe("outbound-email-send-failure alert feature contract", () => {
  it("the feature tag appears in the outbound.ts emit sites", () => {
    expect(producer).toContain(`feature: "${FEATURE_TAG}"`);
  });

  it("the feature tag appears in the alert filter in issue-alerts.tf", () => {
    expect(tf).toContain(`value = "${FEATURE_TAG}"`);
  });

  it("issue-alerts.tf declares the outbound_email_send_failure alert resource", () => {
    expect(tf).toContain(
      'resource "sentry_issue_alert" "outbound_email_send_failure"',
    );
  });

  it("the -target wiring guards that the apply workflow creates the rule", () => {
    const wf = readFileSync(
      join(here, "../../../.github/workflows/apply-sentry-infra.yml"),
      "utf8",
    );
    expect(wf).toContain(
      "-target=sentry_issue_alert.outbound_email_send_failure",
    );
  });

  // Reverse-guard: feature-only matching is safe only while EVERY emit under
  // feature: "outbound-email" is error-level. Non-error emit helpers must not
  // carry this feature tag, or the alert would over-page on routine events.
  it("emits feature: \"outbound-email\" only via error-level reportSilentFallback", () => {
    // Every call carrying the feature tag must be a reportSilentFallback(...)
    // invocation. We assert no info/warn helper appears anywhere paired with the
    // feature in this file (the file's only emit helper is reportSilentFallback).
    expect(producer).not.toContain("reportSilentInfo");
    expect(producer).not.toContain("warnSilentFallback");
    // And the feature tag must never be introduced without the error helper
    // being imported (defense against a future refactor swapping helpers).
    expect(producer).toContain("reportSilentFallback");
  });
});
