import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";
import { callSites } from "./approval/source-scan";

// Cross-artifact contract test (#5426).
//
// The `kb_sync_protected_fallback_failed` Sentry issue-alert filters on
// `feature == "session-sync"` AND `op `in` "kb-sync.protected-fallback-failed"`.
// Because the alert uses `logic_type = "all"`, a rename of the `feature` tag
// OR the op slug on EITHER side (the emit site in server/session-sync.ts, or the
// filter value in issue-alerts.tf) would silently zero the alert's matches —
// re-darking the undelivered-KB-writes incident class the rule exists to catch.
// This test pins both filter dimensions against that drift.
//
// The emit side is anchored on CALL SITES (#12600, CTO ruling D21; cq-assert-anchor-not-bare-token): an emit helper call
// whose options object carries `feature: "session-sync"` and the op slug, so a slug surviving only in a comment or a
// message string is red.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");

// Scope the filter-side assertions to the resource BLOCK, not the whole file —
// a whole-file `toContain` would pass vacuously if a slug were deleted from THIS
// rule while lingering elsewhere (a comment or a sibling rule).
const RESOURCE_DECL =
  'resource "sentry_alert" "kb_sync_protected_fallback_failed"';
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
/** The (helper, op) pairs of every emit call in session-sync.ts whose options carry the feature tag. */
const EMITS = ["reportSilentFallback", "warnSilentFallback", "mirrorWithDebounce", "mirrorWarnWithDebounce"].flatMap((helper) =>
  callSites(sessionSync, "server/session-sync.ts", helper).flatMap((c) =>
    c.args.filter((a) => a.props.feature === `"${FEATURE_TAG}"` && a.props.op !== undefined).map((a) => `${helper} ${a.props.op}`),
  ),
);
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
    expect(EMITS.length).toBeGreaterThan(0);
    expect(tfBlock).toContain(FEATURE_TAG);
  });

  it("the failure op slug is emitted by a call site in session-sync.ts (both branches, debounced) and sits in the alert's filter block", () => {
    expect(EMITS.filter((e) => e === `mirrorWithDebounce "${OP_SLUG}"`)).toHaveLength(2); // fallback_failed and persistent_other
    expect(tfBlock).toContain(OP_SLUG);
  });

  it("the warn-level success op is emitted by a call site but NOT in the paging filter (would over-page)", () => {
    expect(EMITS).toContain(`warnSilentFallback "${SUCCESS_OP_SLUG}"`);
    expect(tfBlock).not.toContain(SUCCESS_OP_SLUG);
  });

  it("the transient side push warns on its own op, which is NOT in the paging filter (D21)", () => {
    expect(EMITS).toContain('mirrorWarnWithDebounce "kb-sync.side-push-transient"');
    expect(tfBlock).not.toContain("kb-sync.side-push-transient");
  });

  it("the rule's frequency is unique across all issue alerts in the file", () => {
    // Line-anchored (multiline) so only real HCL `frequency = N` attribute
    // lines count — an inline comment mention like `frequency=18` in prose must
    // NOT inflate the count (drift-guard false-fail on comment prose).
    const freqMatch = tfBlock.match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
    expect(freqMatch).not.toBeNull();
    const myFreq = freqMatch![1];
    const all =
      tf.match(new RegExp(`^\\s*frequency_minutes\\s*=\\s*${myFreq}\\b`, "gm")) ?? [];
    expect(all.length).toBe(1);
  });

  // Structural predicate pinning: a flip of filter_match to "any" (page on
  // feature-only, ignoring the op filter → over-page on every routine
  // session-sync blip) or op match to "eq" would leave the slug-presence
  // assertions green while breaking the alert's scope. Pin both.
  it("the alert ANDs its filters (filter_match all) and matches the op via `in`", () => {
    expect(tfBlock).toContain('logic_type = "all"');
    expect(tfBlock).toMatch(/key\s*=\s*"op"[\s\S]*?match\s*=\s*"in"/);
  });
});
