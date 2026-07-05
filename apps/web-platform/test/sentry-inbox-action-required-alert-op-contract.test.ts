import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the inbox action_required notify-failure alert
// (feat-severity-ranked-inbox #6007 / ADR-085).
//
// The `inbox-action-required-notify-failure` Sentry issue-alert filters on
// feature == "inbox" AND op == "notify-inbox-action-required" (op-pinned, EQUAL).
// A missed action_required inbox notification is the exact "a decision that needs
// the founder, with no notice" failure this feature prevents. The `inbox` feature
// ALSO carries non-paging ops (list, set-state, inbox-item-insert for info/
// attention), so the op filter must stay EQUAL — a feature-only match would
// over-page. Both tag strings are pinned in BOTH artifacts so a rename in either
// (which silently darks the alert — the user-reports-it-before-we-know failure
// mode) breaks CI instead.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const producer = readFileSync(join(here, "../server/notifications.ts"), "utf8");

const FEATURE_TAG = "inbox";
const OP_TAG = "notify-inbox-action-required";

describe("inbox-action-required-notify-failure alert op contract", () => {
  it("the emit site (notifications.ts) carries the feature + op tags", () => {
    expect(producer).toContain(`feature: "${FEATURE_TAG}"`);
    expect(producer).toContain(OP_TAG);
  });

  it("the alert filter in issue-alerts.tf pins both tag values (op EQUAL, not feature-only)", () => {
    expect(tf).toContain(`value = "${FEATURE_TAG}"`);
    expect(tf).toContain(`value = "${OP_TAG}"`);
  });

  it("issue-alerts.tf declares the inbox_action_required_notify_failure resource", () => {
    expect(tf).toContain(
      'resource "sentry_issue_alert" "inbox_action_required_notify_failure"',
    );
  });

  it("the -target wiring guards that the apply workflow creates the rule", () => {
    const wf = readFileSync(
      join(here, "../../../.github/workflows/apply-sentry-infra.yml"),
      "utf8",
    );
    expect(wf).toContain(
      "-target=sentry_issue_alert.inbox_action_required_notify_failure",
    );
  });
});
