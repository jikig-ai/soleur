// #5728 — cron-community-monitor throw-path heartbeat behaviour.
//
// SEPARATE test file (NOT folded into cron-community-monitor.test.ts) because
// that suite imports the REAL module for source-shape/import-time smoke tests;
// vitest hoists vi.mock to the top of a file and would clobber those real
// imports. Here we mock the substrate so the handler's control flow is driven
// directly.
//
// Pre-fix, a throw inside the catch-less inner try (claude-eval → verify-output
// → safe-commit-pr → sentry-heartbeat) propagated out of the function, so the
// single end-of-run sentry-heartbeat step NEVER ran → Sentry saw NO check-in →
// `missed` (not `error`). These tests pin the flag-pattern fix:
//   - final-attempt no-output throw → exactly one `?status=error` check-in
//   - non-final throw → NO heartbeat step + rethrow (Inngest retries; a memoized
//     step must not replay a stale signal)
//   - happy path → exactly one `ok`
//   - a trailing safe-commit-pr throw on an OUTPUT-PRESENT run stays GREEN
//   - DeployInProgressError is rethrown bare with NO heartbeat from BOTH the
//     existing first catch (setup-workspace) AND the new inner catch
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Short-circuit the inngest client startup-key check (same path next build uses).
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const reportSilentFallbackSpy = vi.fn();
const resolveOutputAwareOkSpy = vi.fn();
const ensureAuditIssueSpy = vi.fn();
const spawnClaudeEvalSpy = vi.fn();
const safeCommitAndPrSpy = vi.fn();
const setupWorkspaceSpy = vi.fn();
const teardownSpy = vi.fn();
// `fetch` is stubbed (real postSentryHeartbeat is kept), so the only network
// call the handler makes is the heartbeat POST — asserting on it is the faithful
// end-to-end check. NOTE: postSentryHeartbeat is intentionally NOT mocked: the
// REAL finalizeOutputAwareHeartbeat calls its module-internal postSentryHeartbeat
// reference, which a mocked export would not intercept.
let fetchSpy: ReturnType<typeof vi.fn>;

vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/inngest/functions/_cron-claude-eval-substrate", () => ({
  setupEphemeralWorkspace: (...a: unknown[]) => setupWorkspaceSpy(...a),
  teardownEphemeralWorkspace: (...a: unknown[]) => teardownSpy(...a),
  spawnClaudeEval: (...a: unknown[]) => spawnClaudeEvalSpy(...a),
  KILL_ESCALATION_MS: 5000,
}));

vi.mock("@/server/inngest/functions/_cron-safe-commit", () => ({
  safeCommitAndPr: (...a: unknown[]) => safeCommitAndPrSpy(...a),
}));

// Partial mock — keep DeployInProgressError, finalizeOutputAwareHeartbeat,
// postSentryHeartbeat REAL; stub only the spawn-adjacent deps.
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>();
  return {
    ...actual,
    resolveOutputAwareOk: (...a: unknown[]) => resolveOutputAwareOkSpy(...a),
    ensureScheduledAuditIssue: (...a: unknown[]) => ensureAuditIssueSpy(...a),
    mintInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken"),
  };
});

// Pull the heartbeat POST URLs out of the fetch spy (the only network call).
const heartbeatUrls = () =>
  fetchSpy.mock.calls.map((c) => String(c[0] as string));

import { cronCommunityMonitorHandler } from "@/server/inngest/functions/cron-community-monitor";
import { DeployInProgressError } from "@/server/inngest/functions/_cron-shared";

