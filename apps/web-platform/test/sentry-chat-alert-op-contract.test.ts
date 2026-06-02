import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#4849, SpecFlow P1 + Kieran P2).
//
// The `chat-message-save-failure` Sentry issue-alert filters on
// `feature == "cc-dispatcher"` AND `op IS_IN` the three interactive-message
// insert-failure slugs. Because the alert uses `filter_match = "all"`, a rename
// of the `feature` tag OR any op slug on EITHER side (the emit site in
// cc-dispatcher.ts, or the filter value in issue-alerts.tf) would silently
// zero the alert's matches — recreating the original 3-week-silent outage one
// rename later. This test pins both filter dimensions against that drift.
//
// Substring match only (code-simplicity): `persist-user-message` lives at the
// CC_OP_SLUGS const definition (cc-dispatcher.ts:292), NOT at the emit site
// (:1502, which references the constant) — a whole-file match finds it. The
// two siblings are inline string literals at :1457 / :1477. No TS const/AST
// resolution required.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(
  join(here, "../infra/sentry/issue-alerts.tf"),
  "utf8",
);
const dispatcher = readFileSync(
  join(here, "../server/cc-dispatcher.ts"),
  "utf8",
);

const FEATURE_TAG = "cc-dispatcher";
const OP_SLUGS = [
  "tenant-mint.persistUserMessage",
  "persistUserMessage.workspaceRead",
  "persist-user-message",
];

describe("chat-message-save-failure alert op/feature contract", () => {
  it("the feature tag appears in both the emit site and the alert filter", () => {
    expect(dispatcher).toContain(FEATURE_TAG);
    expect(tf).toContain(FEATURE_TAG);
  });

  for (const slug of OP_SLUGS) {
    it(`op slug "${slug}" appears in both cc-dispatcher.ts and issue-alerts.tf`, () => {
      // Emit side: the literal exists in cc-dispatcher.ts (inline literal for
      // the two siblings; CC_OP_SLUGS const value for persist-user-message).
      expect(dispatcher).toContain(slug);
      // Filter side: the same literal must be in the alert's op IS_IN value.
      expect(tf).toContain(slug);
    });
  }

  it("issue-alerts.tf binds the three slugs into one IS_IN filter value", () => {
    // Guard against the slugs appearing in unrelated rules: the IS_IN value is
    // a single comma-joined string containing all three.
    const isInValue = `${OP_SLUGS[0]},${OP_SLUGS[1]},${OP_SLUGS[2]}`;
    expect(tf).toContain(isInValue);
  });
});
