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

// #6714 V3 — call-site coverage for the liveness verdict. Every emitter the
// module exports is listed: a wholesale factory REPLACES the module, so an
// omitted export would break any real sibling in the SUT's import graph.
const { digestLivenessMock, digestFileMock } = vi.hoisted(() => ({
  digestLivenessMock: vi.fn(),
  digestFileMock: vi.fn(),
}));

vi.mock("@/server/cron-liveness-marker", () => ({
  emitCronDigestLiveness: digestLivenessMock,
  emitCommunityDigestFile: digestFileMock,
  emitCronPersistResult: vi.fn(),
  emitCronPersistSkipped: vi.fn(),
  emitCronTier2Deferred: vi.fn(),
  emitCronDedupSkip: vi.fn(),
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
    // #5751 — the handler now runs a pre-spawn date-dedup. These throw-path
    // tests exercise the genuine-first-run flow, so the digest never pre-exists.
    digestIssueExistsForDate: vi.fn().mockResolvedValue(false),
    mintInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken"),
  };
});

// Pull the heartbeat POST URLs out of the fetch spy (the only network call).
const heartbeatUrls = () =>
  fetchSpy.mock.calls.map((c) => String(c[0] as string));

import {
  cronCommunityMonitorHandler,
  COMMUNITY_DIGEST_DIR,
} from "@/server/inngest/functions/cron-community-monitor";
import { DeployInProgressError } from "@/server/inngest/functions/_cron-shared";

/**
 * `throwOn` makes the named step reject, which is the only seam for simulating a
 * throw at a specific point in the handler body — the steps in the window
 * between verify-output and the persistence gate call module-local functions
 * (`readCollectorStatus`) that no `vi.mock` of a sibling module can intercept.
 */
