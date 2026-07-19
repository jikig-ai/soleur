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

// #6714 Phase 3.4 — the SECOND half of the dedup substrate. The short-circuit
// used to fire on issue-presence ALONE (the wrong artifact); it now also requires
// the dated digest COMMITTED on the default branch. This set models that commit
// state, and safeCommitAndPr populates it, so run 2 dedups BECAUSE run 1's commit
// landed — the causal chain the production fix depends on. Seeding it directly
// would let a test dedup on a digest nothing ever committed.
let committedPaths: Set<string>;

const fakeRequest = vi.fn(
  async (route: string, params: { per_page?: number; path?: string }) => {
    if (route === "GET /repos/{owner}/{repo}/issues") {
      const sorted = [...store].sort((a, b) =>
        a.created_at < b.created_at ? 1 : -1,
      );
      return { data: sorted.slice(0, params.per_page ?? 30) };
    }
    if (route === "GET /repos/{owner}/{repo}/contents/{path}") {
      if (committedPaths.has(String(params.path))) {
        return { data: { path: params.path } };
      }
      // 404 is the EXPECTED negative ("not committed") and is the one status the
      // production read stays quiet about — any other status is reported as a
      // genuine read fault. Throwing a bare Error here would exercise the wrong
      // arm and emit a spurious reportSilentFallback.
      const err = new Error("Not Found") as Error & { status?: number };
      err.status = 404;
      throw err;
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
// Test Rec 1 (#5751 review) — pin the clock. The dedup read derives its date
// from runStartedAt (the handler's `new Date()` at invoke time) while these
// fixtures derive TODAY at module-load; a real-clock UTC-midnight crossing
// mid-run would desync them (flake). Freeze BOTH onto one fixed UTC instant so
// TODAY === the handler's runStartedAt.slice(0,10) deterministically.
const FROZEN = new Date("2026-06-30T12:00:00.000Z");
const TODAY = FROZEN.toISOString().slice(0, 10);
const YESTERDAY = new Date(FROZEN.getTime() - 86_400_000)
  .toISOString()
  .slice(0, 10);
// Mirrors COMMUNITY_DIGEST_DIR + the `<date>-digest.md` shape in the handler.
const DIGEST_PATH = `knowledge-base/support/community/${TODAY}-digest.md`;

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
// Mirror the production predicate (isRealScheduledDigest): the EXACT canonical
// digest title for TODAY, minus the FAILED audit stub (byte-identical title,
// hardcoded body). A loose endsWith(TODAY) here would count a coincidental-date
// issue and mis-score the invariant.
const realDigestCount = () =>
  store.filter(
    (i) =>
      i.title === `${TITLE_PREFIX} ${TODAY}` &&
      !i.body.startsWith("Automated FAILED self-report"),
  ).length;

beforeEach(() => {
  // Freeze ONLY Date onto the same instant TODAY/YESTERDAY were derived from, so
  // the handler's runStartedAt resolves to TODAY. `toFake: ["Date"]` leaves
  // setTimeout real (the heartbeat 5xx-retry backoff and existing call-count
  // assertions are unaffected — this suite's fetch always resolves 202).
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(FROZEN);
  store = [];
  committedPaths = new Set();
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
  // #6714 — union-valid SafeCommitResult (a bare `{ ok: true }` reads as
  // `status !== "committed"` → livenessOk=false → RED). Landing DIGEST_PATH in
  // `committedPaths` is what lets the NEXT run's dedup read find it.
  safeCommitAndPrSpy.mockImplementation(async () => {
    committedPaths.add(DIGEST_PATH);
    return {
      status: "committed" as const,
      prNumber: 4242,
      branch: "cron/community-monitor",
      fileCount: 1,
      deletionCount: 0,
      paths: [DIGEST_PATH],
    };
  });
  teardownSpy.mockResolvedValue(undefined);
  ensureAuditIssueSpy.mockResolvedValue(undefined);
  vi.stubEnv("SENTRY_INGEST_DOMAIN", "o4509.ingest.sentry.io");
  vi.stubEnv("SENTRY_PROJECT_ID", "4509999");
  vi.stubEnv("SENTRY_PUBLIC_KEY", "abcdef0123456789abcdef0123456789");
  fetchSpy = vi.fn().mockResolvedValue(new Response(null, { status: 202 }));
  vi.stubGlobal("fetch", fetchSpy);
});

afterEach(() => {
  vi.useRealTimers();
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
    // Test Rec 2 (#5751 review) — root-cause guard: the dedup read MUST use the
    // fresh LIST route. A future regression back to `--search '… in:title'`
    // (the H-C stale-index miss) would not call this route → fail here.
    expect(
      fakeRequest.mock.calls.some(
        (c) => c[0] === "GET /repos/{owner}/{repo}/issues",
      ),
    ).toBe(true);
  });

  it("#6714 — a digest ISSUE without the committed digest does NOT dedup; the run spawns", async () => {
    // The GREEN-with-no-artifact path the dedup itself created. Run 1 files a
    // genuine digest issue but loses the commit; run 2 used to see the issue,
    // short-circuit, and post GREEN with nothing landed. `committedPaths` stays
    // empty here, so the contents read 404s — "not proven committed" — and the
    // run must proceed to spawn rather than dedup on the wrong artifact.
    store.push({
      title: `${TITLE_PREFIX} ${TODAY}`,
      body: "## Platform Status\n## Key Metrics\n3 followers",
      created_at: new Date().toISOString(),
    });
    expect(committedPaths.has(DIGEST_PATH)).toBe(false); // precondition

    const step = makeStep();
    await invoke(step);

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1); // recovered, not deduped
    expect(step.executed).toContain("claude-eval");
    // and the recovery genuinely committed the artifact this time
    expect(committedPaths.has(DIGEST_PATH)).toBe(true);
  });

  it("#6714 — a digest issue WITH the committed digest still dedups (healthy path preserved)", async () => {
    // The positive control for the test above: the tightened gate must not turn
    // every dedup into a re-spawn, or it trades a missing digest for a duplicate
    // one every single day.
    store.push({
      title: `${TITLE_PREFIX} ${TODAY}`,
      body: "## Platform Status\n## Key Metrics\n3 followers",
      created_at: new Date().toISOString(),
    });
    committedPaths.add(DIGEST_PATH);

    const step = makeStep();
    const res = await invoke(step);

    expect(spawnClaudeEvalSpy).not.toHaveBeenCalled(); // deduped
    expect(res).toEqual({ ok: true });
    expect(heartbeatUrls()[0]).toContain("?status=ok");
  });

  it("a coincidental-date issue (title merely ends in today's date) does NOT suppress the digest", async () => {
    // `Investigate community drop <today>` ends in the date but is NOT the
    // canonical digest title. The positive-anchor predicate must let the genuine
    // digest through (the old endsWith(date) check would have suppressed it).
    store.push({
      title: `Investigate community drop ${TODAY}`,
      body: "Followers dropped — please look.",
      created_at: new Date().toISOString(),
    });

    await invoke(makeStep());

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
