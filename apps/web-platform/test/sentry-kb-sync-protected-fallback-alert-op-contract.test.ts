import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#5426).
//
// The `kb_sync_protected_fallback_failed` Sentry issue-alert filters on
// `feature == "session-sync"` AND `op IS_IN "kb-sync.protected-fallback-failed"`.
// Because the alert uses `filter_match = "all"`, a rename of the `feature` tag
// OR the op slug on EITHER side (the emit site in server/session-sync.ts, or the
// filter value in issue-alerts.tf) would silently zero the alert's matches —
// re-darking the undelivered-KB-writes incident class the rule exists to catch.
// This test pins both filter dimensions against that drift.
//
// Substring match only (mirrors sentry-kb-sync-silent-failure-alert-op-contract):
// each slug is an inline string literal at its emit site; a whole-file match
// finds it.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");

// Scope the filter-side assertions to the resource BLOCK, not the whole file —
// a whole-file `toContain` would pass vacuously if a slug were deleted from THIS
// rule while lingering elsewhere (a comment or a sibling rule).
const RESOURCE_DECL =
  'resource "sentry_issue_alert" "kb_sync_protected_fallback_failed"';
const blockStart = tf.indexOf(RESOURCE_DECL);
const nextResource = tf.indexOf("\nresource ", blockStart + RESOURCE_DECL.length);
const tfBlock =
  blockStart === -1
    ? ""
    : tf.slice(blockStart, nextResource === -1 ? undefined : nextResource);

const sessionSync = readFileSync(
  join(here, "../server/session-sync.ts"),
  "utf8",
);

const FEATURE_TAG = "session-sync";
const OP_SLUG = "kb-sync.protected-fallback-failed";
// The warn-level success entry op must NOT be in the paging filter.
const SUCCESS_OP_SLUG = "kb-sync.push-protected-fallback";

describe("kb-sync-protected-fallback alert op/feature contract", () => {
  // apply-sentry-infra.yml plans the sentry root FULL (no `-target=` allowlist), so
  // the plan universe is `state UNION config`: declaring the resource IS what applies
  // it, and deleting this block is what destroys the live rule. That structurally
  // closes the declared-but-untargeted-is-silently-dark class (#5380), so this
  // declaration check is the whole apply contract.
  it("declares the kb_sync_protected_fallback_failed issue alert resource", () => {
    expect(blockStart).toBeGreaterThanOrEqual(0);
    expect(tfBlock).toContain(RESOURCE_DECL);
  });

  it("the feature tag appears in the emit site and the alert filter", () => {
    expect(sessionSync).toContain(FEATURE_TAG);
    expect(tfBlock).toContain(FEATURE_TAG);
  });

  it("the failure op slug appears in both session-sync.ts and the alert's filter block", () => {
    expect(sessionSync).toContain(OP_SLUG);
    expect(tfBlock).toContain(OP_SLUG);
  });

  it("the warn-level success op is emitted but NOT in the paging filter (would over-page)", () => {
    expect(sessionSync).toContain(SUCCESS_OP_SLUG);
    expect(tfBlock).not.toContain(SUCCESS_OP_SLUG);
  });

  it("the rule's frequency is unique across all issue alerts in the file", () => {
    // Line-anchored (multiline) so only real HCL `frequency = N` attribute
    // lines count — an inline comment mention like `frequency=18` in prose must
    // NOT inflate the count (drift-guard false-fail on comment prose).
    const freqMatch = tfBlock.match(/^\s*frequency\s*=\s*(\d+)/m);
    expect(freqMatch).not.toBeNull();
    const myFreq = freqMatch![1];
    const all =
      tf.match(new RegExp(`^\\s*frequency\\s*=\\s*${myFreq}\\b`, "gm")) ?? [];
    expect(all.length).toBe(1);
  });

  // Structural predicate pinning: a flip of filter_match to "any" (page on
  // feature-only, ignoring the op filter → over-page on every routine
  // session-sync blip) or op match to "EQUAL" would leave the slug-presence
  // assertions green while breaking the alert's scope. Pin both.
  it("the alert ANDs its filters (filter_match all) and matches the op via IS_IN", () => {
    expect(tfBlock).toContain('filter_match = "all"');
    expect(tfBlock).toMatch(/key\s*=\s*"op"[\s\S]*?match\s*=\s*"IS_IN"/);
  });
});
