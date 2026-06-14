// cron-github-cidr-refresh (#5284) — registration smoke + source-shape anchors
// + drift-decision behavioral unit. The heavy behavior (extraction/validation,
// commit/merge) is covered by the generator shell tests
// (gen-github-egress-cidr.test.sh) and the safeCommitAndPr unit tests; this file
// locks the Inngest registration contract, the five-registry slug parity, and
// the pure drift decision.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronGithubCidrRefresh,
  cronGithubCidrRefreshHandler,
  isCidrFileDirty,
  CRON_NAME,
  SENTRY_MONITOR_SLUG,
  CIDR_FILE_REL,
  GEN_SCRIPT_REL,
} from "@/server/inngest/functions/cron-github-cidr-refresh";
import { SYNTHETIC_CHECK_NAMES } from "@/server/inngest/functions/_cron-safe-commit";

describe("cronGithubCidrRefresh — registration smoke", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronGithubCidrRefresh).toBeDefined();
    expect(typeof cronGithubCidrRefresh).toBe("object");
    expect(typeof cronGithubCidrRefreshHandler).toBe("function");
  });
});

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-github-cidr-refresh.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-github-cidr-refresh"', "canonical function id"],
    ['cron: "41 6 * * *"', "daily off-peak schedule"],
    [
      'event: "cron/github-cidr-refresh.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("handler source-shape anchors", () => {
  it.each([
    ["mintInstallationToken", "App token minting"],
    ["DEFAULT_CRON_TOKEN_PERMISSIONS", "least-privilege token scope"],
    ["setupEphemeralWorkspace", "clone the repo"],
    ["teardownEphemeralWorkspace", "workspace teardown"],
    ["GET /meta", "fetch GitHub /meta via Octokit"],
    ["gen-github-egress-cidr.sh", "shells out to the committed generator"],
    ['mergeMode: "direct"', "direct-merge to main so apply re-fires"],
    ["safeCommitAndPr", "handler-side persistence"],
    ["syntheticChecks", "CLA synthetic checks for merge-to-main"],
    ["postSentryHeartbeat", "heartbeat on every path"],
    ["reportSilentFallback", "Sentry mirror on error"],
    ["allowedPaths: [CIDR_FILE_REL]", "commit scoped to the single CIDR file"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("five-registry slug parity + exported constants", () => {
  it("SENTRY_MONITOR_SLUG is byte-identical to the function id / CRON_NAME", () => {
    expect(CRON_NAME).toBe("cron-github-cidr-refresh");
    expect(SENTRY_MONITOR_SLUG).toBe("cron-github-cidr-refresh");
    expect(SENTRY_MONITOR_SLUG).toBe(CRON_NAME);
  });

  it("CIDR_FILE_REL points to the committed allowlist file", () => {
    expect(CIDR_FILE_REL).toBe(
      "apps/web-platform/infra/cron-egress-allowlist-cidr.txt",
    );
  });

  it("GEN_SCRIPT_REL points to the committed generator", () => {
    expect(GEN_SCRIPT_REL).toBe(
      "apps/web-platform/infra/scripts/gen-github-egress-cidr.sh",
    );
  });

  it("SYNTHETIC_CHECK_NAMES carries the CLA gates direct-merge needs", () => {
    expect(SYNTHETIC_CHECK_NAMES).toContain("cla-check");
    expect(SYNTHETIC_CHECK_NAMES).toContain("cla-evidence");
  });
});

describe("isCidrFileDirty — drift decision", () => {
  it("empty porcelain (generator no-op) → no drift", () => {
    expect(isCidrFileDirty("")).toBe(false);
    expect(isCidrFileDirty("\n")).toBe(false);
    expect(isCidrFileDirty("   \n  ")).toBe(false);
  });

  it("non-empty porcelain (file rewritten on /meta rotation) → drift", () => {
    expect(
      isCidrFileDirty(" M apps/web-platform/infra/cron-egress-allowlist-cidr.txt\n"),
    ).toBe(true);
  });
});
