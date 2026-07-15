import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the zot mirror-staleness fallback-rate alarm
// (#6278 / ADR-096 "Loud, no-SSH signal").
//
// The `zot-mirror-fallback-rate` Sentry issue-alert pages on the FIRST runtime
// zot→GHCR fallback / gate-degrade event (event_frequency count > 0 / 1h, #6285),
// matching the OR of FOUR runtime signals (filter_match="any"):
//   - registry == "ghcr-fallback"      (ci-deploy.sh rolling-deploy pull fallback)
//   - registry == "zot-gate-degraded"  (ci-deploy.sh dark-gate degrade beacon)
//   - stage    == "inngest_ghcr_fallback" (cloud-init.yml inngest fresh-boot pull)
//   - stage    == "app_ghcr_fallback"     (cloud-init.yml app-image fresh-boot pull, #6278 Phase 1b)
//
// The inngest/app boot events carry only `stage` (no feature/op), so the filter is
// `any` over the tag-VALUES, not `all` over feature+op. Each tag string is pinned
// in BOTH its emit site AND issue-alerts.tf so a rename in either — which would
// silently DARK the alert (the operator-only-finds-out-post-cutover failure mode
// this alarm exists to prevent) — breaks CI instead.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const ciDeploy = readFileSync(join(here, "../infra/ci-deploy.sh"), "utf8");
const cloudInit = readFileSync(join(here, "../infra/cloud-init.yml"), "utf8");
// Repo root is three levels up from apps/web-platform/test (precedent: the
// apply-sentry-infra.yml read in the last leg of this file).
const soak = readFileSync(
  join(here, "../../../scripts/followthroughs/zot-soak-6122.sh"),
  "utf8",
);

// --- Derived extraction: the alarm's watched signal set -----------------------
//
// Scoped to the `filters_v2 = [ ... ]` block, NOT the whole resource block. A
// value-only regex over the resource returns the right four today only
// INCIDENTALLY (event_frequency's `value = 0` is unquoted and actions_v2 uses
// `target_type`), and would over-collect the first time a quoted filter of any
// other kind is added — which is how a test gets deleted instead of fixed.
function alarmFilterSet(): Set<string> {
  const start = tf.indexOf('resource "sentry_issue_alert" "zot_mirror_fallback_rate"');
  if (start === -1) throw new Error("zot_mirror_fallback_rate resource not found in issue-alerts.tf");
  const resource = tf.slice(start);
  const filtersStart = resource.indexOf("filters_v2 = [");
  if (filtersStart === -1) throw new Error("filters_v2 block not found on zot_mirror_fallback_rate");
  const filtersEnd = resource.indexOf("\n  ]", filtersStart);
  // Same fail-loud rationale as soakFailQueries: a -1 here would slice to the end of the FILE,
  // collecting every tagged_event of every OTHER alert resource below this one — silently
  // inflating the "watched set" and turning the parity assertion into noise.
  if (filtersEnd === -1) throw new Error("filters_v2 block is not closed as expected");
  const block = resource.slice(filtersStart, filtersEnd);
  const set = new Set<string>();
  const re = /tagged_event\s*=\s*\{[^}]*?key\s*=\s*"([^"]+)"[^}]*?value\s*=\s*"([^"]+)"[^}]*?\}/g;
  for (const m of block.matchAll(re)) set.add(`${m[1]}:${m[2]}`);
  return set;
}

