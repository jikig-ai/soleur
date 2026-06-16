import { describe, expect, it } from "vitest";
import { EXPECTED_CRON_FUNCTIONS } from "@/server/inngest/cron-manifest";
import { ROUTINE_METADATA } from "@/server/inngest/routine-metadata";

// The metadata drift guard (NOT function-registry-count.test.ts `toBe(56)`, which counts the
// route array incl. event fns). This is what prevents a cron being added without metadata.
describe("routine-metadata sidecar parity", () => {
  it("has exactly one entry per EXPECTED_CRON_FUNCTIONS id", () => {
    expect(Object.keys(ROUTINE_METADATA).sort()).toEqual(
      [...EXPECTED_CRON_FUNCTIONS].sort(),
    );
  });

  it("every entry has a non-empty domain, ownerRole, scheduleLabel and a valid manualTrigger", () => {
    for (const [fnId, meta] of Object.entries(ROUTINE_METADATA)) {
      expect(meta.domain, `${fnId}.domain`).toBeTruthy();
      expect(meta.ownerRole, `${fnId}.ownerRole`).toBeTruthy();
      expect(meta.scheduleLabel, `${fnId}.scheduleLabel`).toBeTruthy();
      expect(["allowed", "confirm"], `${fnId}.manualTrigger`).toContain(
        meta.manualTrigger,
      );
    }
  });
});
