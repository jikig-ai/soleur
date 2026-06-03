import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#4918, PIR #4913 follow-up).
//
// The `kb-tenant-mint-silent-fallback` Sentry issue-alert filters on
// `feature == "kb-route-helpers"` AND `op IS_IN` the three tenant-mint
// failure slugs. Because the alert uses `filter_match = "all"`, a rename of
// the `feature` tag OR any op slug on EITHER side (the emit sites in
// kb-route-helpers.ts / kb/sync/route.ts, or the filter value in
// issue-alerts.tf) would silently zero the alert's matches — recreating the
// ~19-day-silent regression class one rename later. This test pins both
// filter dimensions against that drift.
//
// Substring match only (code-simplicity, mirrors sentry-chat-alert-op-contract):
// each slug is an inline string literal at its emit site; a whole-file match
// finds it. No TS const/AST resolution required.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const kbRouteHelpers = readFileSync(
  join(here, "../server/kb-route-helpers.ts"),
  "utf8",
);
const kbSyncRoute = readFileSync(
  join(here, "../app/api/kb/sync/route.ts"),
  "utf8",
);

const FEATURE_TAG = "kb-route-helpers";

// Each op slug paired with the emit file that must contain it.
const OP_SLUGS: ReadonlyArray<{ slug: string; emit: string; emitName: string }> =
  [
    {
      slug: "resolveUserKbRoot.tenant-mint",
      emit: kbRouteHelpers,
      emitName: "kb-route-helpers.ts",
    },
    {
      slug: "authenticateAndResolveKbPath.tenant-mint",
      emit: kbRouteHelpers,
      emitName: "kb-route-helpers.ts",
    },
    {
      slug: "kb-sync.tenant-mint",
      emit: kbSyncRoute,
      emitName: "app/api/kb/sync/route.ts",
    },
  ];

describe("kb-tenant-mint-silent-fallback alert op/feature contract", () => {
  it("declares the kb_tenant_mint_silent_fallback issue alert resource", () => {
    expect(tf).toContain(
      'resource "sentry_issue_alert" "kb_tenant_mint_silent_fallback"',
    );
  });

  it("the feature tag appears in both the emit sites and the alert filter", () => {
    expect(kbRouteHelpers).toContain(FEATURE_TAG);
    expect(kbSyncRoute).toContain(FEATURE_TAG);
    expect(tf).toContain(FEATURE_TAG);
  });

  for (const { slug, emit, emitName } of OP_SLUGS) {
    it(`op slug "${slug}" appears in both ${emitName} and issue-alerts.tf`, () => {
      // Emit side: the literal exists in its emit file.
      expect(emit).toContain(slug);
      // Filter side: the same literal must be in the alert's op IS_IN value.
      expect(tf).toContain(slug);
    });
  }

  it("issue-alerts.tf binds the three slugs into one IS_IN filter value", () => {
    // Guard against the slugs appearing in unrelated rules: the IS_IN value is
    // a single comma-joined string containing all three, in declaration order.
    const isInValue = OP_SLUGS.map((o) => o.slug).join(",");
    expect(tf).toContain(isInValue);
  });
});
