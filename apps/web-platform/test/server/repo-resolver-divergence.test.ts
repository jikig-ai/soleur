import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { reportSilentFallback } from "@/server/observability";
import {
  reportRepoResolverDivergence,
  _resetResolverDivergenceDedupeForTests,
} from "@/server/repo-resolver-divergence";

afterEach(() => {
  _resetResolverDivergenceDedupeForTests();
  vi.clearAllMocks();
});

describe("reportRepoResolverDivergence — fingerprint-deduped breadcrumb (ADR-044 PR-1, FR4)", () => {
  it("emits a synthetic repo_resolver_divergence error with exactly the two workspace ids + userId", () => {
    reportRepoResolverDivergence({
      userId: "user-1",
      op: "non-member-claim-reset",
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "user-1",
    });

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, ctx] = (reportSilentFallback as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).toBe("repo_resolver_divergence");
    expect(ctx.feature).toBe("repo-resolver-divergence");
    expect(ctx.op).toBe("non-member-claim-reset");
    // extra carries the two workspace ids (+ userId, which the emit boundary
    // pseudonymizes to userIdHash). NO repoUrl / installationId.
    expect(ctx.extra).toMatchObject({
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "user-1",
    });
    expect(ctx.extra).not.toHaveProperty("repoUrl");
    expect(ctx.extra).not.toHaveProperty("installationId");
  });

  it("dedupes by (op, userId, claim) fingerprint — does NOT re-fire per dispatch", () => {
    const args = {
      userId: "user-1",
      op: "non-member-claim-reset" as const,
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "user-1",
    };
    reportRepoResolverDivergence(args);
    reportRepoResolverDivergence(args);
    reportRepoResolverDivergence(args);

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
  });

  it("self-heal-failed is a distinct op (deduped independently from reset)", () => {
    reportRepoResolverDivergence({
      userId: "user-1",
      op: "non-member-claim-reset",
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "user-1",
    });
    reportRepoResolverDivergence({
      userId: "user-1",
      op: "self-heal-failed",
      activeClaimWorkspaceId: "user-1",
      resolvedWorkspaceId: "user-1",
    });
    expect(reportSilentFallback).toHaveBeenCalledTimes(2);
    const ops = (reportSilentFallback as ReturnType<typeof vi.fn>).mock.calls.map(
      (c) => c[1].op,
    );
    expect(ops).toContain("self-heal-failed");
  });

  // AC4 — the dispatch-time op (this PR) emits with the same security-safe extra
  // shape (no repoUrl / installationId leaked into the breadcrumb).
  it("connected-null-install-at-dispatch is a distinct op with the two-workspace-id extra shape", () => {
    reportRepoResolverDivergence({
      userId: "user-1",
      op: "connected-null-install-at-dispatch",
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "team-x",
    });
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, ctx] = (reportSilentFallback as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(ctx.op).toBe("connected-null-install-at-dispatch");
    expect(ctx.feature).toBe("repo-resolver-divergence");
    expect(ctx.extra).toMatchObject({
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "team-x",
    });
    expect(ctx.extra).not.toHaveProperty("repoUrl");
    expect(ctx.extra).not.toHaveProperty("installationId");
  });

  it("a DIFFERENT claim for the same user fires a new breadcrumb (not over-deduped on op alone)", () => {
    reportRepoResolverDivergence({
      userId: "user-1",
      op: "non-member-claim-reset",
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "user-1",
    });
    reportRepoResolverDivergence({
      userId: "user-1",
      op: "non-member-claim-reset",
      activeClaimWorkspaceId: "team-y",
      resolvedWorkspaceId: "user-1",
    });

    expect(reportSilentFallback).toHaveBeenCalledTimes(2);
  });
});