// --- Derived extraction: the soak's FAIL set ---------------------------------
//
// Parses the `declare -A FAIL_QUERIES=( ... )` block. Scoping to the array block
// (rather than the whole file) is structural, not stylistic: the script header
// names all four signals in prose, so any whole-file assertion would stay GREEN
// with every query deleted. A comment cannot live inside the array.
function soakFailQueries(): Map<string, string> {
  const start = soak.indexOf("declare -A FAIL_QUERIES=(");
  // Fail LOUD on a missing/renamed block rather than silently widening. `indexOf` returns -1
  // when the anchor moves (e.g. the closing paren gets indented), and `slice(start, -1)` would
  // then scope the "array block" to nearly the whole FILE — where the header prose names all
  // four signal literals, so the extraction could pass while the array is gone. That is the
  // vacuity this test exists to prevent, so it must not be reachable through the test itself.
  if (start === -1) throw new Error("FAIL_QUERIES array block not found in zot-soak-6122.sh");
  const end = soak.indexOf("\n)", start);
  if (end === -1) throw new Error("FAIL_QUERIES array block is not closed by a column-0 ')'");
  const block = soak.slice(start, end);
  const out = new Map<string, string>();
  for (const m of block.matchAll(/^\s*\[[a-z_]+\]='([^']+)'/gm)) {
    const query = m[1];
    // Exactly one tag in each query is quoted — the signal tag. feature:supply-chain
    // and op:image-pull are bare, so this projection cannot pick them up.
    const sig = query.match(/([a-z_]+):"([^"]+)"/);
    if (sig) out.set(sig[2], query);
  }
  return out;
}

function soakFailSet(): Set<string> {
  const set = new Set<string>();
  for (const [, query] of soakFailQueries()) {
    const m = query.match(/([a-z_]+):"([^"]+)"/);
    if (m) set.add(`${m[1]}:${m[2]}`);
  }
  return set;
}

const soakQueryFor = (signal: string) => soakFailQueries().get(signal);

