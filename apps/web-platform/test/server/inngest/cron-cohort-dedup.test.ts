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

// #6750 — the SECOND observable substrate: fake DEFAULT-BRANCH state. The dedup
// hardening probes it before short-circuiting.
//
// Written ONLY by the safeCommitAndPr mock, never seeded directly by a test.
// Seeding it directly would let a test dedup on an artifact that no run
// committed — which is precisely the vacuity the hardening exists to close, so
// a fixture that allowed it would assert nothing.
let committedPaths: string[];
let committedMessages: string[];

const emitDigestLivenessSpy = vi.fn();
const emitPersistSkippedSpy = vi.fn();
const emitDedupSkipSpy = vi.fn();

const fakeRequest = vi.fn(
  async (
    route: string,
    params: { per_page?: number; state?: string; labels?: string; path?: string },
  ) => {
    if (route === "GET /repos/{owner}/{repo}/contents/{path}") {
      // EXISTENCE probe — cron-growth-audit's date-named report only.
      if (committedPaths.includes(String(params.path))) {
        return { data: { path: params.path } };
      }
      // A 404 is the EXPECTED negative and MUST carry `status: 404`:
      // digestCommittedOnDefaultBranch stays quiet on 404 but reports any OTHER
      // status to Sentry, so a bare Error would exercise the wrong arm and fire a
      // spurious reportSilentFallback that has nothing to do with the assertion.
      throw Object.assign(new Error("Not Found"), { status: 404 });
    }
    if (route === "GET /repos/{owner}/{repo}/commits") {
      // FRESHNESS probe — the other six. An empty window is a 200 with an empty
      // array, never a 404.
      return { data: committedMessages.map((m) => ({ commit: { message: m } })) };
    }
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

// Partial override: keep every other emitter real so a sibling export cannot be
// dropped (a wholesale factory would delete the ones this file does not name).
vi.mock("@/server/cron-liveness-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/cron-liveness-marker")>()),
  emitCronDigestLiveness: (...a: unknown[]) => emitDigestLivenessSpy(...a),
  emitCronPersistSkipped: (...a: unknown[]) => emitPersistSkippedSpy(...a),
  emitCronDedupSkip: (...a: unknown[]) => emitDedupSkipSpy(...a),
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
import { cronArchitectureDiagramSyncHandler } from "@/server/inngest/functions/cron-architecture-diagram-sync";

// Pin the clock so the handler's runStartedAt (`new Date()` at invoke time) and
// the fixtures' TODAY (derived at module-load) agree deterministically (a
// real-clock UTC-midnight crossing mid-run would desync them — flake).
const FROZEN = new Date("2026-06-30T12:00:00.000Z");
const TODAY = FROZEN.toISOString().slice(0, 10);

const okSpawn = {
  ok: true, exitCode: 0, signal: null, abortedByTimeout: false,
  durationMs: 1000, stdoutTail: "", stderrTail: "",
};

function makeStep(throwOn?: string, thrown?: Error) {
  const executed: string[] = [];
  const step = {
    executed,
    run: vi.fn(async (name: string, cb: () => Promise<unknown>) => {
      executed.push(name);
      // Injected failure point (#6750): lets a scenario throw from a NAMED step
      // without stubbing the handler's internals, so the try/catch, the liveness
      // application and the terminal heartbeat all run for real.
      if (name === throwOn) throw thrown ?? new Error(`injected failure in ${name}`);
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
  /** #6750 — null means EXEMPT: no safeCommitAndPr, so no liveness table. */
  producerClass: "A" | "B" | null;
  /** The message safeCommitAndPr writes; the freshness probe's anchor. */
  commitMessage: string | null;
  artifact: {
    /** A path that SATISFIES this producer's liveness predicate. */
    hit: string;
    /** Fails the predicate by a hair — the anchor is the point. */
    nearMiss: string;
    /**
     * Allowlisted (so safeCommitAndPr would ship it) but NOT the artifact.
     *
     * `null` where no such path EXISTS: cron-campaign-calendar's Class A
     * predicate is exact allowlist membership, so its allowlist and its artifact
     * set coincide and "allowlisted but not the artifact" is unreachable. That is
     * a property of the producer, asserted below, not a gap in the fixture.
     */
    unrelated: string | null;
  } | null;
}

const ROWS: Row[] = [
  {
    name: "cron-roadmap-review",
    handler: cronRoadmapReviewHandler as AnyHandler,
    label: "scheduled-roadmap-review",
    titlePrefix: "[Scheduled] Weekly Roadmap Review -",
    titleSuffix: "",
    cronName: "cron-roadmap-review",
      producerClass: null,
      commitMessage: null,
      artifact: null,
  },
  {
    name: "cron-content-generator",
    handler: cronContentGeneratorHandler as AnyHandler,
    label: "scheduled-content-generator",
    titlePrefix: "[Scheduled] Content Generator -",
    titleSuffix: "",
    cronName: "cron-content-generator",
      producerClass: "B",
      commitMessage: "feat(content): auto-generate article",
      artifact: {
        hit: "plugins/soleur/docs/blog/2026-06-30-a-post.md",
        nearMiss: "plugins/soleur/docs-blog/2026-06-30-a-post.md",
        unrelated: "knowledge-base/marketing/notes.md",
      },
  },
  {
    name: "cron-growth-audit",
    handler: cronGrowthAuditHandler as AnyHandler,
    label: "scheduled-growth-audit",
    titlePrefix: "[Scheduled] Growth Audit -",
    titleSuffix: "",
    cronName: "cron-growth-audit",
      producerClass: "A",
      commitMessage: "docs: weekly growth audit",
      artifact: {
        hit: `knowledge-base/marketing/audits/soleur-ai/${TODAY}-content-audit.md`,
        // YESTERDAY's report. Allowlisted and plausible, so only the DATE anchor
        // rejects it — the near-miss the Class A predicate exists for.
        nearMiss: "knowledge-base/marketing/audits/soleur-ai/2026-06-29-content-audit.md",
        unrelated: "knowledge-base/product/roadmap.md",
      },
  },
  {
    name: "cron-growth-execution",
    handler: cronGrowthExecutionHandler as AnyHandler,
    label: "scheduled-growth-execution",
    titlePrefix: "[Scheduled] Growth Execution -",
    titleSuffix: "",
    cronName: "cron-growth-execution",
      producerClass: "B",
      commitMessage: "fix(growth): biweekly keyword optimization",
      artifact: {
        hit: "knowledge-base/marketing/seo-refresh-queue.md",
        nearMiss: "knowledge-base/marketingx/seo-refresh-queue.md",
        unrelated: "plugins/soleur/docs/guide.md",
      },
  },
  {
    name: "cron-competitive-analysis",
    handler: cronCompetitiveAnalysisHandler as AnyHandler,
    label: "scheduled-competitive-analysis",
    titlePrefix: "[Scheduled] Competitive Analysis -",
    titleSuffix: "",
    cronName: "cron-competitive-analysis",
      producerClass: "B",
      commitMessage: "docs: update competitive intelligence report",
      artifact: {
        hit: "knowledge-base/product/competitive-intelligence.md",
        nearMiss: "knowledge-base/productx/competitive-intelligence.md",
        unrelated: "knowledge-base/sales/battlecards/acme.md",
      },
  },
  {
    name: "cron-seo-aeo-audit",
    handler: cronSeoAeoAuditHandler as AnyHandler,
    label: "scheduled-seo-aeo-audit",
    titlePrefix: "[Scheduled] SEO/AEO Audit -",
    titleSuffix: "",
    cronName: "cron-seo-aeo-audit",
      producerClass: "B",
      commitMessage: "fix(seo): weekly SEO/AEO audit fixes",
      artifact: {
        hit: "plugins/soleur/docs/index.md",
        nearMiss: "plugins/soleur/docsx/index.md",
        unrelated: "plugins/soleur/docs/guide.md",
      },
  },
  {
    name: "cron-campaign-calendar",
    handler: cronCampaignCalendarHandler as AnyHandler,
    label: "scheduled-campaign-calendar",
    titlePrefix: "[Scheduled] Campaign Calendar -",
    titleSuffix: " (heartbeat)", // STEP 2.5 producer digest carries this suffix
    cronName: "cron-campaign-calendar",
      producerClass: "A",
      commitMessage: "ci: update campaign calendar and content-strategy review",
      artifact: {
        hit: "knowledge-base/marketing/content-strategy.md",
        // The Class A predicate is EXACT allowlist membership (.includes), so a
        // sibling that merely shares the prefix must NOT satisfy it.
        nearMiss: "knowledge-base/marketing/content-strategy.md.bak",
        // #6750 review: no longer degenerate. The predicate now anchors on the
        // MANDATED file (content-strategy.md), so campaign-calendar.md is a
        // genuine allowlisted-but-not-the-artifact path and the Class A RED arm
        // is reachable for this producer too.
        unrelated: "knowledge-base/marketing/campaign-calendar.md",
      },
  },
  {
    // R4 — this row is NEW. The handler had zero executable coverage before
    // #6750: absent from ROWS and with no per-file suite, while being the one
    // producer that has never landed an artifact at all.
    name: "cron-architecture-diagram-sync",
    handler: cronArchitectureDiagramSyncHandler as AnyHandler,
    label: "scheduled-architecture-diagram-sync",
    titlePrefix: "[Scheduled] Architecture Diagram Sync -",
    titleSuffix: "",
    cronName: "cron-architecture-diagram-sync",
    producerClass: "B",
    commitMessage: "docs(arch): weekly architecture diagram sync",
    artifact: {
      hit: "knowledge-base/engineering/architecture/diagrams/model.c4",
      nearMiss: "knowledge-base/engineering/architecture/diagramsx/model.c4",
      unrelated: "knowledge-base/engineering/architecture/diagrams/views.c4",
    },
  },
];

// Per-row spawn mock: simulate the agent filing TODAY's row-derived digest into
// the shared store. Re-installed each test so the title tracks the active row.
// #6750 — the commit mock records what it "landed" on the fake default branch,
// so the dedup hardening's probes observe real evidence. This is the ONLY writer
// of committedPaths/committedMessages; see the note on their declaration.
//
// Returns a >=2-element `paths` deliberately: production calls `.some`/`.includes`
// on it, and a single-element fixture cannot tell membership from position.
function seedCommitFor(row: Row, override?: Record<string, unknown>) {
  safeCommitAndPrSpy.mockImplementation(async () => {
    // artifact NOT first — membership, not position.
    const paths = row.artifact
      ? [row.artifact.unrelated, row.artifact.hit].filter((x): x is string => x !== null)
      : [];
    const result = {
      status: "committed" as const,
      paths,
      prNumber: 4242,
      branch: "cron/cohort",
      fileCount: paths.length,
      deletionCount: 0,
      ...override,
    };
    const landed = (result.paths as string[] | undefined) ?? [];
    if (result.status === "committed") {
      committedPaths.push(...landed);
      // Model what actually lands on `main`: safeCommitAndPr's PR title is
      // `<commitMessage> <run date>` and GitHub's squash merge renders the
      // subject as `<PR title> (#N)`. Recording the BARE message would let a
      // date-bound anchor fail for a fixture reason, and — worse — would let a
      // date-blind anchor pass, hiding the cross-midnight defect.
      if (row.commitMessage) {
        committedMessages.push(`${row.commitMessage} ${TODAY} (#4242)`);
      }
    }
    return result;
  });
}

function seedSpawnFor(row: Row, spawnOverride?: Record<string, unknown>) {
  spawnClaudeEvalSpy.mockImplementation(async () => {
    store.push({
      title: `${row.titlePrefix} ${TODAY}${row.titleSuffix}`,
      body: "## Digest\nrow-derived real digest body",
      created_at: new Date().toISOString(),
    });
    return { ...okSpawn, ...spawnOverride };
  });
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(FROZEN);
  store = [];
  committedPaths = [];
  committedMessages = [];
  fakeRequest.mockClear();
  setupWorkspaceSpy.mockResolvedValue({ ephemeralRoot: "/tmp/x", spawnCwd: "/tmp/x/repo" });
  resolveOutputAwareOkSpy.mockResolvedValue(true);
  // #6750 — every cohort handler now CONSUMES this return value, so the shared
  // default must be union-valid AND carry `paths`. Omitting `paths` (the pre-#6750
  // default) reads as "not determined" and, without `resumed`, is contract-drift →
  // RED, which would false-fail every dedup test for a fixture reason. Per-row
  // staging is installed by seedCommitFor() alongside the spawn mock.
  safeCommitAndPrSpy.mockResolvedValue({
    status: "committed" as const,
    paths: [],
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
    (row) => {
      const { handler, titlePrefix, titleSuffix, cronName } = row;
      it("AC1 — two serialized same-date invocations file EXACTLY ONE digest", async () => {
        seedSpawnFor(row);
        seedCommitFor(row);
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
        seedSpawnFor(row);
        seedCommitFor(row);
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
        seedSpawnFor(row);
        seedCommitFor(row);
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
        seedSpawnFor(row);
        seedCommitFor(row);
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
    seedCommitFor(CC);
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
    seedCommitFor(CC);
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

// ===========================================================================
// #6750 — handler-local liveness (ADR-126 amendment), all 7 cohort producers.
// ===========================================================================
// heartbeatOk answers "did a labelled ISSUE land". livenessOk answers "did the
// artifact the operator actually CONSUMES get committed". Before this, the
// second question was never asked, so a run that filed its issue and committed
// nothing posted GREEN — for six days, in the incident ADR-126 records.
const LIVENESS_ROWS = ROWS.filter((r) => r.producerClass !== null);

/** Drive ONE fresh run (empty store ⇒ no dedup ⇒ the eval + persistence path). */
async function runFresh(
  row: Row,
  opts: {
    commit?: Record<string, unknown>;
    spawn?: Record<string, unknown>;
    step?: ReturnType<typeof makeStep>;
  } = {},
) {
  seedSpawnFor(row, opts.spawn);
  seedCommitFor(row, opts.commit);
  const step = opts.step ?? makeStep();
  const res = await invoke(row.handler, step).catch((e: Error) => e);
  return { res, step };
}

/** The colour of the single terminal check-in. */
const terminalStatus = () => {
  const urls = heartbeatUrls();
  return urls.length === 0 ? "none" : urls[urls.length - 1].includes("?status=ok") ? "ok" : "error";
};

const livenessCalls = () =>
  emitDigestLivenessSpy.mock.calls.map((c) => c[0] as Record<string, unknown>);

describe("#6750 — handler-local liveness across the cohort", () => {
  it("covers every non-exempt cohort producer (cardinality guard)", () => {
    // Without this a filter that silently matched nothing would make every
    // describe.each below vacuous — zero cases is a passing suite.
    expect(LIVENESS_ROWS).toHaveLength(7);
    expect(LIVENESS_ROWS.map((r) => r.name)).toContain("cron-architecture-diagram-sync");
    // Both classes must be represented or the table's split is dead code.
    expect(LIVENESS_ROWS.filter((r) => r.producerClass === "A")).toHaveLength(2);
    expect(LIVENESS_ROWS.filter((r) => r.producerClass === "B")).toHaveLength(5);
  });

  it("cron-roadmap-review stays EXEMPT — it calls safeCommitAndPr zero times", () => {
    // Stated as an assertion so its untouched dedup block does not read as an
    // oversight: no remedy phrased in terms of that helper's return value can
    // reach a cron that never calls it.
    const exempt = ROWS.filter((r) => r.producerClass === null);
    expect(exempt.map((r) => r.name)).toEqual(["cron-roadmap-review"]);
  });

  describe.each(LIVENESS_ROWS)("$name (class $producerClass)", (row) => {
    const isA = row.producerClass === "A";
    const art = row.artifact!;

    // --- scenario 1 -------------------------------------------------------
    it("happy path: the artifact is in the commit → exactly ONE ok check-in", async () => {
      const { res } = await runFresh(row);
      expect(res).toEqual({ ok: true });
      expect(fetchSpy).toHaveBeenCalledTimes(1); // no double-signal
      expect(terminalStatus()).toBe("ok");
      expect(livenessCalls()).toHaveLength(1);
      expect(livenessCalls()[0].ok).toBe(1);
      // The two classes report GREEN for DIFFERENT reasons, and the distinction
      // is the honest part. Class A proves the consumed artifact landed. Class B
      // cannot — it can only say "a non-empty commit under my allowlist landed" —
      // so it gets its own reason rather than borrowing Class A's. Conflating
      // them would rebuild the blind spot in the marker stream.
      expect(livenessCalls()[0].reason).toBe(
        isA ? "digest-committed" : "allowlisted-commit-no-artifact",
      );
    });

    // --- scenario 5 (membership, not position) ----------------------------
    it("the artifact among SEVERAL committed files stays GREEN — membership, not position", async () => {
      const { res } = await runFresh(row, {
        commit: { paths: [art.unrelated ?? "docs/other.md", "README.md", art.hit] },
      });
      expect(res).toEqual({ ok: true });
      expect(livenessCalls()[0].ok).toBe(1);
    });

    // --- scenario 2 -------------------------------------------------------
    it(`no-changes → ${isA ? "RED (deterministic producer must write)" : "GREEN (a no-diff run is healthy)"}`, async () => {
      const { res } = await runFresh(row, { commit: { status: "no-changes", paths: undefined } });
      expect(res).toEqual({ ok: !isA });
      expect(terminalStatus()).toBe(isA ? "error" : "ok");
      expect(livenessCalls()[0]).toMatchObject({
        ok: isA ? 0 : 1,
        reason: isA ? "persistence-not-committed" : "no-changes-change-conditional",
      });
    });

    // --- scenario 3 -------------------------------------------------------
    it("failed → RED for BOTH classes", async () => {
      const { res } = await runFresh(row, { commit: { status: "failed", paths: undefined } });
      expect(res).toEqual({ ok: false });
      expect(terminalStatus()).toBe("error");
      expect(livenessCalls()[0]).toMatchObject({ ok: 0, reason: "persistence-not-committed" });
    });

    // --- scenario 4 + 6 (the near-miss) -----------------------------------
    it("committed the NEAR-MISS path only → RED for BOTH classes", async () => {
      // The near-miss is a hair off the predicate: YESTERDAY's date for the
      // date-anchored producer, a prefix-sibling directory for the others.
      //
      // This is the load-bearing non-vacuity evidence for Class B. Its predicate
      // reduces to `paths.length > 0` in production (safeCommitAndPr pre-filters
      // to the allowlist), so a reader could reasonably suspect it asserts
      // nothing. A NON-EMPTY commit that is nonetheless RED here proves the
      // membership half is really evaluated.
      const { res } = await runFresh(row, { commit: { paths: [art.nearMiss] } });
      expect(res).toEqual({ ok: false });
      expect(livenessCalls()[0]).toMatchObject({
        ok: 0,
        reason: "digest-absent-from-commit",
      });
    });

    it("committed an ALLOWLISTED non-artifact path only → RED for A, GREEN for B (the class split, isolated)", async () => {
      // Same shape as above but the path IS allowlisted, so the ONLY thing that
      // can separate the two outcomes is the producer class. Pairing this with
      // the near-miss case pins both halves of the Class B predicate.
      if (art.unrelated === null) {
        // Degenerate by design: this producer's predicate IS its allowlist, so
        // every allowlisted path is an artifact. Assert that coincidence rather
        // than skipping — a silent skip would hide a later allowlist widening
        // that quietly created a non-artifact allowlisted path.
        const { res } = await runFresh(row, { commit: { paths: [art.hit] } });
        expect(res).toEqual({ ok: true });
        return;
      }
      const { res } = await runFresh(row, { commit: { paths: [art.unrelated] } });
      expect(res).toEqual({ ok: !isA });
      expect(livenessCalls()[0]).toMatchObject({
        ok: isA ? 0 : 1,
        reason: isA ? "digest-absent-from-commit" : "allowlisted-commit-no-artifact",
      });
    });

    // --- scenario 7 -------------------------------------------------------
    it("paths: [] → treated as artifact-ABSENT, not undetermined", async () => {
      const { res } = await runFresh(row, { commit: { paths: [] } });
      expect(res).toEqual({ ok: false });
      expect(livenessCalls()[0]).toMatchObject({ ok: 0, reason: "digest-absent-from-commit" });
    });

    // --- scenario 8 -------------------------------------------------------
    it("undetermined paths WITH resumed → GREEN (the one legitimate undetermined shape)", async () => {
      const { res } = await runFresh(row, {
        commit: { paths: undefined, resumed: true },
      });
      expect(res).toEqual({ ok: true });
      expect(livenessCalls()[0]).toMatchObject({ ok: 1, reason: "undetermined-replay-resume" });
    });

    // --- scenario 9 -------------------------------------------------------
    it("undetermined paths WITHOUT resumed → RED (contract drift; never vote GREEN on an unknown)", async () => {
      const { res } = await runFresh(row, { commit: { paths: undefined } });
      expect(res).toEqual({ ok: false });
      expect(livenessCalls()[0]).toMatchObject({ ok: 0, reason: "undetermined-contract-drift" });
    });

    // --- scenario 10 ------------------------------------------------------
    it("a throw inside the guarded body → terminal RED with NO retry", async () => {
      const { res, step } = await runFresh(row, { step: makeStep("safe-commit-pr") });
      // retryEligible:false makes it terminal: the heartbeat step RUNS and posts
      // error, rather than being skipped for a replay that cannot recover.
      expect(res).toEqual({ ok: false });
      expect(step.executed).toContain("sentry-heartbeat");
      expect(terminalStatus()).toBe("error");
    });

    // --- scenario 12 ------------------------------------------------------
    it("timed-out spawn whose ISSUE landed → RED, and persistence is reported as SKIPPED", async () => {
      const { res, step } = await runFresh(row, { spawn: { abortedByTimeout: true } });
      expect(res).toEqual({ ok: false });
      expect(step.executed).not.toContain("safe-commit-pr");
      expect(emitPersistSkippedSpy).toHaveBeenCalledTimes(1);
      expect(emitPersistSkippedSpy.mock.calls[0][0]).toEqual({
        cron: row.cronName,
        reason: "timeout",
      });
      expect(livenessCalls()[0]).toMatchObject({ ok: 0, reason: "persistence-skipped" });
    });

    // --- F5: the persistence-skipped "red" arm (zero calls before this) ----
    it("spawn ran but the issue never landed → persistence SKIPPED with reason=red", async () => {
      // resolveOutputAwareOk is stubbed true in beforeEach and was never
      // overridden anywhere in this suite, so heartbeatOk === false was never
      // instantiated: the "red" arm and this whole path had no coverage, and
      // hardcoding the reason to "timeout" survived the full suite.
      resolveOutputAwareOkSpy.mockResolvedValue(false);
      const { res, step } = await runFresh(row);
      expect(res).toEqual({ ok: false });
      expect(step.executed).not.toContain("safe-commit-pr");
      expect(emitPersistSkippedSpy).toHaveBeenCalledTimes(1);
      expect(emitPersistSkippedSpy.mock.calls[0][0]).toEqual({
        cron: row.cronName,
        reason: "red",
      });
      expect(livenessCalls()[0]).toMatchObject({ ok: 0, reason: "persistence-skipped" });
    });

    // --- scenario 13 (V1, the P0) -----------------------------------------
    it("dedup: a digest ISSUE WITHOUT the committed artifact does NOT short-circuit — the run spawns", async () => {
      // Run 1 files the issue but its commit is LOST.
      await runFresh(row, { commit: { status: "failed", paths: undefined } });
      expect(store.length).toBeGreaterThan(0); // the issue really is there
      expect(committedPaths).toHaveLength(0); // ...and nothing landed
      spawnClaudeEvalSpy.mockClear();

      // Run 2 sees the issue. Pre-#6750 it deduped and posted GREEN with nothing
      // landed — the dated 2026-07-14 -> 07-19 shape.
      seedSpawnFor(row);
      seedCommitFor(row);
      const step = makeStep();
      await invoke(row.handler, step);

      expect(step.executed).toContain("dedup-digest-committed-check");
      expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1); // it RECOVERED

      // F3 — the marker must record the RECOVERY arm, not just the healthy one.
      // This is the only operator-reachable signal separating "recovered from a
      // green-with-no-artifact" from "healthy dedup"; hardcoding it to 1, or
      // moving the emit inside the gate, previously survived the whole suite.
      expect(emitDedupSkipSpy).toHaveBeenCalledTimes(1);
      expect(emitDedupSkipSpy.mock.calls[0][0]).toEqual({
        cron: row.cronName,
        date: TODAY,
        digest_committed: 0,
      });

      // The COST of recovering, pinned honestly rather than wished away: the
      // re-spawned agent files its own dated issue, so the operator now has TWO
      // issues with the same dated title for the same day. GitHub permits
      // duplicate titles and nothing upstream dedups them. This is the accepted
      // negative recorded in the ADR amendment — two issues plus a landed
      // artifact beats one issue and nothing. What must NOT happen is unbounded
      // growth, so the count is pinned exactly.
      expect(realDigestCount(row.titlePrefix, row.titleSuffix)).toBe(2);
    });

    // --- scenario 14 ------------------------------------------------------
    it("dedup: issue AND artifact both present → short-circuits GREEN (healthy path preserved)", async () => {
      await runFresh(row); // lands both
      expect(committedPaths.length).toBeGreaterThan(0);
      spawnClaudeEvalSpy.mockClear();
      fetchSpy.mockClear();

      const step = makeStep();
      const res = await invoke(row.handler, step);

      expect(res).toEqual({ ok: true });
      expect(spawnClaudeEvalSpy).not.toHaveBeenCalled();
      expect(terminalStatus()).toBe("ok");
    });

    // --- the dedup marker fires on BOTH arms ------------------------------
    it("the dedup-skip marker records the decision on BOTH the healthy and the recovery arm", async () => {
      await runFresh(row); // run 1: issue + artifact
      emitDedupSkipSpy.mockClear();
      seedSpawnFor(row);
      seedCommitFor(row);
      await invoke(row.handler, makeStep()); // run 2: healthy dedup
      expect(emitDedupSkipSpy).toHaveBeenCalledTimes(1);
      expect(emitDedupSkipSpy.mock.calls[0][0]).toEqual({
        cron: row.cronName,
        date: TODAY,
        digest_committed: 1,
      });
    });

    // --- scenario 15 (R11) ------------------------------------------------
    it("a liveness-RED run does not create a SECOND issue for the same date", async () => {
      const before = store.length;
      await runFresh(row, { commit: { status: "no-changes", paths: undefined } });
      // Lowering heartbeatOk makes onBeforeHeartbeat fire ensureScheduledAuditIssue.
      // That write is real and is an accepted negative of this change; what must
      // NOT happen is a duplicate dated digest.
      expect(realDigestCount(row.titlePrefix, row.titleSuffix)).toBeLessThanOrEqual(1);
      expect(store.length).toBeGreaterThanOrEqual(before);
    });

    // --- ADR-029 leak guard ------------------------------------------------
    it("the liveness marker's field set is EXACTLY the declared five (leak guard)", async () => {
      await runFresh(row);
      // toEqual, not toMatchObject: any ADDED field fails the build. This
      // logger's residual exposure is its `redact` KEY SET — a top-level
      // `token`/`secret`/`password`/`authorization` would ship verbatim — so the
      // guard that matters here is credential-shaped keys, not user ids (those
      // are still pseudonymized downstream by Vector's pii_scrub_structured).
      expect(livenessCalls()[0]).toEqual({
        cron: row.cronName,
        run_id: expect.any(String),
        attempt: expect.any(Number),
        ok: expect.any(Number),
        reason: expect.any(String),
      });
    });
  });

  // --- scenario 11: the NAMED RESIDUAL, asserted as what it is -------------
  it("DeployInProgressError rethrows bare with NO heartbeat — a NAMED RESIDUAL, not a safety property", async () => {
    const row = LIVENESS_ROWS[0];
    const { DeployInProgressError } = await import(
      "@/server/inngest/functions/_cron-shared"
    );
    const { res, step } = await runFresh(row, {
      step: makeStep("safe-commit-pr", new DeployInProgressError(row.cronName, 1234)),
    });
    // It propagates, so Inngest retries — and that retry fires the exact hazard
    // retryEligible exists to close, because the workspace is already gone. This
    // is recorded in the ADR-126 amendment as residual 1, NOT fixed here.
    expect(res).toBeInstanceOf(DeployInProgressError);
    expect(step.executed).not.toContain("sentry-heartbeat");
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
