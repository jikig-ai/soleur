import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#4918, PIR #4913 follow-up).
//
// The `kb-tenant-mint-silent-fallback` Sentry issue-alert filters on
// `feature == "kb-route-helpers"` AND `op IS_IN` the surviving tenant-mint
// failure slug. Because the alert uses `filter_match = "all"`, a rename of
// the `feature` tag OR the op slug on EITHER side (the emit site in
// kb/sync/route.ts, or the filter value in issue-alerts.tf) would silently
// zero the alert's matches — recreating the ~19-day-silent regression class
// one rename later. This test pins both filter dimensions against that drift.
//
// #4956: authenticateAndResolveKbPath migrated to the ADR-044 service-role
// resolvers (resolveActiveWorkspaceKbRoot + resolveActiveWorkspaceRepoMeta),
// so the kb/file + kb/c4 write routes no longer mint a tenant client. Its
// tenant-mint op slug was dropped from the emit site, the IS_IN filter, and
// OP_SLUGS below. `kb-sync.tenant-mint` (sync/route.ts) is the surviving live
// tenant-mint surface — the single remaining slug still proves the alert is
// armed.
//
// Substring match only (code-simplicity, mirrors sentry-chat-alert-op-contract):
// each slug is an inline string literal at its emit site; a whole-file match
// finds it. No TS const/AST resolution required.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");

// Scope the filter-side assertions to the kb_tenant_mint_silent_fallback
// resource BLOCK, not the whole file. A whole-file `toContain` would pass
// vacuously if a slug were deleted from THIS rule's IS_IN value while still
// lingering elsewhere in issue-alerts.tf (e.g. a comment or a sibling rule) —
// the removal would silently zero THIS alert's matches while the test stayed
// green. Slicing from the resource marker to the next `resource ` (or EOF)
// pins the assertion to this rule alone.
const RESOURCE_DECL =
  'resource "sentry_issue_alert" "kb_tenant_mint_silent_fallback"';
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
    // Both legacy KB-write tenant-mint op slugs were removed as their functions
    // migrated to the ADR-044 service-role resolvers: resolveUserKbRoot in the
    // share+upload consolidation (#4953), and authenticateAndResolveKbPath in
    // #4956 (resolveActiveWorkspaceKbRoot + resolveActiveWorkspaceRepoMeta — no
    // tenant-mint surface). `kb-sync.tenant-mint` is the surviving live slug
    // that keeps the alert armed.
    {
      slug: "kb-sync.tenant-mint",
      emit: kbSyncRoute,
      emitName: "app/api/kb/sync/route.ts",
    },
  ];

describe("kb-tenant-mint-silent-fallback alert op/feature contract", () => {
  it("declares the kb_tenant_mint_silent_fallback issue alert resource", () => {
    expect(blockStart).toBeGreaterThanOrEqual(0);
    expect(tfBlock).toContain(RESOURCE_DECL);
  });

  it("the feature tag appears in the surviving emit site and the alert filter", () => {
    // kb/sync/route.ts emits under feature "kb-route-helpers" (the alert's
    // feature filter). Post-#4956 it is the sole emit site for this alert.
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
});
