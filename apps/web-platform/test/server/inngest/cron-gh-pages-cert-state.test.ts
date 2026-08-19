// TR9 Phase-2 — cron-gh-pages-cert-state unit tests.
//
// Test coverage:
//   (a) Registration smoke test — import loads without throwing.
//   (b) Source-shape anchor tests — id, cron, event, concurrency, retries.
//   (c) Exported constant — CERT_WARN_DAYS.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronGhPagesCertState,
  CERT_WARN_DAYS,
  CERT_CRITICAL_DAYS,
  REISSUE_ELIGIBLE_STATES,
  certEscalation,
} from "@/server/inngest/functions/cron-gh-pages-cert-state";

// =============================================================================
// Registration smoke test
// =============================================================================

describe("cronGhPagesCertState — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronGhPagesCertState).toBeDefined();
    expect(typeof cronGhPagesCertState).toBe("object");
  });
});

// =============================================================================
// Exported constants
// =============================================================================

describe("cronGhPagesCertState — exported constants", () => {
  it("CERT_WARN_DAYS is 21", () => {
    expect(CERT_WARN_DAYS).toBe(21);
  });
});

// =============================================================================
// Source-shape anchor tests
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-gh-pages-cert-state.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-gh-pages-cert-state"', "canonical function id"],
    ['cron: "0 3 * * *"', "daily at 03:00 UTC schedule"],
    ['event: "cron/gh-pages-cert-state.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on cert check failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("cron-gh-pages-cert-state — Sentry monitor slug", () => {
  it("source contains the correct Sentry monitor slug", () => {
    expect(SUT_SOURCE).toContain('"scheduled-gh-pages-cert-state"');
  });
});

describe("cron-gh-pages-cert-state — key logic anchors", () => {
  it.each([
    ["approved", "healthy cert state"],
    ["issued", "healthy cert state"],
    ["https_certificate", "Pages API response field"],
    ["expires_at", "cert expiry field"],
    ["[cert-poll]", "issue title prefix for dedup"],
    ["action-required", "issue label"],
    ["infra-drift", "issue label"],
    ["GET /repos/{owner}/{repo}/pages", "Pages API endpoint"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

// =============================================================================
// Escalation predicate (2026-08-16 apex-outage regression)
// =============================================================================
//
// The outage was NOT a detection failure — cron-gh-pages-cert-state filed #6691
// 28 days early and commented daily down to "expires in -1 days". It was an
// ESCALATION failure: a daily GitHub comment is a log, not a page. These pin the
// predicate that decides when a reading reaches Sentry.

describe("certEscalation — pages only a WEDGED cert near expiry", () => {
  it("CERT_CRITICAL_DAYS is 7 (narrower than the 21-day warn window)", () => {
    expect(CERT_CRITICAL_DAYS).toBe(7);
    expect(CERT_CRITICAL_DAYS).toBeLessThan(CERT_WARN_DAYS);
  });

  it.each(["approved", "issued"])(
    "healthy state %s never escalates, even at 0 days",
    (certState) => {
      expect(
        certEscalation({ certState, daysUntilExpiry: 0 }).escalate,
      ).toBe(false);
    },
  );

  it.each(REISSUE_ELIGIBLE_STATES)(
    "wedged state %s escalates inside the critical window",
    (certState) => {
      const v = certEscalation({ certState, daysUntilExpiry: 6 });
      expect(v.escalate).toBe(true);
      expect(v.reason).toContain(certState);
    },
  );

  it("does NOT escalate a wedged cert still outside the critical window", () => {
    // This is the #6691 shape on day 1: real problem, ticket-worthy, not yet a page.
    expect(
      certEscalation({ certState: "bad_authz", daysUntilExpiry: 27 }).escalate,
    ).toBe(false);
  });

  it("escalates at the boundary-inside but not at the boundary itself", () => {
    expect(
      certEscalation({ certState: "bad_authz", daysUntilExpiry: 7 }).escalate,
    ).toBe(false);
    expect(
      certEscalation({ certState: "bad_authz", daysUntilExpiry: 6 }).escalate,
    ).toBe(true);
  });

  it("escalates an ALREADY-EXPIRED wedged cert and says so", () => {
    // The literal 2026-08-16 reading that preceded the outage.
    const v = certEscalation({ certState: "bad_authz", daysUntilExpiry: -1 });
    expect(v.escalate).toBe(true);
    expect(v.reason).toContain("EXPIRED");
  });

  it("escalates when expiry is UNKNOWN rather than assuming time remains", () => {
    const v = certEscalation({ certState: "bad_authz", daysUntilExpiry: null });
    expect(v.escalate).toBe(true);
    expect(v.reason).toContain("UNKNOWN");
  });

  it.each(["authorization_pending", "dns_changed", "new"])(
    "does NOT page on in-flight order state %s (ACME may still self-heal)",
    (certState) => {
      // The reissue routine declines these too — paging here would be noise the
      // operator learns to ignore, which is how the real page gets missed.
      expect(
        certEscalation({ certState, daysUntilExpiry: 1 }).escalate,
      ).toBe(false);
    },
  );
});

describe("escalation is wired into the handler, not just exported", () => {
  it.each([
    ['step.run("escalate-if-critical"', "escalation runs as its own step"],
    ["reportSilentFallback", "routes to the Sentry paging channel"],
    ['op: "cert-critical"', "queryable Sentry tag"],
    ["SOLEUR_CERT_CRITICAL", "monitored stdout marker for Better Stack"],
    [
      "cron/gh-pages-cert-reissue.manual-trigger",
      "names the remediation in the alert payload",
    ],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("escalates BEFORE the heartbeat so a broken page cannot hide the run", () => {
    expect(SUT_SOURCE.indexOf('step.run("escalate-if-critical"')).toBeLessThan(
      SUT_SOURCE.indexOf('step.run("sentry-heartbeat"'),
    );
  });
});
