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
// STORE that BOTH the dedup LIST read and the handler's own issue upsert write
// through, so the digest COUNT is the observable invariant — not "a mock fired".
//
// #7122: the spawned agent no longer files the issue. The HANDLER publishes it
// (validate -> upsertDigestIssue through the same fake client), so the spawn mock
// writes nothing to the store and only carries its final-message draft; the
// publish step is the store's one writer, which keeps realDigestCount() honest.
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { applyIssueListParams } from "./helpers/issue-list-params";

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
// from it (via the mocked probe octokit), and the handler's publish step creates
// and patches rows in it through the same client.
interface StoredIssue {
  title: string;
  body: string;
  created_at: string;
  number?: number;
  state?: "open" | "closed";
  user?: { type: string; login: string };
  pull_request?: unknown;
  labels?: string[];
}
let store: StoredIssue[];
let nextNumber: number;
// Errors consumed, in order, by successive `GET issues` calls (a fault injector).
let listFaults: unknown[];
// A digest issue authored by the app bot: the only author the upsert will PATCH.
const BOT = { type: "Bot", login: "soleur-ai[bot]" };

// #6714 Phase 3.4 — the SECOND half of the dedup substrate. The short-circuit
// used to fire on issue-presence ALONE (the wrong artifact); it now also requires
// the dated digest COMMITTED on the default branch. This set models that commit
// state, and safeCommitAndPr populates it, so run 2 dedups BECAUSE run 1's commit
// landed — the causal chain the production fix depends on. Seeding it directly
// would let a test dedup on a digest nothing ever committed.
let committedPaths: Set<string>;

