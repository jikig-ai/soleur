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
