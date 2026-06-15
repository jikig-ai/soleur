import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#4918, PIR #4913 follow-up; re-pointed #5005).
//
// The `kb_sync_silent_failure` Sentry issue-alert filters on
// `feature == "kb-route-helpers"` AND `op IS_IN` the kb/sync silent-failure
// slug. Because the alert uses `filter_match = "all"`, a rename of the
// `feature` tag OR the op slug on EITHER side (the emit site in
// kb/sync/route.ts, or the filter value in issue-alerts.tf) would silently zero
// the alert's matches — recreating the ~19-day-silent regression class one
// rename later. This test pins both filter dimensions against that drift.
//
// #5005: kb/sync converged off the per-user tenant client onto the ADR-044
// service-role resolvers (resolveActiveWorkspaceKbRoot +
// resolveActiveWorkspaceRepoMeta), removing the LAST `kb-sync.tenant-mint` emit
// site. The tenant-mint failure class no longer exists on any KB route, so the
// alert was re-pointed to the route's surviving silent-failure surface: the
// top-level catch's `kb-sync.unexpected` op (still under feature
// "kb-route-helpers"). OP_SLUGS below tracks that re-point.
//
// Substring match only (code-simplicity, mirrors sentry-chat-alert-op-contract):
// each slug is an inline string literal at its emit site; a whole-file match
// finds it. No TS const/AST resolution required.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");

// Scope the filter-side assertions to the kb_sync_silent_failure resource
// BLOCK, not the whole file. A whole-file `toContain` would pass vacuously if a
// slug were deleted from THIS rule's IS_IN value while still lingering elsewhere
// in issue-alerts.tf (e.g. a comment or a sibling rule) — the removal would
// silently zero THIS alert's matches while the test stayed green. Slicing from
// the resource marker to the next `resource ` (or EOF) pins the assertion to
// this rule alone.
const RESOURCE_DECL =
  'resource "sentry_issue_alert" "kb_sync_silent_failure"';
const blockStart = tf.indexOf(RESOURCE_DECL);
const nextResource = tf.indexOf("\nresource ", blockStart + RESOURCE_DECL.length);
const tfBlock =
  blockStart === -1
    ? ""
    : tf.slice(blockStart, nextResource === -1 ? undefined : nextResource);
const kbSyncRoute = readFileSync(
  join(here, "../app/api/kb/sync/route.ts"),
  "utf8",
);

const FEATURE_TAG = "kb-route-helpers";

// Each op slug paired with the emit file that must contain it.
const OP_SLUGS: ReadonlyArray<{ slug: string; emit: string; emitName: string }> =
  [
    // Post-#5005 the alert guards kb/sync's top-level unexpected-failure catch
    // (the only remaining silent-failure surface after the tenant-mint
    // convergence). The prior `kb-sync.tenant-mint` slug was removed with the
    // tenant client.
    {
      slug: "kb-sync.unexpected",
      emit: kbSyncRoute,
      emitName: "app/api/kb/sync/route.ts",
    },
  ];

describe("kb-sync-silent-failure alert op/feature contract", () => {
  it("declares the kb_sync_silent_failure issue alert resource", () => {
    expect(blockStart).toBeGreaterThanOrEqual(0);
    expect(tfBlock).toContain(RESOURCE_DECL);
  });

  it("the feature tag appears in the emit site and the alert filter", () => {
    // kb/sync/route.ts emits under feature "kb-route-helpers" (the alert's
    // feature filter).
    expect(kbSyncRoute).toContain(FEATURE_TAG);
    // Filter side scoped to THIS rule's block, not the whole file.
    expect(tfBlock).toContain(FEATURE_TAG);
  });

  for (const { slug, emit, emitName } of OP_SLUGS) {
    it(`op slug "${slug}" appears in both ${emitName} and the alert's filter block`, () => {
      // Emit side: the literal exists in its emit file.
      expect(emit).toContain(slug);
      // Filter side: the same literal must be in THIS alert's block (not a
      // comment or sibling rule elsewhere in issue-alerts.tf).
      expect(tfBlock).toContain(slug);
    });
  }

  it("the alert block binds the slugs into one IS_IN filter value", () => {
    // The IS_IN value is a single comma-joined string containing all slugs, in
    // declaration order. Asserting against tfBlock (not the whole file) means
    // removing or reordering any slug in THIS rule fails CI even if the slug
    // survives elsewhere in the file.
    const isInValue = OP_SLUGS.map((o) => o.slug).join(",");
    expect(tfBlock).toContain(isInValue);
  });

  // Regression guard (PR follow-up to #5380): this rule is APPLY-CREATED, so it
  // is inert unless the apply workflow `-target`s it. It was declared in
  // issue-alerts.tf (#4918, re-pointed #5005) but never added to the apply
  // -target list, so the live Sentry rule was never created and the alert sat
  // dark — the exact "user reports it before we know" failure mode the rule
  // exists to prevent. A declared-but-untargeted alert is silently inert; pin
  // the wiring so dropping it breaks CI.
  it("is wired into the apply-sentry-infra.yml -target list (else it never applies)", () => {
    const wf = readFileSync(
      join(here, "../../../.github/workflows/apply-sentry-infra.yml"),
      "utf8",
    );
    expect(wf).toContain(
      "-target=sentry_issue_alert.kb_sync_silent_failure",
    );
  });
});
