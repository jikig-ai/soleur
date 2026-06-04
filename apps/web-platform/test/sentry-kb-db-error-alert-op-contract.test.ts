import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#4929, PIR #4913 follow-up #2).
//
// The `kb-db-error` Sentry issue-alert pages on the first KB share db-error
// event — the "breaks every insert" class (the 23502 NOT-NULL incident, the
// 42501 RLS class) that otherwise sits latent for weeks. It filters on
// `feature == "kb-share"` AND `op IS_IN` the kb-share emit slugs. Because the
// alert uses `filter_match = "all"`, a rename of the `feature` tag OR any op
// slug on EITHER side (the emit sites in kb-share.ts, or the filter value in
// issue-alerts.tf) would silently zero the alert's matches — recreating the
// latent-for-weeks regression class one rename later. This test pins both
// filter dimensions against that drift.
//
// Substring match only (code-simplicity, mirrors
// sentry-kb-tenant-mint-alert-op-contract): each slug is an inline string
// literal at its emit site; a whole-file match finds it. No TS const/AST
// resolution required.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");

// Scope the filter-side assertions to the kb_db_error resource BLOCK, not the
// whole file. A whole-file `toContain` would pass vacuously if a slug were
// deleted from THIS rule's IS_IN value while still lingering elsewhere in
// issue-alerts.tf (a comment or a sibling rule) — the removal would silently
// zero THIS alert's matches while the test stayed green. Slicing from the
// resource marker to the next `resource ` (or EOF) pins the assertion to this
// rule alone.
const RESOURCE_DECL = 'resource "sentry_issue_alert" "kb_db_error"';
const blockStart = tf.indexOf(RESOURCE_DECL);
const nextResource = tf.indexOf("\nresource ", blockStart + RESOURCE_DECL.length);
const tfBlock =
  blockStart === -1
    ? ""
    : tf.slice(blockStart, nextResource === -1 ? undefined : nextResource);

const kbShare = readFileSync(join(here, "../server/kb-share.ts"), "utf8");

const FEATURE_TAG = "kb-share";

// Each op slug paired with the emit file that must contain it. Declaration
// order MUST match the IS_IN value in issue-alerts.tf (the join assertion below
// is order-sensitive).
const OP_SLUGS: ReadonlyArray<{ slug: string; emit: string; emitName: string }> =
  [
    { slug: "create", emit: kbShare, emitName: "kb-share.ts" },
    { slug: "list", emit: kbShare, emitName: "kb-share.ts" },
    { slug: "revoke", emit: kbShare, emitName: "kb-share.ts" },
    { slug: "preview", emit: kbShare, emitName: "kb-share.ts" },
    { slug: "preview-invariant", emit: kbShare, emitName: "kb-share.ts" },
  ];

describe("kb-db-error alert op/feature contract", () => {
  it("declares the kb_db_error issue alert resource", () => {
    expect(blockStart).toBeGreaterThanOrEqual(0);
    expect(tfBlock).toContain(RESOURCE_DECL);
  });

  it("the feature tag appears in both the emit sites and the alert filter", () => {
    expect(kbShare).toContain(`feature: "${FEATURE_TAG}"`);
    // Filter side scoped to THIS rule's block, not the whole file.
    expect(tfBlock).toContain(FEATURE_TAG);
  });

  for (const { slug, emit, emitName } of OP_SLUGS) {
    it(`op slug "${slug}" appears in both ${emitName} and the alert's filter block`, () => {
      // Emit side: the literal exists as an `op: "<slug>"` in its emit file.
      expect(emit).toContain(`op: "${slug}"`);
      // Filter side: the same literal must be in THIS alert's block (not a
      // comment or sibling rule elsewhere in issue-alerts.tf).
      expect(tfBlock).toContain(slug);
    });
  }

  it("the alert block binds every slug into one IS_IN filter value", () => {
    // The IS_IN value is a single comma-joined string containing all slugs, in
    // declaration order. Asserting against tfBlock (not the whole file) means
    // removing or reordering any slug in THIS rule fails CI even if the slug
    // survives elsewhere in the file.
    const isInValue = OP_SLUGS.map((o) => o.slug).join(",");
    expect(tfBlock).toContain(isInValue);
  });

  it("the rule's frequency is unique across all issue alerts in the file", () => {
    // Line-anchored (multiline) so only real HCL `frequency = N` attribute
    // lines count — an inline comment mention like `frequency=13` in prose must
    // NOT inflate the count (drift-guard false-fail on comment prose).
    const freqMatch = tfBlock.match(/^\s*frequency\s*=\s*(\d+)/m);
    expect(freqMatch).not.toBeNull();
    const myFreq = freqMatch![1];
    const all =
      tf.match(new RegExp(`^\\s*frequency\\s*=\\s*${myFreq}\\b`, "gm")) ?? [];
    expect(all.length).toBe(1);
  });
});
