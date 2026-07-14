import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the web-host terminal serving-block boot-FATAL alarm
// (#6396, ADR-082 Item 5 — "the SOLE page for a dead web-2 warm standby").
//
// The cloud-init terminal `docker run` block emits `soleur-boot-emit <stage> fatal` on a
// no-SSH boot abort (tags.stage names the failing region). web-2 is a warm standby that takes
// no app.soleur.ai traffic, so `betteruptime_monitor.app` stays GREEN on a dead standby, and
// the #5933 per-host origin uptime probe was RETIRED — this Sentry issue-alert is the ONLY page.
//
// Each terminal stage string is pinned in BOTH its cloud-init emit site AND issue-alerts.tf so
// a rename in either — which would silently DARK the alert (the operator-only-finds-out-after-a-
// dead-standby failure this alarm exists to prevent) — breaks CI instead.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const cloudInit = readFileSync(join(here, "../infra/cloud-init.yml"), "utf8");

const STAGES = [
  "terminal_preamble",
  "hostscripts_incomplete",
  "doppler_download",
  "docker_run",
] as const;

describe("web-host-terminal-boot-fatal alert op contract", () => {
  it("cloud-init.yml arms the composite EXIT trap that emits soleur-boot-emit <stage> fatal", () => {
    // The mutable-stage EXIT trap fires on exit 1 / set -e aborts (doppler_download, docker_run).
    expect(cloudInit).toContain(
      `[ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal`,
    );
    // The poweroff path bypasses the EXIT trap (signal death) — an explicit emit precedes it.
    expect(cloudInit).toContain("soleur-boot-emit hostscripts_incomplete fatal");
  });

  it("cloud-init.yml advances the mutable stage through every fatal-tagged region", () => {
    // Pin the stage ASSIGNMENTS (not bare tag literals) so a rename breaks CI. terminal_preamble
    // is the armed value; doppler_download + docker_run advance the trap's coverage.
    expect(cloudInit).toContain("stage=terminal_preamble");
    expect(cloudInit).toContain("stage=doppler_download");
    expect(cloudInit).toContain("stage=docker_run");
  });

  it("issue-alerts.tf pins all four terminal stage tag-values (any-match OR)", () => {
    for (const stage of STAGES) {
      expect(tf).toContain(`value = "${stage}"`);
    }
  });

  it("issue-alerts.tf declares web_terminal_boot_fatal as a first-occurrence page with a notify target", () => {
    expect(tf).toContain(
      'resource "sentry_issue_alert" "web_terminal_boot_fatal"',
    );
    const start = tf.indexOf(
      'resource "sentry_issue_alert" "web_terminal_boot_fatal"',
    );
    const rest = tf.slice(start + 1);
    const nextResource = rest.indexOf("\nresource ");
    const scoped =
      nextResource === -1 ? tf.slice(start) : tf.slice(start, start + 1 + nextResource);
    // Page on the FIRST fatal (value=1 over 1h) — a dead serving host is high-severity, not a rate.
    expect(scoped).toMatch(/filter_match\s*=\s*"any"/);
    expect(scoped).toContain("event_frequency");
    expect(scoped).toMatch(/comparison_type\s*=\s*"count"/);
    expect(scoped).toMatch(/value\s*=\s*1/);
    expect(scoped).toMatch(/interval\s*=\s*"1h"/);
    // Every filter selects on key = "stage" (the shared soleur-boot-emit events tag the region).
    expect(scoped).not.toMatch(/key\s*=\s*"(?!stage")/);
    expect(scoped).toContain(`key   = "stage"`);
    // No-SSH page target: a silent removal would make the alarm fire-but-page-nobody.
    expect(scoped).toContain("IssueOwners");
    expect(scoped).toContain("ActiveMembers");
  });

  it("the -target wiring guards that the apply workflow creates the rule", () => {
    const wf = readFileSync(
      join(here, "../../../.github/workflows/apply-sentry-infra.yml"),
      "utf8",
    );
    expect(wf).toContain(
      "-target=sentry_issue_alert.web_terminal_boot_fatal",
    );
  });
});
