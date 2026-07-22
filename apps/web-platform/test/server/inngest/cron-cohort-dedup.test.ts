// #5786 — producer-side date-dedup cohort regression (extends the #5751
// cron-community-monitor fix to 7 more claude-eval crons).
//
// SOLE behavioral gate for the sweep: the per-cron test files are source-anchor
// (readFileSync) only. This parametrized suite drives each REAL handler through
// a FAKE octokit issue STORE that BOTH the dedup LIST read and the (mocked)
// spawn's create write through, so the digest COUNT is the observable invariant
// — not "a mock fired". Modeled on cron-community-monitor-dedup.test.ts.
//
// Fidelity guards (deepened plan):
//   - `_cron-shared` is PARTIAL-mocked via importOriginal so
//     digestIssueExistsForDate (+ finalizeOutputAwareHeartbeat, postSentryHeartbeat)
//     stay REAL — a full mock would let AC1 pass vacuously.
//   - the spawn-mock seeds, and realDigestCount keys on, the ROW-DERIVED title
//     `${row.titlePrefix} ${TODAY}${row.titleSuffix}` — NOT a hardcoded constant,
//     so a wrong per-cron prefix/suffix cannot pass vacuously.
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
// from it (via the mocked probe octokit), and the per-row spawn mock writes the
// digest into it (simulating the spawned agent's `gh issue create`).
interface StoredIssue { title: string; body: string; created_at: string }
let store: StoredIssue[];

