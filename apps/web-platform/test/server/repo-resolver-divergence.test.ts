import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  hashUserId: (s: string) => `hash-${s}`,
}));

import { reportSilentFallback } from "@/server/observability";
import {
  reportRepoResolverDivergence,
  reportAgentReadinessSelfStop,
  reportAgentReadinessProbeInconclusive,
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

  // AC9 — the corrupt-worktree op (2026-06-19) carries `extra.recovered` so a
  // self-healed re-clone (true) is triageable apart from an unrecovered
  // honest-block (false); both shapes are safe (no repoUrl/installationId).
  it("corrupt-worktree-at-dispatch carries extra.recovered (recovered branch)", () => {
    reportRepoResolverDivergence({
      userId: "user-1",
      op: "corrupt-worktree-at-dispatch",
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "team-x",
      recovered: true,
    });
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, ctx] = (reportSilentFallback as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(ctx.op).toBe("corrupt-worktree-at-dispatch");
    expect(ctx.feature).toBe("repo-resolver-divergence");
    expect(ctx.extra).toMatchObject({ recovered: true });
    expect(ctx.extra).not.toHaveProperty("repoUrl");
    expect(ctx.extra).not.toHaveProperty("installationId");
  });

  it("corrupt-worktree-at-dispatch recovered=true vs recovered=false are NOT collapsed by the dedupe fingerprint", () => {
    const base = {
      userId: "user-1",
      op: "corrupt-worktree-at-dispatch" as const,
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "team-x",
    };
    reportRepoResolverDivergence({ ...base, recovered: true });
    reportRepoResolverDivergence({ ...base, recovered: false });
    // Distinct `recovered` → distinct fingerprint → two emits (a self-heal
    // breadcrumb AND a later unrecovered page on the same workspace both surface).
    expect(reportSilentFallback).toHaveBeenCalledTimes(2);
    const recovereds = (reportSilentFallback as ReturnType<typeof vi.fn>).mock.calls.map(
      (c) => c[1].extra.recovered,
    );
    expect(recovereds).toContain(true);
    expect(recovereds).toContain(false);
  });

  // ADR-044 PR-3 — the per-dispatch reprovision-path op (warm+cold) emits with the
  // same security-safe extra shape and is deduped independently by op.
  it("reprovision-non-member-claim-reset is a distinct op with the two-workspace-id extra shape (no repoUrl/install leak)", () => {
    reportRepoResolverDivergence({
      userId: "user-1",
      op: "reprovision-non-member-claim-reset",
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "user-1",
    });
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, ctx] = (reportSilentFallback as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(ctx.op).toBe("reprovision-non-member-claim-reset");
    expect(ctx.feature).toBe("repo-resolver-divergence");
    expect(ctx.extra).toMatchObject({
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "user-1",
    });
    expect(ctx.extra).not.toHaveProperty("repoUrl");
    expect(ctx.extra).not.toHaveProperty("installationId");
  });

  it("reprovision-non-member-claim-reset dedupes by (op, userId, claim) fingerprint", () => {
    const args = {
      userId: "user-1",
      op: "reprovision-non-member-claim-reset" as const,
      activeClaimWorkspaceId: "team-x",
      resolvedWorkspaceId: "user-1",
    };
    reportRepoResolverDivergence(args);
    reportRepoResolverDivergence(args);
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
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

describe("reportAgentReadinessSelfStop — agent-surface strand observability (#5733 Phase 1b)", () => {
  const base = {
    userId: "user-1",
    activeWorkspaceId: "754ee124",
    gitValid: true, // the FILE-pointer trap: lstat-valid yet strands in-bwrap
    gitKind: "file-pointer",
    gitdirEscapesWorkspace: true,
  };

  it("emits a DISTINCT agent_readiness_self_stop error (own Sentry issue group) carrying HASHED ws id + gitValid + shape; NO raw id/path/repoUrl/installationId", () => {
    reportAgentReadinessSelfStop(base);

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, ctx] = (reportSilentFallback as ReturnType<typeof vi.fn>).mock
      .calls[0];
    // Distinct message → its OWN issue group (NOT repo_resolver_divergence), so
    // the discoverability `jq length` counts it independently.
    expect((err as Error).message).toBe("agent_readiness_self_stop");
    expect(ctx.feature).toBe("agent-readiness-self-stop");
    expect(ctx.op).toBe("agent-readiness-self-stop");
    expect(ctx.extra).toMatchObject({
      // Pre-hashed: for a SOLO workspace this would equal the raw userId, so it
      // MUST be hashed (security #5733) — not emitted raw.
      activeWorkspaceIdHash: "hash-754ee124",
      gitValid: true,
      gitKind: "file-pointer",
      gitdirEscapesWorkspace: true,
    });
    // userId is present (pseudonymized to userIdHash at the emit boundary).
    expect(ctx.extra).toHaveProperty("userId");
    // The raw workspace-id-bearing fields must NOT leak (they == userId for solo).
    expect(ctx.extra).not.toHaveProperty("activeWorkspaceId");
    expect(ctx.extra).not.toHaveProperty("workspacePath");
    expect(ctx.extra).not.toHaveProperty("repoUrl");
    expect(ctx.extra).not.toHaveProperty("installationId");
  });

  it("dedupes by (userId, workspace, .git kind) — recurring strand emits once per process", () => {
    reportAgentReadinessSelfStop(base);
    reportAgentReadinessSelfStop(base);
    reportAgentReadinessSelfStop(base);
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
  });

  it("a SHAPE CHANGE (file-pointer → dir-invalid) re-fires (not over-deduped on workspace alone)", () => {
    reportAgentReadinessSelfStop(base);
    reportAgentReadinessSelfStop({ ...base, gitKind: "dir-invalid", gitValid: false });
    expect(reportSilentFallback).toHaveBeenCalledTimes(2);
  });

  // #5733 deliverable A/C — the widened event. The host-confirm verdict
  // (`gitRevParseValid`) makes the proxy-vs-invariant divergence visible in the
  // ONE event (gitValid=true lstat-says-ready, gitRevParseValid=false git-disagrees),
  // and the `source` tag distinguishes the host pre-heal emit from the C2 in-sandbox
  // backstop. NEITHER may carry the subprocess stderr / raw path.
  it("carries gitRevParseValid + source; the host confirm shows the proxy-vs-invariant divergence; NO stderr/path", () => {
    reportAgentReadinessSelfStop({
      userId: "user-1",
      activeWorkspaceId: "754ee124",
      gitValid: true,
      gitRevParseValid: false,
      gitKind: "dir-valid",
      source: "host-pre-heal",
    });
    const [, ctx] = (reportSilentFallback as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(ctx.extra).toMatchObject({
      gitValid: true,
      gitRevParseValid: false,
      gitKind: "dir-valid",
      source: "host-pre-heal",
    });
    // The git failure text (which embeds the raw `/workspaces/<id>/.git` path ==
    // raw userId for a solo workspace) must NEVER reach the event.
    expect(ctx.extra).not.toHaveProperty("stderr");
    expect(ctx.extra).not.toHaveProperty("error");
    expect(ctx.extra).not.toHaveProperty("workspacePath");
    expect(ctx.extra).not.toHaveProperty("gitdirTarget");
  });

  it("the same workspace+kind from DIFFERENT sources (host vs in-sandbox backstop) are NOT collapsed", () => {
    const shared = {
      userId: "user-1",
      activeWorkspaceId: "754ee124",
      gitValid: true,
      gitRevParseValid: false,
      gitKind: "dir-valid",
    };
    reportAgentReadinessSelfStop({ ...shared, source: "host-pre-heal" });
    reportAgentReadinessSelfStop({ ...shared, source: "in-sandbox-backstop" });
    expect(reportSilentFallback).toHaveBeenCalledTimes(2);
    const sources = (reportSilentFallback as ReturnType<typeof vi.fn>).mock.calls.map(
      (c) => c[1].extra.source,
    );
    expect(sources).toContain("host-pre-heal");
    expect(sources).toContain("in-sandbox-backstop");
  });

  it("source defaults to host-pre-heal when omitted (back-compat with the cold pre-heal emit)", () => {
    reportAgentReadinessSelfStop(base); // no `source`
    const [, ctx] = (reportSilentFallback as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(ctx.extra.source).toBe("host-pre-heal");
    // No host confirm ran on the pure-lstat pre-heal emit → gitRevParseValid absent.
    expect(ctx.extra).not.toHaveProperty("gitRevParseValid");
  });
});

describe("reportAgentReadinessProbeInconclusive — fail-OPEN breadcrumb (#5733)", () => {
  it("emits a DISTINCT op/issue-group (NOT the self-stop) with only the hashed workspace id", () => {
    reportAgentReadinessProbeInconclusive({
      userId: "user-1",
      activeWorkspaceId: "754ee124",
    });
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, ctx] = (reportSilentFallback as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect((err as Error).message).toBe("agent_readiness_probe_inconclusive");
    expect(ctx.op).toBe("agent-readiness-probe-inconclusive");
    expect(ctx.extra).toMatchObject({ activeWorkspaceIdHash: "hash-754ee124" });
    expect(ctx.extra).not.toHaveProperty("activeWorkspaceId");
    expect(ctx.extra).not.toHaveProperty("workspacePath");
  });

  it("dedupes per (userId, workspace) per process", () => {
    const args = { userId: "user-1", activeWorkspaceId: "754ee124" };
    reportAgentReadinessProbeInconclusive(args);
    reportAgentReadinessProbeInconclusive(args);
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
