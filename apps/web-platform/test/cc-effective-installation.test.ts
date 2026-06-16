// #5340 / #5240 — the Concierge installation self-heal SELECTION, extracted from
// `cc-dispatcher.ts realSdkQueryFactory` (feat-one-shot-concierge-gh-403) so the
// cold factory, the per-dispatch warm re-provision (cc-reprovision.ts), and the
// leader recovery (agent-runner.ts) all select the SAME entitled install. The
// extraction makes the promotion branches unit-testable for the first time (the
// factory was impractical to invoke whole).

import { describe, it, expect, vi, beforeEach } from "vitest";

const {
  mockGetInstallationAccount,
  mockFindRepoOwnerInstallationForUser,
  mockMirrorSelfHealSkip,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockGetInstallationAccount: vi.fn(),
  mockFindRepoOwnerInstallationForUser: vi.fn(),
  mockMirrorSelfHealSkip: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/server/github-app", () => ({
  getInstallationAccount: mockGetInstallationAccount,
  findRepoOwnerInstallationForUser: mockFindRepoOwnerInstallationForUser,
}));
vi.mock("@/server/cc-self-heal-observability", () => ({
  mirrorSelfHealSkip: mockMirrorSelfHealSkip,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));
vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));

import { resolveEffectiveInstallationId } from "@/server/cc-effective-installation";

const USER = "u1";
const REPO = "https://github.com/acme-org/widget";
const STORED = 100;
const OWNER = 200;

beforeEach(() => vi.clearAllMocks());

describe("resolveEffectiveInstallationId", () => {
  it("null stored install → returns null (no probe)", async () => {
    const out = await resolveEffectiveInstallationId({ userId: USER, installationId: null, repoUrl: REPO });
    expect(out).toBeNull();
    expect(mockGetInstallationAccount).not.toHaveBeenCalled();
  });

  it("malformed / empty repoUrl (no owner) → returns the stored install, no probe", async () => {
    const out = await resolveEffectiveInstallationId({ userId: USER, installationId: STORED, repoUrl: null });
    expect(out).toBe(STORED);
    expect(mockGetInstallationAccount).not.toHaveBeenCalled();
  });

  it("stored install already owns the repo → returns stored, NO skip mirror", async () => {
    mockGetInstallationAccount.mockResolvedValue({ login: "acme-org", type: "Organization" });
    const out = await resolveEffectiveInstallationId({ userId: USER, installationId: STORED, repoUrl: REPO });
    expect(out).toBe(STORED);
    expect(mockMirrorSelfHealSkip).not.toHaveBeenCalled();
  });

  it("personal install not owning the repo + entitled owner install found → PROMOTES", async () => {
    mockGetInstallationAccount.mockResolvedValue({ login: "alice", type: "User" });
    mockFindRepoOwnerInstallationForUser.mockResolvedValue({ installationId: OWNER, outcome: "member" });
    const out = await resolveEffectiveInstallationId({ userId: USER, installationId: STORED, repoUrl: REPO });
    expect(out).toBe(OWNER);
    expect(mockMirrorSelfHealSkip).not.toHaveBeenCalled();
  });

  it("personal install, promotion denied (owner install null) → keeps stored + mirrors skip", async () => {
    mockGetInstallationAccount.mockResolvedValue({ login: "alice", type: "User" });
    mockFindRepoOwnerInstallationForUser.mockResolvedValue({ installationId: null, outcome: "not-member" });
    const out = await resolveEffectiveInstallationId({ userId: USER, installationId: STORED, repoUrl: REPO });
    expect(out).toBe(STORED);
    expect(mockMirrorSelfHealSkip).toHaveBeenCalledTimes(1);
    expect(mockMirrorSelfHealSkip.mock.calls[0][0]).toMatchObject({
      membershipProbeOutcome: "not-member",
      effectiveInstallationId: STORED,
    });
  });

  it("org-type stored install not owning the repo → keeps stored + mirrors org-type skip", async () => {
    mockGetInstallationAccount.mockResolvedValue({ login: "other-org", type: "Organization" });
    const out = await resolveEffectiveInstallationId({ userId: USER, installationId: STORED, repoUrl: REPO });
    expect(out).toBe(STORED);
    expect(mockFindRepoOwnerInstallationForUser).not.toHaveBeenCalled();
    expect(mockMirrorSelfHealSkip).toHaveBeenCalledWith(
      expect.objectContaining({ membershipProbeOutcome: "org-type-stored-install" }),
    );
  });

  it("probe throws → fail-soft: keeps stored install + mirrors to Sentry, never throws", async () => {
    mockGetInstallationAccount.mockRejectedValue(new Error("probe boom"));
    const out = await resolveEffectiveInstallationId({ userId: USER, installationId: STORED, repoUrl: REPO });
    expect(out).toBe(STORED);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "cc-dispatcher",
      op: "installation-self-heal-probe",
    });
  });
});
