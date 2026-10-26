// #9545 PR2 — a Flagsmith outage must not read as "Recording isn't on". `readRuntimeFlagDetailed` reports
// whether Flagsmith ANSWERED; `readEgressAuditCollectionState` maps an unanswered read to "unknown" (even when
// the env mirror happens to be on), while the ingest reader `isEgressAuditCollectionOn` stays a plain boolean.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockGetIdentityFlags = vi.fn();
vi.mock("flagsmith-nodejs", () => ({
  Flagsmith: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.getIdentityFlags = mockGetIdentityFlags;
  }),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));

import { __resetFeatureFlagsForTests, ANON_IDENTITY, readAgentSandboxUnixDenyDetailed, readRuntimeFlagDetailed } from "@/lib/feature-flags/server";
import { isEgressAuditCollectionOn, readEgressAuditCollectionState } from "@/server/egress-audit-collection";

const ORG = "22222222-2222-4222-8222-222222222222";
const ORIGINAL_ENV = process.env;

const answers = (on: boolean) => mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: (n: string) => on && n === "egress-audit-collection" });

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  delete process.env.FLAG_EGRESS_AUDIT_COLLECTION;
  delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
  mockGetIdentityFlags.mockReset();
  __resetFeatureFlagsForTests();
});
afterEach(() => {
  process.env = ORIGINAL_ENV;
});

describe("readRuntimeFlagDetailed", () => {
  it("Flagsmith answered ON / OFF: the value and fellBack=false", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    answers(true);
    await expect(readRuntimeFlagDetailed("egress-audit-collection", ANON_IDENTITY)).resolves.toEqual({ value: true, fellBack: false });
    __resetFeatureFlagsForTests();
    answers(false);
    await expect(readRuntimeFlagDetailed("egress-audit-collection", ANON_IDENTITY)).resolves.toEqual({ value: false, fellBack: false });
  });

  it("a configured Flagsmith that did not answer: the env mirror's value WITH fellBack=true, on or off", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockRejectedValue(new Error("timeout"));
    await expect(readRuntimeFlagDetailed("egress-audit-collection", ANON_IDENTITY)).resolves.toEqual({ value: false, fellBack: true });
    __resetFeatureFlagsForTests();
    process.env.FLAG_EGRESS_AUDIT_COLLECTION = "1";
    await expect(readRuntimeFlagDetailed("egress-audit-collection", ANON_IDENTITY)).resolves.toEqual({ value: true, fellBack: true });
  });

  it("no Flagsmith key configured: the env mirror is the authority, so fellBack=false", async () => {
    await expect(readRuntimeFlagDetailed("egress-audit-collection", ANON_IDENTITY)).resolves.toEqual({ value: false, fellBack: false });
    process.env.FLAG_EGRESS_AUDIT_COLLECTION = "1";
    __resetFeatureFlagsForTests();
    await expect(readRuntimeFlagDetailed("egress-audit-collection", ANON_IDENTITY)).resolves.toEqual({ value: true, fellBack: false });
  });
});

describe("readAgentSandboxUnixDenyDetailed vs readRuntimeFlagDetailed (fellBack breadth)", () => {
  it("with NO Flagsmith key the sandbox reader reports fellBack=true while the generic reader reports false", async () => {
    // Documented in the JSDoc of readAgentSandboxUnixDenyDetailed: the resolver CLI treats "no client" as unresolved.
    await expect(readRuntimeFlagDetailed("agent-sandbox-unix-deny", ANON_IDENTITY)).resolves.toMatchObject({ fellBack: false });
    __resetFeatureFlagsForTests();
    await expect(readAgentSandboxUnixDenyDetailed()).resolves.toMatchObject({ fellBack: true });
  });
});

describe("readEgressAuditCollectionState", () => {
  it("is true / false exactly as Flagsmith answered, evaluated for the organisation (role prd, no user)", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    answers(true);
    await expect(readEgressAuditCollectionState(ORG)).resolves.toBe(true);
    expect(mockGetIdentityFlags.mock.calls[0][0]).toBe(`org:${ORG}:prd`);
    __resetFeatureFlagsForTests();
    answers(false);
    await expect(readEgressAuditCollectionState(ORG)).resolves.toBe(false);
  });

  it("is `unknown` when Flagsmith did not answer, even when the env mirror says on", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockRejectedValue(new Error("timeout"));
    await expect(readEgressAuditCollectionState(ORG)).resolves.toBe("unknown");
    __resetFeatureFlagsForTests();
    process.env.FLAG_EGRESS_AUDIT_COLLECTION = "1";
    await expect(readEgressAuditCollectionState(ORG)).resolves.toBe("unknown");
  });

  it("with no Flagsmith key the env mirror is authoritative (a plain boolean, never `unknown`)", async () => {
    await expect(readEgressAuditCollectionState(ORG)).resolves.toBe(false);
  });
});

describe("isEgressAuditCollectionOn (the ingest reader)", () => {
  it("stays a plain boolean in every case, including an outage", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    answers(true);
    await expect(isEgressAuditCollectionOn(ORG)).resolves.toBe(true);
    __resetFeatureFlagsForTests();
    answers(false);
    await expect(isEgressAuditCollectionOn(ORG)).resolves.toBe(false);
    __resetFeatureFlagsForTests();
    mockGetIdentityFlags.mockRejectedValue(new Error("timeout"));
    await expect(isEgressAuditCollectionOn(ORG)).resolves.toBe(false);
    __resetFeatureFlagsForTests();
    process.env.FLAG_EGRESS_AUDIT_COLLECTION = "1";
    const outage = await isEgressAuditCollectionOn(ORG);
    expect(typeof outage).toBe("boolean");
    expect(outage).toBe(true);
  });
});