function makeStep() {
  const executed: string[] = [];
  const step = {
    executed,
    run: vi.fn(async (name: string, cb: () => Promise<unknown>) => {
      executed.push(name);
      return cb();
    }),
  };
  return step;
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

type HandlerArg = Parameters<typeof cronCommunityMonitorHandler>[0];

const invoke = (
  step: ReturnType<typeof makeStep>,
  attempt: number,
  maxAttempts: number,
) =>
  cronCommunityMonitorHandler({
    step: step as unknown as HandlerArg["step"],
    logger: logger as unknown as HandlerArg["logger"],
    attempt,
    maxAttempts,
  } as HandlerArg);

const okSpawn = {
  ok: true,
  exitCode: 0,
  signal: null,
  abortedByTimeout: false,
  durationMs: 1000,
  stdoutTail: "",
  stderrTail: "",
};

beforeEach(() => {
  setupWorkspaceSpy.mockResolvedValue({ ephemeralRoot: "/tmp/x", spawnCwd: "/tmp/x/repo" });
  spawnClaudeEvalSpy.mockResolvedValue(okSpawn);
  resolveOutputAwareOkSpy.mockResolvedValue(true);
  safeCommitAndPrSpy.mockResolvedValue({ ok: true });
  teardownSpy.mockResolvedValue(undefined);
  ensureAuditIssueSpy.mockResolvedValue(undefined);
  // Real postSentryHeartbeat requires these env vars + a fetch to actually POST.
  vi.stubEnv("SENTRY_INGEST_DOMAIN", "o4509.ingest.sentry.io");
  vi.stubEnv("SENTRY_PROJECT_ID", "4509999");
  vi.stubEnv("SENTRY_PUBLIC_KEY", "abcdef0123456789abcdef0123456789");
  fetchSpy = vi.fn().mockResolvedValue(new Response(null, { status: 202 }));
  vi.stubGlobal("fetch", fetchSpy);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  vi.clearAllMocks();
});

describe("cron-community-monitor — throw-path heartbeat (#5728)", () => {
  it("happy path posts exactly one ok check-in (no double-signal)", async () => {
    const step = makeStep();
    const res = await invoke(step, 0, 2);
    expect(res).toEqual({ ok: true });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatUrls()[0]).toContain("?status=ok");
    expect(step.executed).toContain("sentry-heartbeat");
    expect(step.executed).not.toContain("ensure-audit-issue");
  });

  it("final-attempt no-output throw posts exactly one ?status=error (loud, not silent missed)", async () => {
    spawnClaudeEvalSpy.mockRejectedValue(new Error("claude-eval blew up"));
    const step = makeStep();
    const res = await invoke(step, 1, 2); // final attempt (index 1 of maxAttempts 2)
    expect(res).toEqual({ ok: false });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatUrls()[0]).toContain("?status=error");
    expect(step.executed).toContain("ensure-audit-issue");
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
  });

  it("non-final throw runs NO heartbeat step and rethrows (Inngest retries; no memoized stale signal)", async () => {
    spawnClaudeEvalSpy.mockRejectedValue(new Error("transient blip"));
    const step = makeStep();
    await expect(invoke(step, 0, 2)).rejects.toThrow();
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(step.executed).not.toContain("sentry-heartbeat");
    expect(step.executed).not.toContain("ensure-audit-issue");
  });

  it("a trailing safe-commit-pr throw on an OUTPUT-PRESENT run stays GREEN (one ok, persistence failure self-reports)", async () => {
    resolveOutputAwareOkSpy.mockResolvedValue(true);
    safeCommitAndPrSpy.mockRejectedValue(new Error("git push failed"));
    const step = makeStep();
    const res = await invoke(step, 0, 2);
    expect(res).toEqual({ ok: true });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatUrls()[0]).toContain("?status=ok"); // NOT error — digest exists
    expect(reportSilentFallbackSpy).toHaveBeenCalled(); // the throw self-reports
  });

  it("DeployInProgressError from the inner body is rethrown bare with NO heartbeat", async () => {
    spawnClaudeEvalSpy.mockRejectedValue(new DeployInProgressError("cron-community-monitor", 1234));
    const step = makeStep();
    await expect(invoke(step, 1, 2)).rejects.toBeInstanceOf(DeployInProgressError);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("DeployInProgressError from setup-workspace (first catch) is rethrown bare with NO error heartbeat", async () => {
    setupWorkspaceSpy.mockRejectedValue(new DeployInProgressError("cron-community-monitor", 5678));
    const step = makeStep();
    await expect(invoke(step, 1, 2)).rejects.toBeInstanceOf(DeployInProgressError);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
