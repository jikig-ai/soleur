/**
 * Bug B (feat-one-shot-concierge-gh-403-self-heal): the Concierge installation
 * self-heal "promotion skipped" decision must be a QUERYABLE Sentry event, not
 * an observability-dark silent keep. When the membership probe denies promotion
 * (the user keeps a possibly-wrong install and `gh` may still 403), on-call must
 * be able to answer "why did this dispatch keep the wrong install?" from Sentry
 * alone — no SSH (hr-observability-layer-citation, cq-silent-fallback-must-mirror-to-sentry).
 *
 * The skip-mirror emit is extracted into a tiny pure helper (`mirrorSelfHealSkip`)
 * so the decision is unit-testable without standing up the per-dispatch cc
 * factory (which is impractical to invoke whole — same rationale as the
 * source-presence framing in cc-dispatcher-gh-403-directive.test.ts).
 */
import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

import { mirrorSelfHealSkip } from "../server/cc-self-heal-observability";

describe("mirrorSelfHealSkip — self-heal skip is a queryable Sentry event (Bug B)", () => {
  beforeEach(() => mockReportSilentFallback.mockReset());

  test("AC4: mirrors the deny/skip once with feature, op, and the 4-field payload", () => {
    mirrorSelfHealSkip({
      userId: "user-123",
      storedInstallationId: 111,
      owner: "victim-org",
      membershipProbeOutcome: "not-member",
      effectiveInstallationId: 111,
    });

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = mockReportSilentFallback.mock.calls[0];
    // AC8: a `null` err routes to Sentry.captureMessage — a queryable EVENT,
    // not a breadcrumb-only log.info. This null is the discoverability proof.
    expect(err).toBeNull();
    expect(opts.feature).toBe("cc-dispatcher");
    expect(opts.op).toBe("self-heal-skip");
    expect(opts.extra).toMatchObject({
      storedInstallationId: 111,
      owner: "victim-org",
      membershipProbeOutcome: "not-member",
      // promotion denied ⇒ effective == stored (the possibly-wrong install).
      effectiveInstallationId: 111,
    });
  });

  test("AC4: carries the transient `indeterminate` outcome verbatim", () => {
    mirrorSelfHealSkip({
      userId: "user-123",
      storedInstallationId: 222,
      owner: "some-org",
      membershipProbeOutcome: "indeterminate",
      effectiveInstallationId: 222,
    });
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra.membershipProbeOutcome).toBe("indeterminate");
  });

  test("AC5: the mirrored payload NEVER contains a gh token substring (hr-github-app-auth-not-pat)", () => {
    mirrorSelfHealSkip({
      userId: "user-123",
      storedInstallationId: 333,
      owner: "victim-org",
      membershipProbeOutcome: "indeterminate",
      effectiveInstallationId: 333,
    });
    const serialized = JSON.stringify(mockReportSilentFallback.mock.calls[0]);
    expect(serialized).not.toMatch(/ghs_|gho_|ghp_/);
  });
});