function makeStep(throwOn?: string) {
  const executed: string[] = [];
  const step = {
    executed,
    run: vi.fn(async (name: string, cb: () => Promise<unknown>) => {
      executed.push(name);
      if (name === throwOn) throw new Error(`simulated failure in ${name}`);
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

// #6714 — the handler now CONSUMES safeCommitAndPr's return value (R16a: it was
// DISCARDED before, which is why a failed persistence could stay GREEN). A bare
// `{ ok: true }` is NOT a member of the SafeCommitResult union, so it reads as
// `status !== "committed"` → livenessOk=false → RED, failing every happy-path
// test here for a fixture reason rather than a real one.
//
// The clock is FROZEN (see beforeEach) rather than read live. The handler derives
// its digest path from `runStartedAt.slice(0,10)`; deriving the fixture's from a
// second, later `new Date()` made the two disagree across a UTC midnight boundary
// — a real (if rare) RED flake, reproduced by review. The sibling dedup suite
// already pins its clock this way; this suite was the inconsistent one.
const FROZEN = new Date("2026-06-30T12:00:00.000Z");
const TODAY = FROZEN.toISOString().slice(0, 10);
// Mirrors COMMUNITY_DIGEST_DIR, imported from the handler so a rename cannot
// silently desync the fixture from the value under test.
const DIGEST_PATH = `${COMMUNITY_DIGEST_DIR}${TODAY}-digest.md`;

/** A union-valid "committed" result whose `paths` includes today's digest. */
const committedWithDigest = () => ({
  status: "committed" as const,
  prNumber: 4242,
  branch: "cron/community-monitor",
  fileCount: 1,
  deletionCount: 0,
  paths: [DIGEST_PATH],
});

beforeEach(() => {
  // `toFake: ["Date"]` only — setTimeout stays real so the heartbeat retry
  // backoff and call-count assertions are unaffected (this suite's fetch always
  // resolves 202). Mirrors the dedup suite.
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(FROZEN);
  setupWorkspaceSpy.mockResolvedValue({ ephemeralRoot: "/tmp/x", spawnCwd: "/tmp/x/repo" });
  spawnClaudeEvalSpy.mockResolvedValue(okSpawn);
  resolveOutputAwareOkSpy.mockResolvedValue(true);
  safeCommitAndPrSpy.mockImplementation(async () => committedWithDigest());
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
  vi.useRealTimers();
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
    expect(reportSilentFallbackSpy.mock.calls.some((c) => c[1]?.op === "handler-body-threw")).toBe(true);
  });

  // CONTRACT CHANGE (#6714, ADR-126). Both tests below previously encoded the
  // #5728 behavior: a non-final throw rethrew for an Inngest retry, and a
  // trailing persistence throw on an output-present run stayed GREEN. Both are
  // now RED-and-terminal, deliberately.
  //
  // The retry was never capable of recovery. `setup-workspace` runs inside
  // step.run (memoized), and the handler's `finally` tears down ephemeralRoot
  // unconditionally — so a replay reads back a path that has already been
  // rm -rf'd, and safeCommitAndPr hits its `workspace-lost` guard, which
  // comments a misleading "PR withheld" + runbook pointer onto the operator's
  // issue. `retryEligible: false` at the finalize call drops that useless
  // replay, which is what lets livenessOk be honestly fail-closed.
  it("a non-final no-output throw posts ONE terminal error and does not rethrow", async () => {
    spawnClaudeEvalSpy.mockRejectedValue(new Error("transient blip"));
    const step = makeStep();

    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: false });
    expect(heartbeatUrls()[0]).toContain("?status=error");
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    // The honest terminal signal now includes the FAILED audit issue, which the
    // old rethrow-and-retry path deferred to a second attempt that could not
    // have succeeded.
    expect(step.executed).toContain("ensure-audit-issue");
  });

  it("a trailing safe-commit-pr throw turns the monitor RED (was GREEN pre-#6714)", async () => {
    // This was the "output-present run with a trailing persistence throw stays
    // GREEN" contract. It is a GREEN-with-no-artifact path by construction: the
    // issue landed, the commit did not, and the operator saw green. Under the
    // fail-closed default livenessOk is never set true, so the run reddens.
    resolveOutputAwareOkSpy.mockResolvedValue(true);
    safeCommitAndPrSpy.mockRejectedValue(new Error("git push failed"));
    const step = makeStep();

    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: false });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatUrls()[0]).toContain("?status=error");
    // still self-reports the underlying persistence failure
    expect(reportSilentFallbackSpy.mock.calls.some((c) => c[1]?.op === "handler-body-threw")).toBe(true);
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

// ---------------------------------------------------------------------------
// #6714 — the four-arm liveness table (R16a / R21)
// ---------------------------------------------------------------------------
// Every case below posts a heartbeat with `threw === false`, so
// finalizeOutputAwareHeartbeat computes `failed = threw && !heartbeatOk` = false
// and ALWAYS reaches the heartbeat step: the colour, not the presence, is the
// observable. Each case therefore asserts `?status=…` directly.
//
// resolveOutputAwareOk stays TRUE throughout — that is the whole point. Every
// one of these is a run whose ISSUE landed (so the pre-#6714 monitor was GREEN);
// only the committed ARTIFACT differs.
describe("cron-community-monitor — digest liveness (#6714)", () => {
  it("issue filed but persistence returned no-changes turns the monitor RED", async () => {
    // THE 2026-07-14 → 07-19 STATE. The return value was discarded (R16a), so
    // this ran GREEN for six days with nothing committed.
    safeCommitAndPrSpy.mockResolvedValue({ status: "no-changes" as const });
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: false });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatUrls()[0]).toContain("?status=error");
  });

  it("issue filed but persistence FAILED turns the monitor RED", async () => {
    safeCommitAndPrSpy.mockResolvedValue({
      status: "failed" as const,
      stage: "git-push",
      message: "remote rejected",
    });
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: false });
    expect(heartbeatUrls()[0]).toContain("?status=error");
  });

  it("a commit that landed OTHER files but not today's digest turns the monitor RED", async () => {
    // The subtle arm: status IS "committed" and a PR number exists, so every
    // pre-#6714 signal reads healthy — but the operator's artifact is absent.
    safeCommitAndPrSpy.mockResolvedValue({
      status: "committed" as const,
      prNumber: 4242,
      branch: "cron/community-monitor",
      fileCount: 1,
      deletionCount: 0,
      paths: ["knowledge-base/support/community/collector-status.json"],
    });
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: false });
    expect(heartbeatUrls()[0]).toContain("?status=error");
  });

  it("today's digest among SEVERAL committed files stays GREEN (membership, not position)", async () => {
    // V1 — every other fixture here carries a single-element `paths`, under which
    // `paths.includes(digestPath)` and `paths[0] === digestPath` are
    // indistinguishable. The allowlist is the whole community directory, so the
    // agent can legitimately land other files beside the digest and the digest
    // need not be first. Without this fixture, narrowing the production check to
    // a positional compare passes the whole suite.
    safeCommitAndPrSpy.mockResolvedValue({
      status: "committed" as const,
      prNumber: 4242,
      branch: "cron/community-monitor",
      fileCount: 3,
      deletionCount: 0,
      paths: [
        `${COMMUNITY_DIGEST_DIR}README.md`,
        `${COMMUNITY_DIGEST_DIR}platform-notes.md`,
        DIGEST_PATH,
      ],
    });
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: true });
    expect(heartbeatUrls()[0]).toContain("?status=ok");
  });

  it("a STALE digest from a prior date turns the monitor RED (the date anchor)", async () => {
    // V2 — the date anchor is the entire point of #6714, and nothing pinned it at
    // the liveness gate. Relaxing the production check to "some path ends in
    // -digest.md" passed every other test: a stale digest kept the monitor GREEN,
    // which is GREEN-with-no-CURRENT-artifact — the exact failure being closed.
    safeCommitAndPrSpy.mockResolvedValue({
      status: "committed" as const,
      prNumber: 4242,
      branch: "cron/community-monitor",
      fileCount: 1,
      deletionCount: 0,
      paths: [`${COMMUNITY_DIGEST_DIR}2026-06-29-digest.md`], // yesterday
    });
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: false });
    expect(heartbeatUrls()[0]).toContain("?status=error");
  });

  it("emits the liveness VERDICT with the arm that decided it, at its call site", async () => {
    // V3 — markers 2-5 had zero call-site coverage; only marker 1 was asserted
    // where it fires. This pins the one that makes a RED run diagnosable: marker
    // 1 already emitted status:"committed" from inside safeCommitAndPr, so
    // without a reason an operator cannot tell WHY the monitor reddened.
    safeCommitAndPrSpy.mockResolvedValue({
      status: "committed" as const,
      prNumber: 4242,
      branch: "cron/community-monitor",
      fileCount: 1,
      deletionCount: 0,
      paths: [`${COMMUNITY_DIGEST_DIR}2026-06-29-digest.md`], // stale
    });
    const step = makeStep();
    await invoke(step, 0, 2);

    expect(digestLivenessMock).toHaveBeenCalledWith(
      expect.objectContaining({
        cron: "cron-community-monitor",
        ok: 0,
        reason: "digest-absent-from-commit",
        attempt: 0,
      }),
    );
  });

  it("the digest-file marker carries the REAL attempt, not a constant", async () => {
    // The field exists solely to disambiguate replays: the stat runs outside
    // step.run, so it re-emits on attempt 1 — by which point the `finally` has
    // deleted the workspace, forcing present:0. Hardcoding attempt:0 would make
    // a healthy replayed run indistinguishable from an agent that never wrote
    // the file, which is exactly what this marker is supposed to tell apart.
    // Asserted on a NON-ZERO attempt, since attempt:0 cannot catch a constant.
    const step = makeStep();
    await invoke(step, 1, 2);

    expect(digestFileMock).toHaveBeenCalledWith(
      expect.objectContaining({ attempt: 1, digest_path: DIGEST_PATH }),
    );
  });

  it("a replay-resume with UNDETERMINED paths stays GREEN (R21 carve-out)", async () => {
    // On the replay-resume branch the allowlist scan never runs, so `paths` is
    // undefined — "NOT DETERMINED", never "nothing committed". Reading undefined
    // as absent would false-RED a run whose artifact genuinely landed.
    safeCommitAndPrSpy.mockResolvedValue({
      status: "committed" as const,
      prNumber: 4242,
      branch: "cron/community-monitor",
      fileCount: 0,
      deletionCount: 0,
      resumed: true as const,
    });
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: true });
    expect(heartbeatUrls()[0]).toContain("?status=ok");
  });

  it("UNDETERMINED paths WITHOUT the resumed marker turns the monitor RED", async () => {
    // The negative half of the R21 carve-out, and what makes `resumed`
    // load-bearing rather than decorative: only the replay-resume branch has a
    // legitimate reason to leave `paths` undetermined. Any other undetermined
    // shape is a drifted result contract, and voting GREEN on an unknown is the
    // precise failure #6714 exists to close.
    safeCommitAndPrSpy.mockResolvedValue({
      status: "committed" as const,
      prNumber: 4242,
      branch: "cron/community-monitor",
      fileCount: 0,
      deletionCount: 0,
    });
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: false });
    expect(heartbeatUrls()[0]).toContain("?status=error");
  });

  it("a throw BEFORE the persistence gate turns the monitor RED and does NOT retry", async () => {
    // THE EXPLOIT the fail-open default left open. The issue lands
    // (heartbeatOk=true), the agent writes the digest, then a step between
    // verify-output and the persistence gate throws. Under the old
    // initialised-true default: threw=true, heartbeatOk=true, livenessOk never
    // falsified → `failed = threw && !heartbeatOk` = FALSE → no retry → terminal
    // GREEN with nothing committed, on the FIRST attempt. Verbatim the shape
    // ADR-126 forbids.
    //
    // Simulated at the collector-status step, which sits in exactly that window.
    const step = makeStep("verify-collector-status");
    const res = await invoke(step, 0, 2); // attempt 0 of 2 — a retry IS available

    expect(res).toEqual({ ok: false });
    expect(heartbeatUrls()[0]).toContain("?status=error");
    // and it did NOT retry: a replay reads back an ephemeralRoot the `finally`
    // already deleted, so it could only produce a misleading workspace-lost
    // comment on the operator's issue. One terminal heartbeat, not a rethrow.
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(safeCommitAndPrSpy).not.toHaveBeenCalled();
  });

  it("the happy path still posts GREEN under the fail-closed default", async () => {
    // Guards the inversion against over-reddening. A fail-closed livenessOk is
    // only correct if the positive arm genuinely fires on a healthy run — if it
    // did not, every run would go RED and the monitor would be useless in the
    // opposite direction.
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: true });
    expect(heartbeatUrls()[0]).toContain("?status=ok");
  });

  it("a timed-out spawn whose issue landed turns the monitor RED (the no-else gate)", async () => {
    // The persistence gate had no `else`, so this skipped persistence silently.
    // heartbeatOk is true (the issue exists), so ONLY livenessOk can redden it.
    spawnClaudeEvalSpy.mockResolvedValue({ ...okSpawn, abortedByTimeout: true });
    const step = makeStep();
    const res = await invoke(step, 0, 2);

    expect(res).toEqual({ ok: false });
    expect(heartbeatUrls()[0]).toContain("?status=error");
    // and persistence was genuinely skipped, not merely reported red
    expect(safeCommitAndPrSpy).not.toHaveBeenCalled();
  });
});