const fakeRequest = vi.fn(
  async (
    route: string,
    params: { per_page?: number; state?: string; labels?: string },
  ) => {
    if (route === "GET /repos/{owner}/{repo}/issues") {
      // The dedup LIST read MUST query `state: "all"` — a regression to the
      // stale `state: "open"` (the #5751 root cause; roadmap-review's old
      // `--search` form) would miss campaign-calendar's create-and-close
      // heartbeat digest and re-introduce the double-file. Fail loudly here so
      // the behavioral cohort test — not just the cron-shared param unit test —
      // guards the `--state all` contract.
      if (params.state !== "all") {
        throw new Error(
          `dedup LIST read must use state:"all", got ${JSON.stringify(params.state)}`,
        );
      }
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

import { digestIssueExistsForDate } from "@/server/inngest/functions/_cron-shared";
import { cronRoadmapReviewHandler } from "@/server/inngest/functions/cron-roadmap-review";
import { cronContentGeneratorHandler } from "@/server/inngest/functions/cron-content-generator";
import { cronGrowthAuditHandler } from "@/server/inngest/functions/cron-growth-audit";
import { cronGrowthExecutionHandler } from "@/server/inngest/functions/cron-growth-execution";
import { cronCompetitiveAnalysisHandler } from "@/server/inngest/functions/cron-competitive-analysis";
import { cronSeoAeoAuditHandler } from "@/server/inngest/functions/cron-seo-aeo-audit";
import { cronCampaignCalendarHandler } from "@/server/inngest/functions/cron-campaign-calendar";

// Pin the clock so the handler's runStartedAt (`new Date()` at invoke time) and
// the fixtures' TODAY (derived at module-load) agree deterministically (a
// real-clock UTC-midnight crossing mid-run would desync them — flake).
const FROZEN = new Date("2026-06-30T12:00:00.000Z");
const TODAY = FROZEN.toISOString().slice(0, 10);

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

type AnyHandler = (args: {
  step: unknown;
  logger: unknown;
  attempt: number;
  maxAttempts: number;
}) => Promise<{ ok: boolean }>;

const invoke = (handler: AnyHandler, step: ReturnType<typeof makeStep>) =>
  handler({
    step: step as unknown,
    logger: logger as unknown,
    attempt: 0,
    maxAttempts: 2,
  });

const heartbeatUrls = () => fetchSpy.mock.calls.map((c) => String(c[0] as string));

// The exact canonical digest title for THIS row+date, minus the FAILED audit
// stub (byte-identical title, hardcoded body). Mirrors isRealScheduledDigest.
const realDigestCount = (titlePrefix: string, titleSuffix: string) =>
  store.filter(
    (i) =>
      i.title === `${titlePrefix} ${TODAY}${titleSuffix}` &&
      !i.body.startsWith("Automated FAILED self-report"),
  ).length;

interface Row {
  name: string;
  handler: AnyHandler;
  label: string;
  titlePrefix: string;
  titleSuffix: string;
  cronName: string;
}

const ROWS: Row[] = [
  {
    name: "cron-roadmap-review",
    handler: cronRoadmapReviewHandler as AnyHandler,
    label: "scheduled-roadmap-review",
    titlePrefix: "[Scheduled] Weekly Roadmap Review -",
    titleSuffix: "",
    cronName: "cron-roadmap-review",
  },
  {
    name: "cron-content-generator",
    handler: cronContentGeneratorHandler as AnyHandler,
    label: "scheduled-content-generator",
    titlePrefix: "[Scheduled] Content Generator -",
    titleSuffix: "",
    cronName: "cron-content-generator",
  },
  {
    name: "cron-growth-audit",
    handler: cronGrowthAuditHandler as AnyHandler,
    label: "scheduled-growth-audit",
    titlePrefix: "[Scheduled] Growth Audit -",
    titleSuffix: "",
    cronName: "cron-growth-audit",
  },
  {
    name: "cron-growth-execution",
    handler: cronGrowthExecutionHandler as AnyHandler,
    label: "scheduled-growth-execution",
    titlePrefix: "[Scheduled] Growth Execution -",
    titleSuffix: "",
    cronName: "cron-growth-execution",
  },
  {
    name: "cron-competitive-analysis",
    handler: cronCompetitiveAnalysisHandler as AnyHandler,
    label: "scheduled-competitive-analysis",
    titlePrefix: "[Scheduled] Competitive Analysis -",
    titleSuffix: "",
    cronName: "cron-competitive-analysis",
  },
  {
    name: "cron-seo-aeo-audit",
    handler: cronSeoAeoAuditHandler as AnyHandler,
    label: "scheduled-seo-aeo-audit",
    titlePrefix: "[Scheduled] SEO/AEO Audit -",
    titleSuffix: "",
    cronName: "cron-seo-aeo-audit",
  },
  {
    name: "cron-campaign-calendar",
    handler: cronCampaignCalendarHandler as AnyHandler,
    label: "scheduled-campaign-calendar",
    titlePrefix: "[Scheduled] Campaign Calendar -",
    titleSuffix: " (heartbeat)", // STEP 2.5 producer digest carries this suffix
    cronName: "cron-campaign-calendar",
  },
];

// Per-row spawn mock: simulate the agent filing TODAY's row-derived digest into
// the shared store. Re-installed each test so the title tracks the active row.
function seedSpawnFor(row: Row) {
  spawnClaudeEvalSpy.mockImplementation(async () => {
    store.push({
      title: `${row.titlePrefix} ${TODAY}${row.titleSuffix}`,
      body: "## Digest\nrow-derived real digest body",
      created_at: new Date().toISOString(),
    });
    return okSpawn;
  });
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(FROZEN);
  store = [];
  fakeRequest.mockClear();
  setupWorkspaceSpy.mockResolvedValue({ ephemeralRoot: "/tmp/x", spawnCwd: "/tmp/x/repo" });
  resolveOutputAwareOkSpy.mockResolvedValue(true);
  // #6714 — union-valid SafeCommitResult. None of the 7 cohort handlers consume
  // this return value today (only cron-community-monitor does, via its own
  // suite), so `paths` is omitted: on this arm that reads as "not determined",
  // which is exactly right for a cron with no artifact assertion. A bare
  // `{ ok: true }` was never a member of the union and would silently read as
  // `status !== "committed"` the moment any of these handlers starts checking.
  safeCommitAndPrSpy.mockResolvedValue({
    status: "committed" as const,
    prNumber: 4242,
    branch: "cron/cohort",
    fileCount: 1,
    deletionCount: 0,
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

describe("#5786 — producer-side date-dedup cohort (the 7-cron sweep)", () => {
  describe.each(ROWS)(
    "$name",
    ({ handler, titlePrefix, titleSuffix, cronName }) => {
      it("AC1 — two serialized same-date invocations file EXACTLY ONE digest", async () => {
        seedSpawnFor({ titlePrefix, titleSuffix } as Row);
        await invoke(handler, makeStep()); // first: no digest → spawns + files
        const secondStep = makeStep();
        await invoke(handler, secondStep); // second: sees first via fresh LIST → skips

        expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
        expect(realDigestCount(titlePrefix, titleSuffix)).toBe(1);
        // Root-cause guard: the dedup read MUST use the fresh LIST route (a
        // regression back to `--search '… in:title'` would not call this route).
        expect(
          fakeRequest.mock.calls.some(
            (c) => c[0] === "GET /repos/{owner}/{repo}/issues",
          ),
        ).toBe(true);
        // No upstream defer swallowed the run.
        expect(secondStep.executed).toContain("dedup-digest-check");
      });

      it("AC1b — the dedup-skip path posts a GREEN heartbeat and skips the eval", async () => {
        seedSpawnFor({ titlePrefix, titleSuffix } as Row);
        await invoke(handler, makeStep()); // seed today's digest
        fetchSpy.mockClear();

        const step = makeStep();
        const res = await invoke(handler, step);

        expect(res).toEqual({ ok: true });
        expect(step.executed).not.toContain("claude-eval");
        expect(step.executed).toContain("sentry-heartbeat");
        // campaign-calendar caveat: the skip MUST NOT fall through to
        // verify-output (whose run-window would false-RED the skip).
        expect(step.executed).not.toContain("verify-output");
        expect(fetchSpy).toHaveBeenCalledTimes(1);
        expect(heartbeatUrls()[0]).toContain("?status=ok");
      });

      it("AC2 — fail-OPEN: a LIST-read error spawns (a transient hiccup must not miss the digest)", async () => {
        seedSpawnFor({ titlePrefix, titleSuffix } as Row);
        fakeRequest.mockRejectedValueOnce(new Error("GitHub 502"));

        await invoke(handler, makeStep());

        expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
        expect(realDigestCount(titlePrefix, titleSuffix)).toBe(1);
        expect(
          reportSilentFallbackSpy.mock.calls.some(
            (c) => (c[1] as { op?: string })?.op === "digest-dedup-read-failed",
          ),
        ).toBe(true);
      });

      it("AC3 — a pre-existing FAILED audit stub (same dated title) does NOT suppress the real digest", async () => {
        seedSpawnFor({ titlePrefix, titleSuffix } as Row);
        store.push({
          title: `${titlePrefix} ${TODAY}${titleSuffix}`,
          body: `Automated FAILED self-report from \`${cronName}\`.`,
          created_at: new Date().toISOString(),
        });

        await invoke(handler, makeStep());

        expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1); // stub did NOT block
        expect(realDigestCount(titlePrefix, titleSuffix)).toBe(1);
      });
    },
  );

  // --- campaign-calendar-specific rows (the suffix variant) ---
  const CC = ROWS.find((r) => r.name === "cron-campaign-calendar")!;

  it("AC1c — campaign-calendar suffix is a load-bearing handler invariant (mutation-proof)", async () => {
    seedSpawnFor(CC);
    await invoke(CC.handler, makeStep());
    const secondStep = makeStep();
    await invoke(CC.handler, secondStep);

    // Positive: the handler's titleSuffix: " (heartbeat)" lets invocation #2 see
    // the suffixed seed → exactly one digest.
    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
    expect(realDigestCount(CC.titlePrefix, CC.titleSuffix)).toBe(1);

    // Mutation evidence: had the handler omitted titleSuffix, its dedup read
    // would have compared the suffixed seed against the BARE anchor → false →
    // invocation #2 would have re-spawned → 2 digests. Prove the REAL helper
    // returns false WITHOUT the suffix against this same suffixed store.
    const wouldMatchWithoutSuffix = await digestIssueExistsForDate({
      label: CC.label,
      date: TODAY,
      cronName: CC.cronName,
      titlePrefix: CC.titlePrefix,
      // titleSuffix omitted — the mutation
      octokit: { request: fakeRequest } as never,
    });
    expect(wouldMatchWithoutSuffix).toBe(false);
  });

  it("AC1d — campaign-calendar overdue-day (NEW>0): an `[Content] Overdue` issue does NOT suppress the spawn", async () => {
    seedSpawnFor(CC);
    // On an overdue day invocation #1 files `[Content] Overdue: …` issues and NO
    // `(heartbeat)` digest, so the dedup (anchored on the suffixed title) finds
    // nothing → spawn runs (fail-OPEN, documented partial-dedup asymmetry).
    store.push({
      title: `[Content] Overdue: Launch teaser — ${TODAY}`,
      body: "This piece is overdue.",
      created_at: new Date().toISOString(),
    });

    const step = makeStep();
    await invoke(CC.handler, step);

    expect(step.executed).toContain("dedup-digest-check");
    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1); // overdue issue did NOT dedup
  });
});
