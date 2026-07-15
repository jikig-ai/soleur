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
