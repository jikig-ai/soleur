import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#5417).
//
// The `container-restart-burst` Sentry issue-alert pages when
// container-restart-monitor.sh posts a restart-churn EVENT. It filters on
// `feature == "container-restart-monitor"` AND `op `in` {restart_storm,
// fresh_crash_loop}`. Because the alert uses `logic_type = "all"`, a rename of
// the `feature` tag OR an op slug on EITHER side (the emit site in
// container-restart-monitor.sh, or the filter value in issue-alerts.tf) would
// silently zero the alert's matches — the exact silent-paging-loss class this
// alert exists to prevent. Pin both filter dimensions against that drift, and
// fail closed if a NEW alertable monitor op is added without updating the `in`.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const monitor = readFileSync(
  join(here, "../infra/container-restart-monitor.sh"),
  "utf8",
);

// Slice to THIS rule's block so a deleted slug lingering elsewhere in the file
// (a comment / sibling rule) cannot make a whole-file match pass vacuously.
const RESOURCE_DECL = 'resource "sentry_alert" "container_restart_burst"';
const blockStart = tf.indexOf(RESOURCE_DECL);
const nextResource = tf.indexOf("\nresource ", blockStart + RESOURCE_DECL.length);
const tfBlock =
  blockStart === -1
    ? ""
    : tf.slice(blockStart, nextResource === -1 ? undefined : nextResource);

const FEATURE_TAG = "container-restart-monitor";

// Alertable ops (declaration order MUST match the `in` value).
const ALERTABLE_OPS = ["restart_storm", "fresh_crash_loop"] as const;
// Ops the monitor emits but must NOT page (informational). Adding a new monitor
// op forces a conscious in/out call here, failing the reverse-guard otherwise.
const EXCLUDED_OPS = ["recovered"] as const;

describe("container-restart-burst alert op/feature contract (#5417)", () => {
  it("declares the container_restart_burst issue alert resource", () => {
    expect(blockStart).toBeGreaterThanOrEqual(0);
    expect(tfBlock).toContain(RESOURCE_DECL);
  });

  it("the feature tag appears in both the monitor emit + the alert filter", () => {
    // Anchored (closing-quote / value-equality) matches so a SUFFIX rename
    // (container-restart-monitor-RENAMED) fails — a bare substring `.toContain`
    // would pass on the prefix and miss the drift.
    expect(monitor).toContain(`feature: "${FEATURE_TAG}"`);
    expect(tfBlock).toMatch(
      new RegExp(`value\\s*=\\s*"${FEATURE_TAG}"`),
    );
  });

  for (const op of ALERTABLE_OPS) {
    it(`alertable op "${op}" appears in both the monitor + the alert filter block`, () => {
      // Emit side: set as ALERT_OP in the monitor's classification.
      expect(monitor).toContain(`ALERT_OP="${op}"`);
      expect(tfBlock).toContain(op);
    });
  }

  it("binds every alertable op into one comma-joined `in` value (order-sensitive)", () => {
    expect(tfBlock).toContain(ALERTABLE_OPS.join(","));
  });

  it("ANDs its filters (filter_match all), op via `in`, feature via EQUAL", () => {
    expect(tfBlock).toContain('logic_type = "all"');
    expect(tfBlock).toMatch(/key\s*=\s*"op"[\s\S]*?match\s*=\s*"in"/);
    expect(tfBlock).toMatch(/key\s*=\s*"feature"[\s\S]*?match\s*=\s*"eq"/);
  });

  it("excludes the informational recovery op from the paging filter", () => {
    for (const op of EXCLUDED_OPS) {
      // The monitor DOES emit it (so the exclusion is meaningful)…
      expect(monitor).toContain(`"${op}"`);
      // …but it must NOT be inside this alert's `in` value.
      const isIn = tfBlock.match(/value\s*=\s*"([^"]*)"/g)?.join(" ") ?? "";
      expect(isIn).not.toContain(op);
    }
  });

  it("the rule's frequency is unique across all issue alerts in the file", () => {
    const freqMatch = tfBlock.match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
    expect(freqMatch).not.toBeNull();
    const myFreq = freqMatch![1];
    const all =
      tf.match(new RegExp(`^\\s*frequency_minutes\\s*=\\s*${myFreq}\\b`, "gm")) ?? [];
    expect(all.length).toBe(1);
  });
});
