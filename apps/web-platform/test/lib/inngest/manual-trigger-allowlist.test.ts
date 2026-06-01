import { describe, it, expect } from "vitest";
import {
  EXPECTED_CRON_FUNCTIONS,
  manualTriggerEventFor,
} from "@/server/inngest/cron-manifest";
import {
  MANUAL_TRIGGER_EVENTS,
  isAllowlistedManualTrigger,
} from "@/lib/inngest/manual-trigger-allowlist";

describe("manual-trigger allowlist", () => {
  it("equals EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor) — no parallel hardcoded list", () => {
    expect(MANUAL_TRIGGER_EVENTS).toEqual(
      new Set(EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor)),
    );
    // Drift guard: same cardinality as the manifest (one event per cron).
    expect(MANUAL_TRIGGER_EVENTS.size).toBe(EXPECTED_CRON_FUNCTIONS.length);
  });

  it("allowlists a known cron's manual-trigger event", () => {
    expect(
      isAllowlistedManualTrigger("cron/workspace-sync-health.manual-trigger"),
    ).toBe(true);
    expect(
      isAllowlistedManualTrigger("cron/inngest-cron-watchdog.manual-trigger"),
    ).toBe(true);
  });

  it("rejects non-cron / event-prefixed / malformed names", () => {
    // cf-token-expiry-check is an `event-`-prefixed function, NOT a `cron-`,
    // so its *.manual-trigger string must NOT be allowlisted.
    expect(
      isAllowlistedManualTrigger("cron/cf-token-expiry-check.manual-trigger"),
    ).toBe(false);
    expect(isAllowlistedManualTrigger("evil")).toBe(false);
    expect(isAllowlistedManualTrigger("cron/bug-fixer.run")).toBe(false);
    expect(isAllowlistedManualTrigger("cron/workspace-sync-health")).toBe(false);
  });

  it("rejects non-string inputs (type narrowing)", () => {
    expect(isAllowlistedManualTrigger(undefined)).toBe(false);
    expect(isAllowlistedManualTrigger(null)).toBe(false);
    expect(isAllowlistedManualTrigger(42)).toBe(false);
    expect(isAllowlistedManualTrigger({})).toBe(false);
  });
});
