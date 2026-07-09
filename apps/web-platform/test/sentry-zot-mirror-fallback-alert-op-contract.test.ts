import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the zot mirror-staleness fallback-rate alarm
// (#6278 / ADR-096 "Loud, no-SSH signal").
//
// The `zot-mirror-fallback-rate` Sentry issue-alert pages when the runtime
// zot→GHCR fallback / gate-degrade event rate exceeds >3 / 1h (event_frequency),
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
    // ghcr-fallback is the level-warning registry value from registry_pull_event;
    // zot-gate-degraded is the literal from zot_gate_degraded_event.
    expect(ciDeploy).toContain("ghcr-fallback");
    expect(ciDeploy).toContain(`registry: "zot-gate-degraded"`);
  });

  it("cloud-init.yml emits both fresh-boot fallback stages (inngest + app-image)", () => {
    expect(cloudInit).toContain("inngest_ghcr_fallback");
    expect(cloudInit).toContain("app_ghcr_fallback");
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
    // Aggregate-rate intent: event_frequency count > 3 within 1h (not a first_seen page).
    const block = tf.slice(
      tf.indexOf('resource "sentry_issue_alert" "zot_mirror_fallback_rate"'),
    );
    const resourceEnd = block.indexOf("\nresource ");
    const scoped = resourceEnd === -1 ? block : block.slice(0, resourceEnd);
    expect(scoped).toMatch(/filter_match\s*=\s*"any"/);
    expect(scoped).toContain("event_frequency");
    expect(scoped).toMatch(/comparison_type\s*=\s*"count"/);
    expect(scoped).toMatch(/value\s*=\s*3/);
    expect(scoped).toMatch(/interval\s*=\s*"1h"/);
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