describe("zot-mirror-fallback-rate alert op contract", () => {
  it("ci-deploy.sh emits the supply-chain image-pull tags + both registry values", () => {
    expect(ciDeploy).toContain(`feature: "supply-chain"`);
    expect(ciDeploy).toContain(`op: "image-pull"`);
    // Pin the exact EMIT forms, not the bare tag literals: `ghcr-fallback` also
    // appears in several ci-deploy.sh comments, so a bare `toContain("ghcr-fallback")`
    // would stay GREEN even if the emit CALL were renamed — the silent-DARK failure
    // this guard exists to catch. `registry_pull_event ghcr-fallback` (the call site)
    // and `registry: "zot-gate-degraded"` (the jq tag literal) are emit-only.
    expect(ciDeploy).toContain("registry_pull_event ghcr-fallback");
    expect(ciDeploy).toContain(`registry: "zot-gate-degraded"`);
  });

  it("cloud-init.yml emits both fresh-boot fallback stages (inngest + app-image)", () => {
    // Pin the exact emit CALL forms — `app_ghcr_fallback` also appears in this PR's
    // Phase-1b explanatory comment, so pinning the bare stage would be vacuous.
    expect(cloudInit).toContain("soleur-boot-emit inngest_ghcr_fallback warning");
    expect(cloudInit).toContain(`"app_ghcr_fallback" warning`);
  });

  it("issue-alerts.tf pins all four signal tag-values (any-match OR)", () => {
    expect(tf).toContain(`value = "ghcr-fallback"`);
    expect(tf).toContain(`value = "zot-gate-degraded"`);
    expect(tf).toContain(`value = "inngest_ghcr_fallback"`);
    expect(tf).toContain(`value = "app_ghcr_fallback"`);
  });

  it("issue-alerts.tf declares the zot_mirror_fallback_rate resource with an any-match event_frequency rule", () => {
    expect(tf).toContain(
      'resource "sentry_issue_alert" "zot_mirror_fallback_rate"',
    );
    // Fire-on-first intent: event_frequency count > 0 within 1h (#6285). value MUST stay 0 —
    // any value > 0 is fleet-shape-dependent and silently unreachable whenever the per-group
    // event count cannot exceed it. See the resource comment in issue-alerts.tf for the
    // mechanism; do NOT "normalize" this to the value = 1 used by web_terminal_boot_fatal.
    const block = tf.slice(
      tf.indexOf('resource "sentry_issue_alert" "zot_mirror_fallback_rate"'),
    );
    const resourceEnd = block.indexOf("\nresource ");
    const scoped = resourceEnd === -1 ? block : block.slice(0, resourceEnd);
    expect(scoped).toMatch(/filter_match\s*=\s*"any"/);
    expect(scoped).toContain("event_frequency");
    expect(scoped).toMatch(/comparison_type\s*=\s*"count"/);
    expect(scoped).toMatch(/value\s*=\s*0/);
    expect(scoped).toMatch(/interval\s*=\s*"1h"/);
    // Pin the no-SSH page target: a silent removal of the notify action would
    // make the alarm fire-but-page-nobody (the exact Branch-B failure the CTO
    // ruling avoided). IssueOwners→ActiveMembers reaches the solo founder.
    expect(scoped).toContain("IssueOwners");
    expect(scoped).toContain("ActiveMembers");
  });

  // --- Parity: the soak gate must count every signal the alarm watches -------
  //
  // #6435: zot-soak-6122.sh queried only 2 of the 4 signals in the alarm's filter
  // set. registry:"zot-gate-degraded" and stage:"app_ghcr_fallback" were counted by
  // NOTHING, so an intermittently-degraded fleet produced FALLBACKS=0 with a
  // sufficient zot sample => PASS => GHCR retired (ADR-096 5.3-5.5, which rotates
  // AND revokes the PAT — no rollback) while the fleet was intermittently GHCR-served.
  //
  // The alarm and the soak are the two consumers of the same four literals; the emit
  // sites are pinned by the legs above. This leg makes the soak — the only unpinned
  // consumer, and the one gating an irreversible action — drift-proof.
  it("the soak gate's FAIL set equals the alarm's watched signal set (derived, both sides)", () => {
    const alarm = alarmFilterSet();
    // Guard against a vacuous pass if either extraction silently yields nothing.
    expect(alarm.size).toBe(4);
    expect(soakFailQueries().size).toBe(4);
    // Derived equality on BOTH sides — deliberately no canonical list here. A
    // WATCHED constant would be a third source of truth, not a parity test; this
    // shape gives "a 5th signal added to the alarm breaks CI" for free.
    expect(soakFailSet()).toEqual(alarm);
  });

  // The set-equality leg above projects each query down to its (key, value) pair,
  // which STRUCTURALLY DISCARDS the query prefix — so it cannot catch a prefix that
  // silently matches zero events forever. These four flat pins are the only thing
  // that can. Keep them flat and duplicated: a loop over a table hides a missing
  // entry, which is exactly how the 2-of-4 blindness survived review in the first
  // place. Duplication beats cleverness in a pin.
  //
  // THE PREFIX ASYMMETRY IS DELIBERATE AND LOAD-BEARING:
  //   ci-deploy.sh's jq payload carries feature+op, so the registry: queries are prefixed.
  //   cloud-init.yml's _emit writes only {stage,image_ref,host_id,detail} — NO feature/op —
  //   so the stage: queries MUST be bare. Sentry tag matching is exact: prefixing a
  //   stage: query makes it match zero events FOREVER, silently restoring the very
  //   blindness this PR removes. Proven live: stage:"bootstrap_complete" => 9 events,
  //   feature:supply-chain op:image-pull stage:"bootstrap_complete" => 0.
  it("pins the WHOLE query string for all four signals (the prefix trap)", () => {
    expect(soakQueryFor("ghcr-fallback")).toBe(
      'feature:supply-chain op:image-pull registry:"ghcr-fallback"',
    );
    expect(soakQueryFor("zot-gate-degraded")).toBe(
      'feature:supply-chain op:image-pull registry:"zot-gate-degraded"',
    );
    // BARE — no feature/op. See the asymmetry note above.
    expect(soakQueryFor("inngest_ghcr_fallback")).toBe(
      'stage:"inngest_ghcr_fallback"',
    );
    expect(soakQueryFor("app_ghcr_fallback")).toBe(
      'stage:"app_ghcr_fallback"',
    );
  });

  it("the -target wiring guards that the apply workflow creates the rule", () => {
    const wf = readFileSync(
      join(here, "../../../.github/workflows/apply-sentry-infra.yml"),
      "utf8",
    );
    expect(wf).toContain(
      "-target=sentry_issue_alert.zot_mirror_fallback_rate",
    );
  });
});
