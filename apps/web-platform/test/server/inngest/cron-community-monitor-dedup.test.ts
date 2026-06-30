// #5751 — cron-community-monitor producer-side date-dedup regression.
//
// Phase 0 verdict: H-A (multiple serialized invocations) COMPOUNDED by H-C (the
// in-prompt DEDUP RULE read the STALE search index and missed the first issue).
// On 2026-06-30 BOTH digests (#5737 07:04Z, #5740 07:08Z) were filed before the
// 08:00 cron → two manual-trigger invocations. routine_runs has NO rows for the
// three double-file dates (06-20/06-21/06-30) while every clean day has exactly
// one. concurrency:{scope:"fn",limit:1} serializes the two invocations, so the
// fix is a handler-side FRESH-LIST date-dedup that short-circuits the second.
//
// SEAM (per the deepened plan): the existing heartbeat test mocks BOTH the spawn
// AND ensureScheduledAuditIssue, so "issue-count == 1" there is only a proxy.
// Here we drive the REAL digestIssueExistsForDate through a FAKE octokit issue
// STORE that BOTH the dedup LIST read and the (mocked) spawn's create write
// through, so the digest COUNT is the observable invariant — not "a mock fired".
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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
let fetchSpy: ReturnType<typeof vi.fn>;

// Fake GitHub issue store — the observable substrate. The dedup LIST read pulls
// from it (via the mocked probe octokit), and the spawn mock writes the digest
// into it (simulating the spawned agent's `gh issue create`).
interface StoredIssue { title: string; body: string; created_at: string }
let store: StoredIssue[];

const fakeRequest = vi.fn(
  async (route: string, params: { per_page?: number }) => {
    if (route === "GET /repos/{owner}/{repo}/issues") {
      const sorted = [...store].sort((a, b) =>
        a.created_at < b.created_at ? 1 : -1,
      );
      return { data: sorted.slice(0, params.per_page ?? 30) };
    }
    throw new Error(`unexpected octokit route ${route}`);
  },
);

vi.mock("@/server/github/probe-octokit", () => ({
  createProbeOctokit: () => Promise.resolve({ request: fakeRequest }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/inngest/functions/_cron-claude-eval-substrate", () => ({
  setupEphemeralWorkspace: (...a: unknown[]) => setupWorkspaceSpy(...a),
  teardownEphemeralWorkspace: (...a: unknown[]) => teardownSpy(...a),
  spawnClaudeEval: (...a: unknown[]) => spawnClaudeEvalSpy(...a),
  makeThrewSpawnResult: () => ({
    ok: false, exitCode: -1, signal: null, abortedByTimeout: false,
    durationMs: 0, stdoutTail: "", stderrTail: "",
  }),
  KILL_ESCALATION_MS: 5000,
}));

vi.mock("@/server/inngest/functions/_cron-safe-commit", () => ({
  safeCommitAndPr: (...a: unknown[]) => safeCommitAndPrSpy(...a),
}));

// Partial mock — keep digestIssueExistsForDate, finalizeOutputAwareHeartbeat,
// postSentryHeartbeat, DeployInProgressError REAL; stub only the spawn-adjacent
// deps so the dedup read + skip-path heartbeat are exercised end-to-end.
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

import { cronCommunityMonitorHandler } from "@/server/inngest/functions/cron-community-monitor";

const TITLE_PREFIX = "[Scheduled] Community Monitor -";
const TODAY = new Date().toISOString().slice(0, 10);
const YESTERDAY = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);

const okSpawn = {
  ok: true, exitCode: 0, signal: null, abortedByTimeout: false,
  durationMs: 1000, stdoutTail: "", stderrTail: "",
};

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
const invoke = (step: ReturnType<typeof makeStep>) =>
  cronCommunityMonitorHandler({
    step: step as unknown as HandlerArg["step"],
    logger: logger as unknown as HandlerArg["logger"],
    attempt: 0,
    maxAttempts: 2,
  } as HandlerArg);

const heartbeatUrls = () => fetchSpy.mock.calls.map((c) => String(c[0] as string));
const realDigestCount = () =>
  store.filter(
    (i) => i.title.endsWith(TODAY) && !i.body.startsWith("Automated FAILED self-report"),
  ).length;

beforeEach(() => {
  store = [];
  fakeRequest.mockClear();
  setupWorkspaceSpy.mockResolvedValue({ ephemeralRoot: "/tmp/x", spawnCwd: "/tmp/x/repo" });
  // The spawn simulates the agent filing TODAY's digest into the shared store.
  spawnClaudeEvalSpy.mockImplementation(async () => {
    store.push({
      title: `${TITLE_PREFIX} ${TODAY}`,
      body: "## Platform Status\n## Key Metrics\n3 followers",
      created_at: new Date().toISOString(),
    });
    return okSpawn;
  });
  resolveOutputAwareOkSpy.mockResolvedValue(true);
  safeCommitAndPrSpy.mockResolvedValue({ ok: true });
  teardownSpy.mockResolvedValue(undefined);
  ensureAuditIssueSpy.mockResolvedValue(undefined);
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

describe("cron-community-monitor — producer-side date-dedup (#5751)", () => {
  it("two serialized same-date invocations file EXACTLY ONE digest (invariant via fake store)", async () => {
    await invoke(makeStep()); // first: no existing digest → spawns + files
    await invoke(makeStep()); // second: sees the first via fresh LIST → short-circuits

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
    expect(realDigestCount()).toBe(1);
  });

  it("the dedup-skip path posts a healthy OK heartbeat (no false-RED) and returns ok", async () => {
    await invoke(makeStep()); // seed today's digest
    fetchSpy.mockClear();

    const step = makeStep();
    const res = await invoke(step);

    expect(res).toEqual({ ok: true });
    expect(step.executed).not.toContain("claude-eval"); // skipped
    expect(step.executed).toContain("sentry-heartbeat");
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatUrls()[0]).toContain("?status=ok");
  });

  it("a pre-existing FAILED audit stub (same dated title) does NOT suppress the real digest", async () => {
    store.push({
      title: `${TITLE_PREFIX} ${TODAY}`,
      body: "Automated FAILED self-report from `cron-community-monitor`.",
      created_at: new Date().toISOString(),
    });

    await invoke(makeStep());

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1); // stub did NOT block
    expect(realDigestCount()).toBe(1);
  });

  it("a pre-existing `- FAILED` no-platform issue does NOT suppress the real digest", async () => {
    store.push({
      title: `${TITLE_PREFIX} FAILED`,
      body: "Only GitHub and HN enabled — misconfiguration.",
      created_at: new Date().toISOString(),
    });

    await invoke(makeStep());

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
    expect(realDigestCount()).toBe(1);
  });

  it("fails OPEN: a LIST-read error spawns (a transient hiccup must not miss the digest)", async () => {
    fakeRequest.mockRejectedValueOnce(new Error("GitHub 502"));

    await invoke(makeStep());

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
    expect(realDigestCount()).toBe(1);
  });

  it("date anchor is replay-stable: yesterday's digest does NOT suppress today's", async () => {
    store.push({
      title: `${TITLE_PREFIX} ${YESTERDAY}`,
      body: "## Platform Status\nyesterday",
      created_at: new Date(Date.now() - 86_400_000).toISOString(),
    });

    await invoke(makeStep());

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
    expect(realDigestCount()).toBe(1);
  });
});