const fakeRequest = vi.fn(
  async (route: string, params: Record<string, unknown> & { per_page?: number; path?: string }) => {
    if (route === "GET /repos/{owner}/{repo}/issues") {
      const fault = listFaults.shift();
      if (fault !== undefined) throw fault;
      // The fake ANSWERS THE QUESTION ASKED: state, labels, sort, direction and
      // per_page are applied, so a changed read shape cannot hide (a real GitHub page
      // that no longer holds today's digest makes the upsert file a duplicate).
      return { data: applyIssueListParams(store, params) };
    }
    if (route === "GET /repos/{owner}/{repo}/milestones") {
      return { data: [{ number: 7, title: "Post-MVP / Later" }] };
    }
    if (route === "POST /repos/{owner}/{repo}/issues") {
      const row: StoredIssue = {
        title: String(params.title),
        body: String(params.body),
        created_at: new Date(Date.now() + store.length).toISOString(),
        number: nextNumber++,
        state: "open",
        user: BOT,
        labels: Array.isArray(params.labels) ? (params.labels as string[]) : undefined,
      };
      store.push(row);
      return { data: { number: row.number } };
    }
    if (route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}") {
      const row = store.find((i) => i.number === params.issue_number);
      if (!row) throw new Error("PATCH of an unknown issue");
      row.body = String(params.body);
      return { data: { number: row.number } };
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

// The authoritative bot-login source the handler resolves (GET /app).
vi.mock("@/server/github-app", () => ({
  getAppSlug: () => Promise.resolve("soleur-ai"),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/inngest/functions/_cron-claude-eval-substrate", () => ({
  setupEphemeralWorkspace: (...a: unknown[]) => setupWorkspaceSpy(...a),
  teardownEphemeralWorkspace: (...a: unknown[]) => teardownSpy(...a),
  spawnClaudeEval: (...a: unknown[]) => spawnClaudeEvalSpy(...a),
  setOriginToken: vi.fn().mockResolvedValue(undefined),
  COMMUNITY_DISALLOWED_TOOLS: "Read,Glob,Grep,Write,Edit,MultiEdit,NotebookEdit,Task,Agent,Skill",
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
// postSentryHeartbeat and the #8726 deploy-deferral helpers REAL; stub only the spawn-adjacent
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

import {
  COMMUNITY_DIGEST_DIR,
  cronCommunityMonitorHandler,
} from "@/server/inngest/functions/cron-community-monitor";
import { validDraftFinalMessage } from "./helpers/community-draft";

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
// Derived from the handler's own constant (re-exported from the publication module),
// not mirrored as a second literal.
const DIGEST_PATH = `${COMMUNITY_DIGEST_DIR}${TODAY}-digest.md`;

const okSpawn = {
  ok: true, exitCode: 0, signal: null, abortedByTimeout: false,
  durationMs: 1000, stdoutTail: "", stderrTail: "",
  finalMessage: validDraftFinalMessage(), finalMessageTruncated: false,
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

// The publish step writes the rendered digest into the workspace: a REAL directory.
let tmpRoot: string;

beforeEach(() => {
  tmpRoot = mkdtempSync(join(tmpdir(), "community-dedup-"));
  mkdirSync(join(tmpRoot, "repo"), { recursive: true });
  // Freeze ONLY Date onto the same instant TODAY/YESTERDAY were derived from, so
  // the handler's runStartedAt resolves to TODAY. `toFake: ["Date"]` leaves
  // setTimeout real (the heartbeat 5xx-retry backoff and existing call-count
  // assertions are unaffected — this suite's fetch always resolves 202).
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(FROZEN);
  store = [];
  nextNumber = 5000;
  listFaults = [];
  committedPaths = new Set();
  fakeRequest.mockClear();
  setupWorkspaceSpy.mockResolvedValue({ ephemeralRoot: tmpRoot, spawnCwd: join(tmpRoot, "repo") });
  // #7122: the spawn only returns the agent's draft; it files nothing.
  spawnClaudeEvalSpy.mockImplementation(async () => okSpawn);
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
  rmSync(tmpRoot, { recursive: true, force: true });
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
    // The monitor issues are closed shortly after filing: seed it CLOSED, authored
    // by the app bot (the only author the handler's upsert will PATCH).
    store.push({
      title: `${TITLE_PREFIX} ${TODAY}`,
      body: "## Platform Status\n## Key Metrics\n3 followers",
      created_at: new Date().toISOString(),
      number: 4999,
      state: "closed",
      user: BOT,
    });
    expect(committedPaths.has(DIGEST_PATH)).toBe(false); // precondition

    const step = makeStep();
    await invoke(step);

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1); // recovered, not deduped
    expect(step.executed).toContain("claude-eval");
    // and the recovery genuinely committed the artifact this time
    expect(committedPaths.has(DIGEST_PATH)).toBe(true);
    // #7122: recovery REFRESHES the existing issue (PATCH) instead of filing a
    // second one, and the seeded stale body is replaced by the rendered digest.
    expect(realDigestCount()).toBe(1);
    expect(store[0].body).toMatch(/^Daily community digest for 2026-06-30/);
    expect(
      fakeRequest.mock.calls.some((c) => c[0] === "POST /repos/{owner}/{repo}/issues"),
    ).toBe(false);
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

  it("#7122 — the PUBLISH read fails CLOSED: an error there throws, no duplicate issue is created (counterpart to the fail-open dedup read)", async () => {
    // The first GET is the pre-spawn dedup read (fails open, above); the second is
    // the upsert's existence read. If it fell open to a create it would double-file
    // whenever the list read hiccups.
    listFaults = [new Error("GitHub 502"), new Error("GitHub 502")];
    const step = makeStep();

    const res = await invoke(step);

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
    expect(store).toHaveLength(0);
    expect(
      fakeRequest.mock.calls.some((c) => c[0] === "POST /repos/{owner}/{repo}/issues"),
    ).toBe(false);
    expect(res).toEqual({ ok: false });
    expect(safeCommitAndPrSpy).not.toHaveBeenCalled();
    expect(
      reportSilentFallbackSpy.mock.calls.some((c) => c[1]?.op === "community-publication-issue-failed"),
    ).toBe(true);
  });

  it("#7122 — the published issue is the handler's rendered digest, not agent text", async () => {
    await invoke(makeStep());
    expect(store).toHaveLength(1);
    expect(store[0].title).toBe(`${TITLE_PREFIX} ${TODAY}`);
    expect(store[0].body).toMatch(/^Daily community digest for 2026-06-30/);
    expect(store[0].user).toEqual(BOT);
  });

  it("#7122 — the pre-spawn dedup read and the upsert read are the SAME question (page size, order, state, label)", async () => {
    await invoke(makeStep());
    const reads = fakeRequest.mock.calls
      .filter((c) => c[0] === "GET /repos/{owner}/{repo}/issues")
      .map((c) => c[1] as Record<string, unknown>);
    expect(reads.length).toBeGreaterThanOrEqual(2); // the dedup read, then the upsert's
    const shape = (p: Record<string, unknown>) => ({
      per_page: p.per_page, sort: p.sort, direction: p.direction, state: p.state, labels: p.labels,
    });
    for (const r of reads) expect(shape(r)).toEqual(shape(reads[0]));
    expect(reads[0].per_page).toBe(10);
    expect(reads[0].direction).toBe("desc");
  });

  it("#7122 — with MORE older digests than a page holds, recovery still finds today's issue (newest-first) and PATCHes it instead of filing a duplicate", async () => {
    for (let i = 0; i < 15; i++) {
      store.push({
        title: `${TITLE_PREFIX} 2026-06-${String(i + 1).padStart(2, "0")}`,
        body: "old digest", state: "closed", user: BOT, number: 3000 + i,
        created_at: new Date(Date.UTC(2026, 5, 1, i)).toISOString(),
      });
    }
    store.push({
      title: `${TITLE_PREFIX} ${TODAY}`, body: "stale body of today's failed run", state: "closed",
      user: BOT, number: 3500, created_at: new Date(Date.UTC(2026, 5, 30, 1)).toISOString(),
    });
    expect(committedPaths.has(DIGEST_PATH)).toBe(false); // the commit never landed: recover

    await invoke(makeStep());

    expect(spawnClaudeEvalSpy).toHaveBeenCalledTimes(1);
    expect(realDigestCount()).toBe(1);
    expect(store.find((i) => i.number === 3500)!.body).toMatch(/^Daily community digest for 2026-06-30/);
    expect(
      fakeRequest.mock.calls.some((c) => c[0] === "POST /repos/{owner}/{repo}/issues"),
    ).toBe(false);
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
