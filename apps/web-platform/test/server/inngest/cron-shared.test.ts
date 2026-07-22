// #4689/#4686/#4684 — output-aware Sentry heartbeat.
//
// `verifyScheduledIssueCreated` is the read-only probe that closes the
// silent-no-op gap: a scheduled producer can exit 0 without ever creating
// its `scheduled-<task>` issue, and the old `ok: spawnResult.ok` heartbeat
// then stayed GREEN. These tests pin the helper's contract:
//   1. returns true when a labeled issue exists at/after the run-window start
//   2. returns false when the only matching issue predates the window
//      (the regression that must turn the monitor RED)
//   3. returns false when the repo has no matching issue at all
//   4. read-only: issues a GET, never a create/POST
//   5. throws on an invalid sinceIso rather than silently red-flagging
//      a healthy producer with a NaN lower bound
//
// The octokit is injected (the `octokit?` param) so the test drives the
// GitHub read shape directly without standing up the App-JWT mint path.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const reportSilentFallbackSpy = vi.fn();
const warnSilentFallbackSpy = vi.fn();
// #4861 — postSentryHeartbeat routes its unset/malformed-env skip through the
// debounced warn wrapper. The wrapper's own 5-min TTL bounding is unit-tested
// in observability's TtlDedupMap suite; here it forwards to the warn spy so the
// op/key/errorClass contract can be asserted.
const mirrorWarnWithDebounceSpy = vi.fn(
  (err: unknown, ctx: unknown, _key: string, _errorClass: string) =>
    warnSilentFallbackSpy(err, ctx),
);
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: (...a: unknown[]) => warnSilentFallbackSpy(...a),
  mirrorWarnWithDebounce: (...a: unknown[]) =>
    (mirrorWarnWithDebounceSpy as (...x: unknown[]) => void)(...a),
}));

// #cost-attribution (plan Phase 2, AC4c) — spy the marker helper that
// postAnthropicMessage emits into when a `markerSource` is threaded.
const { emitClaudeCostMarkerSpy } = vi.hoisted(() => ({
  emitClaudeCostMarkerSpy: vi.fn(),
}));
vi.mock("@/server/claude-cost-marker", () => ({
  emitClaudeCostMarker: emitClaudeCostMarkerSpy,
}));

// mintInstallationToken (#5046) mints via the App-JWT probe path, NOT any
// ambient GH_TOKEN, and threads the least-privilege scope to
// generateInstallationToken. Mock both dependencies so the scope-threading
// contract can be asserted without the live GitHub mint.
const { generateInstallationTokenSpy, probeRequestSpy } = vi.hoisted(() => ({
  generateInstallationTokenSpy: vi.fn(),
  probeRequestSpy: vi.fn(),
}));
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: (...a: unknown[]) => generateInstallationTokenSpy(...a),
}));
vi.mock("@/server/github/probe-octokit", () => ({
  createProbeOctokit: () => Promise.resolve({ request: probeRequestSpy }),
}));

import {
  AnthropicApiError,
  classifyEvalFatal,
  deferIfTier2Cron,
  DEFAULT_CRON_TOKEN_PERMISSIONS,
  digestIssueExistsForDate,
  ensureDedupIssue,
  ensureScheduledAuditIssue,
  formatTailForSentry,
  getAnthropicAdminReport,
  isRealScheduledDigest,
  mintInstallationToken,
  postAnthropicMessage,
  postSentryHeartbeat,
  REPO_NAME,
  resolveBestEffortEvalOk,
  resolveOutputAwareOk,
  ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS,
  TIER2_DEFERRED_CRONS,
  verifyScheduledIssueCreated,
} from "@/server/inngest/functions/_cron-shared";
import type { Octokit } from "@octokit/core";

function octokitReturning(issues: Array<{ updated_at: string }>) {
  const request = vi.fn().mockResolvedValue({ data: issues });
  // The helper only ever calls `.request`; cast through unknown so the
  // stub satisfies the structural param type without the full Octokit API.
  return { request } as unknown as Parameters<
    typeof verifyScheduledIssueCreated
  >[0]["octokit"] & { request: typeof request };
}

const RUN_START = "2026-05-31T09:00:00.000Z";

afterEach(() => {
  reportSilentFallbackSpy.mockClear();
  warnSilentFallbackSpy.mockClear();
});

// D6 (#5018) — Tier-2 deferral guard. Sentry env is unset in this suite, so
// postSentryHeartbeat is a no-op; we assert the guard's control-flow contract.
describe("deferIfTier2Cron (Tier-2 deferral guard)", () => {
  const makeStep = () => ({
    run: vi.fn(async (_id: string, fn: () => Promise<unknown>) => fn()),
  });
  const makeLogger = () =>
    ({ warn: vi.fn(), info: vi.fn(), error: vi.fn() }) as unknown as Parameters<
      typeof deferIfTier2Cron
    >[0]["logger"];

  it("does NOT defer cron-bug-fixer — RESTORED (#5199): returns false, no heartbeat, spawns normally", async () => {
    // #5199 emptied TIER2_DEFERRED_CRONS (bug-fixer was the last member; the
    // stale-bot-PR watchdog was extended to bot-fix/* so it could be restored).
    // deferIfTier2Cron is now a defensive no-op for EVERY cron — an empty set
    // short-circuits has() to false, so no positive (defer) path is reachable.
    const step = makeStep();
    const logger = makeLogger();
    const deferred = await deferIfTier2Cron({
      cronName: "cron-bug-fixer",
      sentryMonitorSlug: "scheduled-bug-fixer",
      step: step as unknown as Parameters<typeof deferIfTier2Cron>[0]["step"],
      logger,
    });
    expect(deferred).toBe(false);
    expect(step.run).not.toHaveBeenCalled();
    expect(logger.warn).not.toHaveBeenCalled();
  });

  it("does NOT defer the Tier-1 roadmap-review cron: returns false, no heartbeat", async () => {
    const step = makeStep();
    const logger = makeLogger();
    const deferred = await deferIfTier2Cron({
      cronName: "cron-roadmap-review",
      sentryMonitorSlug: "scheduled-roadmap-review",
      step: step as unknown as Parameters<typeof deferIfTier2Cron>[0]["step"],
      logger,
    });
    expect(deferred).toBe(false);
    expect(step.run).not.toHaveBeenCalled();
  });

  it("roadmap-review (#5004, Tier-1) is NOT in the deferred set; bug-fixer is now RESTORED too (#5199)", () => {
    expect(TIER2_DEFERRED_CRONS.has("cron-roadmap-review")).toBe(false);
    // #5199 restored the 7 mergeMode:"auto" crons — growth-audit included —
    // and finally cron-bug-fixer (the watchdog was extended to bot-fix/*).
    expect(TIER2_DEFERRED_CRONS.has("cron-growth-audit")).toBe(false);
    expect(TIER2_DEFERRED_CRONS.has("cron-bug-fixer")).toBe(false);
  });

  // #6602: the expenses verify_by scheduler is a dispatch-hybrid (mint token +
  // workflow_dispatch), never Tier-2 deferred. Asserted here so the sibling-set
  // sweep sees this dependent when EXPECTED_CRON_FUNCTIONS grows.
  it("expenses-verify-by (#6602, dispatch-hybrid) is NOT in the deferred set", () => {
    expect(TIER2_DEFERRED_CRONS.has("cron-expenses-verify-by")).toBe(false);
  });

  // #6657: cron-gh-pages-cert-reissue is an event-triggered live-infra
  // remediation (no schedule, no git, no PR) — never Tier-2 deferred. Asserted
  // here so the sibling-set sweep sees this dependent when EXPECTED_CRON_FUNCTIONS
  // grows with a new event-triggered cron.
  it("gh-pages-cert-reissue (#6657, event-triggered) is NOT in the deferred set", () => {
    expect(TIER2_DEFERRED_CRONS.has("cron-gh-pages-cert-reissue")).toBe(false);
  });

  // #5046 PR-2 Phase 2.C (AC-P2.12): the hook's relax-minimal (Task/Skill
  // allow) unblocks the two audit crons whose only denied construct was the
  // Task catch-all.
  it("agent-native-audit + legal-audit are RESTORED (out of the deferred set) — #5046 PR-2", () => {
    expect(TIER2_DEFERRED_CRONS.has("cron-agent-native-audit")).toBe(false);
    expect(TIER2_DEFERRED_CRONS.has("cron-legal-audit")).toBe(false);
  });

  it("ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS is exactly contents:read + issues:write (#5046 PR-2)", () => {
    expect(ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS).toEqual({
      contents: "read",
      issues: "write",
    });
    // Push/PR capability must stay denied at the token layer for the
    // issue-creator crons — defense-in-depth beneath the containment hook.
    expect(ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS).not.toHaveProperty("pull_requests");
    expect(ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS.contents).not.toBe("write");
  });

  it("ALL Tier-2 crons restored — TIER2_DEFERRED_CRONS is EMPTY (#5199)", () => {
    // #5199 final: the PR-5200 stale-bot-PR watchdog was extended to bot-fix/*
    // (this PR), so cron-bug-fixer — the last deferred cron — is now restored.
    // The Tier-2 boundary is fully retired; the set is empty.
    for (const cron of [
      "cron-campaign-calendar",
      "cron-community-monitor",
      "cron-competitive-analysis",
      "cron-content-generator",
      "cron-growth-audit",
      "cron-growth-execution",
      "cron-seo-aeo-audit",
      "cron-bug-fixer",
    ]) {
      expect(TIER2_DEFERRED_CRONS.has(cron)).toBe(false);
    }
    expect(TIER2_DEFERRED_CRONS.size).toBe(0);
  });

  it("cron-ux-audit is RESTORED — no longer Tier-2 deferred (#5199)", () => {
    expect(TIER2_DEFERRED_CRONS.has("cron-ux-audit")).toBe(false);
  });

  it("cron-architecture-diagram-sync is live — not Tier-2 deferred (#5631)", () => {
    expect(TIER2_DEFERRED_CRONS.has("cron-architecture-diagram-sync")).toBe(false);
  });

  it("cron-domain-model-drift is live — not Tier-2 deferred (#5872)", () => {
    // New dispatch-hybrid drift cron added to EXPECTED_CRON_FUNCTIONS; it is not
    // a deferred Tier-2 cron (the set is retired/empty), so it participates in
    // the watchdog purview immediately.
    expect(TIER2_DEFERRED_CRONS.has("cron-domain-model-drift")).toBe(false);
  });

  it("cron-ghcr-token-minter is live — not Tier-2 deferred (#6031)", () => {
    // The GHCR installation-token minter does NO git operations (it mints a
    // token and writes to Doppler), so it needs no CRON_BASH_ALLOWLISTS entry and
    // is not a deferred Tier-2 cron — added to EXPECTED_CRON_FUNCTIONS but
    // participating in the watchdog purview immediately.
    expect(TIER2_DEFERRED_CRONS.has("cron-ghcr-token-minter")).toBe(false);
  });
});

describe("verifyScheduledIssueCreated", () => {
  it("returns true when a labeled issue was created at/after the run window", async () => {
    const octokit = octokitReturning([
      { updated_at: "2026-05-31T09:30:08.000Z" },
    ]);
    const result = await verifyScheduledIssueCreated({
      label: "scheduled-roadmap-review",
      sinceIso: RUN_START,
      octokit,
    });
    expect(result).toBe(true);
  });

  it("returns FALSE when the newest matching issue predates the run window (the silent-no-op regression)", async () => {
    // The producer exited 0 but created nothing this run; the only labeled
    // issue is last week's. A pre-fix exit-code-only heartbeat would have
    // reported ok:true here — this assertion is what turns the monitor RED.
    const octokit = octokitReturning([
      { updated_at: "2026-05-18T12:29:30.000Z" },
    ]);
    const result = await verifyScheduledIssueCreated({
      label: "scheduled-roadmap-review",
      sinceIso: RUN_START,
      octokit,
    });
    expect(result).toBe(false);
  });

  it("credits a dedup-comment: issue created earlier but UPDATED this run window → true", async () => {
    // cron-campaign-calendar's comment-bump path (STEP 2(b): "Do NOT create a new
    // issue") comments a heartbeat note on the most-recent existing calendar issue
    // instead of creating a new one on a quiet day. That is a HEALTHY run with no
    // new issue — updated_at moved into the window, so it must NOT false-red.
    // Verifying on created_at would have failed here. (community-monitor's former
    // in-prompt dedup rule was another such consumer, removed in #6143 — see the
    // coupling-invariant assertion below.)
    const octokit = octokitReturning([
      { updated_at: "2026-05-31T09:31:00.000Z" }, // commented this run...
    ]);
    const result = await verifyScheduledIssueCreated({
      label: "scheduled-campaign-calendar",
      sinceIso: RUN_START, // ...even though the issue was created earlier
      octokit,
    });
    expect(result).toBe(true);
  });

  it("passes the GitHub `since` param so the server filters by updated_at", async () => {
    const octokit = octokitReturning([
      { updated_at: "2026-05-31T10:00:00.000Z" },
    ]);
    await verifyScheduledIssueCreated({
      label: "scheduled-roadmap-review",
      sinceIso: RUN_START,
      octokit,
    });
    const [, params] = octokit.request.mock.calls[0];
    expect(params.since).toBe(RUN_START);
    expect(params.sort).toBe("updated");
  });

  it("returns false when no matching issue exists at all", async () => {
    const octokit = octokitReturning([]);
    const result = await verifyScheduledIssueCreated({
      label: "scheduled-competitive-analysis",
      sinceIso: RUN_START,
      octokit,
    });
    expect(result).toBe(false);
  });

  it("is read-only — issues a GET against the issues list, never a create", async () => {
    const octokit = octokitReturning([
      { updated_at: "2026-05-31T10:00:00.000Z" },
    ]);
    await verifyScheduledIssueCreated({
      label: "scheduled-content-generator",
      sinceIso: RUN_START,
      octokit,
    });
    expect(octokit.request).toHaveBeenCalledTimes(1);
    const [route, params] = octokit.request.mock.calls[0];
    expect(route).toBe("GET /repos/{owner}/{repo}/issues");
    expect(params.labels).toBe("scheduled-content-generator");
    // Never a mutation route.
    for (const call of octokit.request.mock.calls) {
      expect(String(call[0])).not.toContain("POST");
      expect(String(call[0])).not.toContain("PATCH");
    }
  });

  it("throws on an invalid sinceIso rather than silently red-flagging a healthy run", async () => {
    const octokit = octokitReturning([
      { updated_at: "2026-05-31T10:00:00.000Z" },
    ]);
    await expect(
      verifyScheduledIssueCreated({
        label: "scheduled-strategy-review",
        sinceIso: "not-a-date",
        octokit,
      }),
    ).rejects.toThrow(/invalid sinceIso/);
  });
});

// #6143 — coupling-invariant: campaign-calendar is the SOLE remaining consumer
// of verifyScheduledIssueCreated's updated_at-credits-a-comment path (after
// community-monitor's in-prompt dedup rule was removed). The `since`/updated_at
// filter in verifyScheduledIssueCreated is load-bearing ONLY because of that
// path. This test reads the campaign-calendar source and asserts its comment-bump
// markers still exist — if that path is ever removed, this reddens and tells the
// next engineer the `updated_at` filter may now be tightened to created_at.
// (cq-test-fixtures-synthesized-only: reads the real SUT via readFileSync.)
describe("#6143 — campaign-calendar comment-bump coupling invariant", () => {
  it("cron-campaign-calendar.ts still carries the updated_at-crediting comment-bump path", async () => {
    const { readFileSync } = await import("node:fs");
    const { resolve } = await import("node:path");
    const campaignCalendarSource = readFileSync(
      resolve(
        __dirname,
        "../../../server/inngest/functions/cron-campaign-calendar.ts",
      ),
      "utf-8",
    );
    // Anchor on the BEHAVIOR-bearing prompt directive (STEP 2(b)'s "comment,
    // don't create" instruction) — NOT the volatile "STEP 2(b)" step number
    // and NOT an explanatory source comment (which a benign reword would
    // false-red). Removing this directive removes campaign-calendar's
    // comment-bump path → the updated_at filter becomes tightenable to
    // created_at, which is exactly what this tripwire signals.
    expect(campaignCalendarSource).toContain("Do NOT create a new issue");
  });
});

describe("resolveOutputAwareOk", () => {
  it("issue present + spawn ok → ok:true, no event", async () => {
    const octokit = octokitReturning([
      { updated_at: "2026-05-31T09:30:00.000Z" },
    ]);
    const ok = await resolveOutputAwareOk({
      spawnOk: true,
      label: "scheduled-roadmap-review",
      runStartedAt: RUN_START,
      cronName: "cron-roadmap-review",
      octokit,
    });
    expect(ok).toBe(true);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("issue present + spawn NON-ZERO → ok:true + non-paging WARN (output overrides exit code)", async () => {
    // The competitive-analysis #4747 false-red regression: claude created the
    // issue but exited non-zero on a trailing step. Output is the contract →
    // green, with a warning (not a red monitor).
    const octokit = octokitReturning([
      { updated_at: "2026-06-01T11:15:00.000Z" },
    ]);
    const ok = await resolveOutputAwareOk({
      spawnOk: false,
      label: "scheduled-competitive-analysis",
      runStartedAt: RUN_START,
      cronName: "cron-competitive-analysis",
      octokit,
    });
    expect(ok).toBe(true); // <-- the fix: was false before
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(warnSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(warnSilentFallbackSpy.mock.calls[0][1].op).toBe(
      "scheduled-output-nonzero-exit",
    );
  });

  it("NO issue + spawn ok → ok:false + scheduled-output-missing (silent no-op)", async () => {
    const octokit = octokitReturning([
      { updated_at: "2026-05-18T12:00:00.000Z" }, // before window
    ]);
    const ok = await resolveOutputAwareOk({
      spawnOk: true,
      label: "scheduled-roadmap-review",
      runStartedAt: RUN_START,
      cronName: "cron-roadmap-review",
      octokit,
    });
    expect(ok).toBe(false);
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const opts = reportSilentFallbackSpy.mock.calls[0][1];
    expect(opts.op).toBe("scheduled-output-missing");
    expect(opts.extra.spawnOk).toBe(true);
  });

  it("NO issue + spawn NON-ZERO → ok:false + scheduled-output-missing (spawnOk:false in extra)", async () => {
    const octokit = octokitReturning([]);
    const ok = await resolveOutputAwareOk({
      spawnOk: false,
      label: "scheduled-roadmap-review",
      runStartedAt: RUN_START,
      cronName: "cron-roadmap-review",
      octokit,
    });
    expect(ok).toBe(false);
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe(
      "scheduled-output-missing",
    );
    expect(reportSilentFallbackSpy.mock.calls[0][1].extra.spawnOk).toBe(false);
  });

  it("verify THREW → falls back to spawn exit code + verify-output-failed event", async () => {
    const request = vi.fn().mockRejectedValue(new Error("GitHub 502"));
    const octokit = { request } as unknown as Parameters<
      typeof resolveOutputAwareOk
    >[0]["octokit"];
    // spawnOk true → inconclusive verify falls back to true
    const okTrue = await resolveOutputAwareOk({
      spawnOk: true,
      label: "scheduled-content-generator",
      runStartedAt: RUN_START,
      cronName: "cron-content-generator",
      octokit,
    });
    expect(okTrue).toBe(true);
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe(
      "verify-output-failed",
    );
    reportSilentFallbackSpy.mockClear();
    // spawnOk false → inconclusive verify falls back to false
    const okFalse = await resolveOutputAwareOk({
      spawnOk: false,
      label: "scheduled-content-generator",
      runStartedAt: RUN_START,
      cronName: "cron-content-generator",
      octokit,
    });
    expect(okFalse).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// ensureScheduledAuditIssue — the handler-level silence-hole fallback (#4960),
// extracted from cron-content-generator and parameterized for all 8 always-
// create producers (#4978). When the output-aware heartbeat finds NO labeled
// issue in the run window, the handler files a self-reporting FAILED audit
// issue so the run is never silent. The behavior under test (dedup, redaction,
// markdown-breakout neutralization, create) is identical to the proven
// content-generator helper — these tests pin it for the shared, parameterized
// form so a hardcoded-slug regression fails.
// ---------------------------------------------------------------------------

describe("ensureScheduledAuditIssue (shared fallback)", () => {
  const RUN_STARTED_AT = "2026-06-05T15:05:11.992Z";
  const DATE = "2026-06-05"; // runStartedAt.slice(0, 10)
  const SPAWN = {
    exitCode: 1,
    signal: null,
    abortedByTimeout: false,
    durationMs: 368727,
    stdoutTail: "API Error: 500 Internal server error.",
    stderrTail: "",
  };

  // ≥2 distinct {label, titlePrefix} pairs so a hardcoded-slug regression
  // (e.g. forgetting to thread args.label / args.titlePrefix) fails loudly.
  const PAIRS = [
    {
      label: "scheduled-growth-audit",
      titlePrefix: "[Scheduled] Growth Audit -",
      cronName: "cron-growth-audit",
    },
    {
      label: "scheduled-community-monitor",
      titlePrefix: "[Scheduled] Community Monitor -",
      cronName: "cron-community-monitor",
    },
  ] as const;

  function fakeOctokit(getData: Array<{ title: string }>) {
    const calls: Array<{ route: string; params: Record<string, unknown> }> = [];
    const octokit = {
      request: vi.fn(async (route: string, params: Record<string, unknown>) => {
        calls.push({ route, params });
        if (route.startsWith("GET")) return { data: getData };
        return { data: { number: 9999 } };
      }),
    } as unknown as Octokit;
    return { octokit, calls };
  }

  it.each(PAIRS)(
    "creates exactly one labeled audit issue for $label when none exists in the window",
    async ({ label, titlePrefix, cronName }) => {
      const { octokit, calls } = fakeOctokit([]);
      const res = await ensureScheduledAuditIssue({
        label,
        titlePrefix,
        cronName,
        runStartedAt: RUN_STARTED_AT,
        spawnResult: SPAWN,
        octokit,
      });
      expect(res.created).toBe(true);
      const posts = calls.filter((c) => c.route.startsWith("POST"));
      expect(posts).toHaveLength(1);
      // Title is `${titlePrefix} ${date}` with date = runStartedAt.slice(0,10).
      expect(posts[0].params.title).toBe(`${titlePrefix} ${DATE}`);
      expect(posts[0].params.labels).toEqual([label]);
      // Self-diagnosing body carries the cronName + failure evidence.
      expect(String(posts[0].params.body)).toContain(cronName);
      expect(String(posts[0].params.body)).toContain("API Error: 500");
      expect(String(posts[0].params.body)).toContain("exitCode");
    },
  );

  it("composes the content-generator title byte-identically (AC2)", async () => {
    const { octokit, calls } = fakeOctokit([]);
    await ensureScheduledAuditIssue({
      label: "scheduled-content-generator",
      titlePrefix: "[Scheduled] Content Generator -",
      cronName: "cron-content-generator",
      runStartedAt: RUN_STARTED_AT,
      spawnResult: SPAWN,
      octokit,
    });
    const post = calls.find((c) => c.route.startsWith("POST"));
    expect(post?.params.title).toBe(`[Scheduled] Content Generator - ${DATE}`);
  });

  it.each(PAIRS)(
    "does NOT double-file for $label when an EXACT same-day audit title already exists",
    async ({ label, titlePrefix, cronName }) => {
      const { octokit, calls } = fakeOctokit([
        { title: `${titlePrefix} ${DATE}` },
      ]);
      const res = await ensureScheduledAuditIssue({
        label,
        titlePrefix,
        cronName,
        runStartedAt: RUN_STARTED_AT,
        spawnResult: SPAWN,
        octokit,
      });
      expect(res.created).toBe(false);
      expect(calls.filter((c) => c.route.startsWith("POST"))).toHaveLength(0);
    },
  );

  it.each(PAIRS)(
    "dedup is title-PREFIX for $label — a suffixed prompt-success issue suppresses the fallback",
    async ({ label, titlePrefix, cronName }) => {
      const { octokit, calls } = fakeOctokit([
        { title: `${titlePrefix} ${DATE} (manual)` },
      ]);
      const res = await ensureScheduledAuditIssue({
        label,
        titlePrefix,
        cronName,
        runStartedAt: RUN_STARTED_AT,
        spawnResult: SPAWN,
        octokit,
      });
      expect(res.created).toBe(false);
      expect(calls.filter((c) => c.route.startsWith("POST"))).toHaveLength(0);
    },
  );

  it("dedup GET is label-scoped, state:all, sort:created/desc, per_page:10 (AC6)", async () => {
    const { octokit, calls } = fakeOctokit([]);
    await ensureScheduledAuditIssue({
      label: "scheduled-growth-audit",
      titlePrefix: "[Scheduled] Growth Audit -",
      cronName: "cron-growth-audit",
      runStartedAt: RUN_STARTED_AT,
      spawnResult: SPAWN,
      octokit,
    });
    const get = calls.find((c) => c.route.startsWith("GET"));
    expect(get?.route).toBe("GET /repos/{owner}/{repo}/issues");
    expect(get?.params.labels).toBe("scheduled-growth-audit");
    expect(get?.params.state).toBe("all");
    expect(get?.params.sort).toBe("created");
    expect(get?.params.direction).toBe("desc");
    expect(get?.params.per_page).toBe(10);
  });

  it("scrubs secrets and neutralizes markdown-breakout chars in the issue body (AC5)", async () => {
    const { octokit, calls } = fakeOctokit([]);
    await ensureScheduledAuditIssue({
      label: "scheduled-seo-aeo-audit",
      titlePrefix: "[Scheduled] SEO/AEO Audit -",
      cronName: "cron-seo-aeo-audit",
      runStartedAt: RUN_STARTED_AT,
      spawnResult: {
        ...SPAWN,
        // crash-path stderr spilling an Anthropic key + table-breaking chars
        // (incl. a literal backslash-pipe to exercise escape-order, js/incomplete-sanitization)
        stderrTail: "boom sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAA \\| pipe `tick`",
      },
      octokit,
    });
    const body = String(
      calls.find((c) => c.route.startsWith("POST"))!.params.body,
    );
    expect(body).not.toContain("sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAA");
    expect(body).toContain("[redacted-key]");
    // table-breaking chars neutralized inside the inline-code cell: backslash
    // escaped FIRST (js/incomplete-sanitization) so `\|` → `\\\|`, pipe → "\|"
    // (markdown literal, no row break), backtick → "ʼ" (no span break),
    // CR/LF → space.
    expect(body).toContain("\\\\\\| pipe");
    expect(body).toContain("ʼtickʼ");
    expect(body).not.toContain("`tick`");
  });

  it("collapses CR/LF in the tail to a single space (no markdown row-break)", async () => {
    const { octokit, calls } = fakeOctokit([]);
    await ensureScheduledAuditIssue({
      label: "scheduled-growth-audit",
      titlePrefix: "[Scheduled] Growth Audit -",
      cronName: "cron-growth-audit",
      runStartedAt: RUN_STARTED_AT,
      spawnResult: { ...SPAWN, stderrTail: "line1\r\nline2\nline3" },
      octokit,
    });
    const body = String(
      calls.find((c) => c.route.startsWith("POST"))!.params.body,
    );
    // CR/LF collapsed to a single space so the tail stays inside one table cell.
    expect(body).toContain("line1 line2 line3");
    expect(body).not.toContain("line1\nline2");
  });

  it("renders the (empty) sentinel for an empty tail", async () => {
    const { octokit, calls } = fakeOctokit([]);
    await ensureScheduledAuditIssue({
      label: "scheduled-growth-audit",
      titlePrefix: "[Scheduled] Growth Audit -",
      cronName: "cron-growth-audit",
      runStartedAt: RUN_STARTED_AT,
      spawnResult: { ...SPAWN, stdoutTail: "", stderrTail: "" },
      octokit,
    });
    const body = String(
      calls.find((c) => c.route.startsWith("POST"))!.params.body,
    );
    expect(body).toContain("(empty)");
  });

  it("throws when neither octokit nor installationToken is provided", async () => {
    await expect(
      ensureScheduledAuditIssue({
        label: "scheduled-growth-audit",
        titlePrefix: "[Scheduled] Growth Audit -",
        cronName: "cron-growth-audit",
        runStartedAt: RUN_STARTED_AT,
        spawnResult: SPAWN,
        // no octokit, no installationToken
      }),
    ).rejects.toThrow(/need octokit or installationToken/);
  });

  it("propagates a create failure to the caller (POST throws → helper rejects)", async () => {
    const octokit = {
      request: vi.fn(async (route: string) => {
        if (route.startsWith("GET")) return { data: [] };
        throw new Error("GitHub 503");
      }),
    } as unknown as Octokit;
    await expect(
      ensureScheduledAuditIssue({
        label: "scheduled-roadmap-review",
        titlePrefix: "[Scheduled] Weekly Roadmap Review -",
        cronName: "cron-roadmap-review",
        runStartedAt: RUN_STARTED_AT,
        spawnResult: SPAWN,
        octokit,
      }),
    ).rejects.toThrow("GitHub 503");
  });
});

// ---------------------------------------------------------------------------
// mintInstallationToken — least-privilege cron token (#5046 PR-1 / AC3).
//
// The cron mint path threads an optional { permissions, repositories } scope to
// generateInstallationToken so a leaked cron GH_TOKEN is bounded to a
// single-user incident (repo-scoped, write-only on contents/issues/PRs — never
// actions/admin/checks). The mint resolves the installation via the App-JWT
// probe client, NOT any ambient GH_TOKEN, so a bogus ambient token cannot leak
// into the minted value.
// ---------------------------------------------------------------------------
describe("mintInstallationToken (least-privilege cron token)", () => {
  beforeEach(() => {
    generateInstallationTokenSpy.mockReset().mockResolvedValue("ghs_minted");
    probeRequestSpy.mockReset().mockResolvedValue({ data: { id: 424242 } });
  });

  it("DEFAULT_CRON_TOKEN_PERMISSIONS is exactly contents+issues+pull_requests:write (AC3)", () => {
    expect(DEFAULT_CRON_TOKEN_PERMISSIONS).toEqual({
      contents: "write",
      issues: "write",
      pull_requests: "write",
    });
    // NEVER actions/administration/checks — those would un-bound the blast radius.
    expect(DEFAULT_CRON_TOKEN_PERMISSIONS).not.toHaveProperty("actions");
    expect(DEFAULT_CRON_TOKEN_PERMISSIONS).not.toHaveProperty("administration");
  });

  it("threads the narrowed permissions + repositories scope to generateInstallationToken", async () => {
    const token = await mintInstallationToken({
      tokenMinLifetimeMs: 1000,
      permissions: DEFAULT_CRON_TOKEN_PERMISSIONS,
      repositories: [REPO_NAME],
    });
    expect(token).toBe("ghs_minted");
    expect(generateInstallationTokenSpy).toHaveBeenCalledTimes(1);
    const [installationId, opts] = generateInstallationTokenSpy.mock.calls[0];
    expect(installationId).toBe(424242);
    expect(opts).toMatchObject({
      minRemainingMs: 1000,
      permissions: {
        contents: "write",
        issues: "write",
        pull_requests: "write",
      },
      repositories: ["soleur"],
    });
  });

  it("an unscoped mint passes no permissions/repositories (full grant preserved for non-narrowed crons)", async () => {
    await mintInstallationToken({ tokenMinLifetimeMs: 2000 });
    const [, opts] = generateInstallationTokenSpy.mock.calls[0];
    expect(opts.minRemainingMs).toBe(2000);
    expect(opts.permissions).toBeUndefined();
    expect(opts.repositories).toBeUndefined();
  });

  it("mints via the App-JWT probe path, not an ambient GH_TOKEN", async () => {
    const prev = process.env.GH_TOKEN;
    process.env.GH_TOKEN = "ghs_bogus_ambient_should_be_ignored";
    try {
      const token = await mintInstallationToken({
        tokenMinLifetimeMs: 1000,
        permissions: DEFAULT_CRON_TOKEN_PERMISSIONS,
        repositories: [REPO_NAME],
      });
      // The returned token is the freshly minted one, never the ambient env var.
      expect(token).toBe("ghs_minted");
      expect(token).not.toContain("bogus_ambient");
      // Installation resolved via the probe octokit (App JWT), not GH_TOKEN.
      expect(probeRequestSpy).toHaveBeenCalledWith(
        "GET /repos/{owner}/{repo}/installation",
        { owner: "jikig-ai", repo: "soleur" },
      );
    } finally {
      if (prev === undefined) delete process.env.GH_TOKEN;
      else process.env.GH_TOKEN = prev;
    }
  });
});

// #5186 — postAnthropicMessage: transport-only Anthropic Messages helper.
// Extracted from the duplicated fetch shape in cron-weekly-release-digest and
// cron-compound-promote. The helper owns ONLY the request/response transport;
// every observability/fallback/shape decision stays at the call site. These
// tests pin the transport contract: request headers + body, return shape,
// non-ok throw, optional timeout wiring, optional output_config passthrough.
describe("postAnthropicMessage (shared Anthropic transport)", () => {
  const ANY_MODEL = "claude-sonnet-5";
  let fetchSpy: ReturnType<typeof vi.fn>;

  function okResponse(body: unknown) {
    // Use a real Response (not a duck-typed object) for fidelity + parity with
    // the domain-router classify-path tests; survives a future resp.text() refactor.
    return new Response(JSON.stringify(body), { status: 200 });
  }

  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    emitClaudeCostMarkerSpy.mockClear();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("AC4c — emits a cron:<name> SOLEUR_CLAUDE_COST marker from the response usage/model when markerSource is set", async () => {
    fetchSpy.mockResolvedValue(
      okResponse({
        content: [{ text: "ok" }],
        stop_reason: "end_turn",
        model: "claude-sonnet-5",
        usage: {
          input_tokens: 12,
          output_tokens: 3,
          cache_read_input_tokens: 4,
          cache_creation_input_tokens: 1,
        },
      }),
    );

    await postAnthropicMessage({
      apiKey: "sk-ant-" + "synthetic-key",
      model: ANY_MODEL,
      maxTokens: 8,
      messages: [{ role: "user", content: "ping" }],
      markerSource: "cron-compound-promote",
    });

    expect(emitClaudeCostMarkerSpy).toHaveBeenCalledTimes(1);
    expect(emitClaudeCostMarkerSpy.mock.calls[0][0]).toMatchObject({
      source: "cron:cron-compound-promote",
      model: "claude-sonnet-5",
      input_tokens: 12,
      output_tokens: 3,
      cache_read_input_tokens: 4,
      cache_creation_input_tokens: 1,
      // /v1/messages does not return total_cost_usd → tokens-only.
      cost_usd: null,
      capture_status: "ok",
    });
  });

  it("emits NO marker when markerSource is omitted (the two legacy callers)", async () => {
    fetchSpy.mockResolvedValue(
      okResponse({ content: [{ text: "ok" }], stop_reason: "end_turn" }),
    );
    await postAnthropicMessage({
      apiKey: "sk-ant-" + "synthetic-key",
      model: ANY_MODEL,
      maxTokens: 8,
      messages: [{ role: "user", content: "ping" }],
    });
    expect(emitClaudeCostMarkerSpy).not.toHaveBeenCalled();
  });

  it("POSTs to the messages endpoint with auth + version headers and returns {text, stopReason}", async () => {
    fetchSpy.mockResolvedValue(
      okResponse({ content: [{ text: '{"highlights":[]}' }], stop_reason: "end_turn" }),
    );

    const result = await postAnthropicMessage({
      apiKey: "sk-ant-" + "synthetic-key",
      model: ANY_MODEL,
      maxTokens: 2048,
      messages: [{ role: "user", content: "hello" }],
    });

    expect(result).toEqual({ text: '{"highlights":[]}', stopReason: "end_turn" });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [url, init] = fetchSpy.mock.calls[0] as [string, RequestInit & { headers: Record<string, string> }];
    expect(url).toBe("https://api.anthropic.com/v1/messages");
    expect(init.method).toBe("POST");
    expect(init.headers["x-api-key"]).toBe("sk-ant-" + "synthetic-key");
    expect(init.headers["anthropic-version"]).toBe("2023-06-01");
    expect(init.headers["content-type"]).toBe("application/json");
    const sent = JSON.parse(init.body as string);
    expect(sent).toMatchObject({
      model: ANY_MODEL,
      max_tokens: 2048,
      messages: [{ role: "user", content: "hello" }],
    });
    // No timeout requested → no AbortSignal wired.
    expect(init.signal).toBeUndefined();
    // No outputConfig → request carries no output_config field.
    expect(sent).not.toHaveProperty("output_config");
  });

  it("throws `Anthropic API <status>` on a non-ok response (caller owns the fallback)", async () => {
    fetchSpy.mockResolvedValue(new Response("upstream error", { status: 503 }));

    await expect(
      postAnthropicMessage({
        apiKey: "sk-ant-" + "synthetic-key",
        model: ANY_MODEL,
        maxTokens: 2048,
        messages: [{ role: "user", content: "x" }],
      }),
    ).rejects.toThrow("Anthropic API 503");
  });

  it("rethrows a redacted error on a fetch network failure (never leaks the api key)", async () => {
    const apiKey = "sk-ant-" + "synthetic-network-key";
    fetchSpy.mockRejectedValue(new TypeError("fetch failed"));

    const err = await postAnthropicMessage({
      apiKey,
      model: ANY_MODEL,
      maxTokens: 2048,
      messages: [{ role: "user", content: "x" }],
    }).catch((e: Error) => e);

    expect(err).toBeInstanceOf(Error);
    // Redacted shape: carries the error class, never the credential.
    expect((err as Error).message).toBe("Anthropic API request failed (TypeError)");
    expect((err as Error).message).not.toContain(apiKey);
  });

  it("wires AbortSignal.timeout when timeoutMs is provided", async () => {
    fetchSpy.mockResolvedValue(okResponse({ content: [{ text: "{}" }], stop_reason: "end_turn" }));

    await postAnthropicMessage({
      apiKey: "sk-ant-" + "synthetic-key",
      model: ANY_MODEL,
      maxTokens: 2048,
      messages: [{ role: "user", content: "x" }],
      timeoutMs: 60_000,
    });

    const [, init] = fetchSpy.mock.calls[0] as [string, RequestInit];
    // AbortSignal.timeout(ms) returns an AbortSignal instance.
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });

  it("passes output_config through to the request body when provided", async () => {
    fetchSpy.mockResolvedValue(okResponse({ content: [{ text: "{}" }], stop_reason: "end_turn" }));
    const schema = { type: "object", additionalProperties: false, properties: {} };

    await postAnthropicMessage({
      apiKey: "sk-ant-" + "synthetic-key",
      model: ANY_MODEL,
      maxTokens: 2048,
      messages: [{ role: "user", content: "x" }],
      outputConfig: { format: { type: "json_schema", schema } },
    });

    const [, init] = fetchSpy.mock.calls[0] as [string, RequestInit];
    const sent = JSON.parse(init.body as string);
    expect(sent.output_config).toEqual({ format: { type: "json_schema", schema } });
  });

  it("returns {text: ''} when content is empty — the caller decides that is an error", async () => {
    fetchSpy.mockResolvedValue(okResponse({ content: [], stop_reason: "end_turn" }));

    const result = await postAnthropicMessage({
      apiKey: "sk-ant-" + "synthetic-key",
      model: ANY_MODEL,
      maxTokens: 2048,
      messages: [{ role: "user", content: "x" }],
    });

    expect(result).toEqual({ text: "", stopReason: "end_turn" });
  });
});

// ---------------------------------------------------------------------------
// #5674 — formatTailForSentry + classify-fatal resolver + AnthropicApiError.
// ---------------------------------------------------------------------------

// Runtime-constructed token shapes that MATCH the redaction-allowlist regexes
// (sk-ant-[A-Za-z0-9_-]{20,}, ghs_[A-Za-z0-9_-]{20,}) WITHOUT a literal
// sk-ant-<alnum> string in the source (GitHub push-protection Sharp Edge — the
// secret only exists at runtime, assembled from non-secret fragments).
const SYNTH_SK_ANT = "sk-ant-" + "A".repeat(40);
const SYNTH_GHS = "ghs_" + "B".repeat(40);
// Standalone Supabase secret-grade tokens (sbp_ management token, sb_secret_
// key) — secret-shaped, regex-matching the allowlist, no literal token in
// source (push-protection Sharp Edge). review #5680 hardening.
const SYNTH_SBP = "sbp_" + "c".repeat(40);
const SYNTH_SB_SECRET = "sb_secret_" + "D".repeat(30);

describe("formatTailForSentry (multi-secret scrub + slice)", () => {
  it("strips an sk-ant key AND an installation-token-shaped string (AC2)", () => {
    const tail = `boot ok\nAPI Error: invalid x-api-key ${SYNTH_SK_ANT} and ${SYNTH_GHS} leaked`;
    const out = formatTailForSentry(tail);
    expect(out).toBeDefined();
    expect(out).not.toContain(SYNTH_SK_ANT);
    expect(out).not.toContain(SYNTH_GHS);
  });

  it("strips bare standalone Supabase secret tokens (sbp_ / sb_secret_) (review #5680)", () => {
    const tail = `crash stack\nleaked ${SYNTH_SBP} and ${SYNTH_SB_SECRET} in trace`;
    const out = formatTailForSentry(tail);
    expect(out).toBeDefined();
    expect(out).not.toContain(SYNTH_SBP);
    expect(out).not.toContain(SYNTH_SB_SECRET);
    // public-grade publishable key is NOT secret — left intact
    const pub = "sb_publishable_" + "e".repeat(30);
    expect(formatTailForSentry(`url uses ${pub}`)).toContain(pub);
  });

  it("returns undefined for empty/absent input (caller omits the key)", () => {
    expect(formatTailForSentry(undefined)).toBeUndefined();
    expect(formatTailForSentry("")).toBeUndefined();
  });

  it("preserves the human-readable cause line (reason survives scrub, AC6)", () => {
    const tail = `Credit balance is too low. Visit billing. token ${SYNTH_SK_ANT} here`;
    const out = formatTailForSentry(tail);
    expect(out).toContain("Credit balance is too low");
    expect(out).not.toContain(SYNTH_SK_ANT);
  });
});

describe("classifyEvalFatal", () => {
  const base = { exitCode: 1, abortedByTimeout: false, stdoutTail: "", stderrTail: "" };

  it("credit-balance tail → fatal credit-exhausted", () => {
    const c = classifyEvalFatal({ ...base, stdoutTail: "Credit balance is too low" });
    expect(c.fatal).toBe(true);
    expect(c.fatalClass).toBe("credit-exhausted");
  });

  it("auth marker tail → fatal auth-failure", () => {
    const c = classifyEvalFatal({ ...base, stderrTail: "API Error: invalid x-api-key" });
    expect(c.fatal).toBe(true);
    expect(c.fatalClass).toBe("auth-failure");
  });

  it("abortedByTimeout → fatal timeout", () => {
    const c = classifyEvalFatal({ ...base, abortedByTimeout: true });
    expect(c.fatal).toBe(true);
    expect(c.fatalClass).toBe("timeout");
  });

  it("exitCode -1 (spawn never started) → fatal spawn-fault", () => {
    const c = classifyEvalFatal({ ...base, exitCode: -1 });
    expect(c.fatal).toBe(true);
    expect(c.fatalClass).toBe("spawn-fault");
  });

  it("plain non-zero with no marker → NOT fatal (benign)", () => {
    const c = classifyEvalFatal({ ...base, stdoutTail: "Reached max turns; no artifact." });
    expect(c.fatal).toBe(false);
  });
});

describe("resolveBestEffortEvalOk (classify-fatal heartbeat)", () => {
  const FATAL_TAIL = {
    ok: false,
    exitCode: 1,
    abortedByTimeout: false,
    durationMs: 1234,
    stdoutTail: `Credit balance is too low. token ${SYNTH_SK_ANT}`,
    stderrTail: "",
  };

  it("FATAL credit tail → ok:false + scrubbed reason in sentryExtra (AC1)", () => {
    const d = resolveBestEffortEvalOk(FATAL_TAIL);
    expect(d.ok).toBe(false);
    expect(d.errorSummary).toMatch(/credit balance is too low/i);
    // Scrubbed tail present, secret absent (AC1 + AC6).
    expect(d.sentryExtra.stdoutTail).toContain("Credit balance is too low");
    expect(JSON.stringify(d.sentryExtra)).not.toContain(SYNTH_SK_ANT);
    expect(d.sentryExtra.fatalClass).toBe("credit-exhausted");
  });

  it("BENIGN max-turns non-zero → ok:true (monitor stays GREEN) + reason recorded (the #4730 carve-out)", () => {
    const d = resolveBestEffortEvalOk({
      ok: false,
      exitCode: 1,
      abortedByTimeout: false,
      durationMs: 42,
      stdoutTail: "Reached max turns with no artifact this cycle.",
      stderrTail: "",
    });
    expect(d.ok).toBe(true); // <-- flip-all would have made this false (false page)
    expect(d.errorSummary).toMatch(/non-zero/i);
    expect(d.sentryExtra.fatalClass).toBe("benign");
  });

  it("clean exit (ok:true) → ok:true, no reason", () => {
    const d = resolveBestEffortEvalOk({
      ok: true,
      exitCode: 0,
      abortedByTimeout: false,
      durationMs: 10,
      stdoutTail: "done",
      stderrTail: "",
    });
    expect(d.ok).toBe(true);
    expect(d.errorSummary).toBeUndefined();
  });
});

describe("AnthropicApiError (widened transport, #5674)", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;
  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
  });
  afterEach(() => vi.unstubAllGlobals());

  it("throws a typed AnthropicApiError carrying status + scrubbed bodyExcerpt on non-ok", async () => {
    fetchSpy.mockResolvedValue(
      new Response(
        JSON.stringify({ type: "error", error: { type: "invalid_request_error", message: "Credit balance is too low" } }),
        { status: 400 },
      ),
    );
    const err = await postAnthropicMessage({
      apiKey: "sk-ant-" + "synthetic",
      model: "claude-sonnet-5",
      maxTokens: 1,
      messages: [{ role: "user", content: "ping" }],
    }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AnthropicApiError);
    expect((err as AnthropicApiError).status).toBe(400);
    expect((err as AnthropicApiError).bodyExcerpt).toMatch(/credit balance is too low/i);
    // Backward-compatible message prefix (existing callers/tests match it).
    expect((err as Error).message).toContain("Anthropic API 400");
  });

  it("backward-compat: `Anthropic API <status>` substring still matches (AC8)", async () => {
    fetchSpy.mockResolvedValue(new Response("upstream error", { status: 503 }));
    await expect(
      postAnthropicMessage({
        apiKey: "sk-ant-" + "synthetic",
        model: "claude-sonnet-5",
        maxTokens: 1,
        messages: [{ role: "user", content: "x" }],
      }),
    ).rejects.toThrow("Anthropic API 503");
  });
});

describe("resolveOutputAwareOk — F1 retrofit (scheduled-output-missing extra is scrubbed)", () => {
  it("routes the stdout/stderr tails through formatTailForSentry (no raw sk-ant in the extra, AC2)", async () => {
    const octokit = octokitReturning([]); // no issue → output-missing
    await resolveOutputAwareOk({
      spawnOk: true,
      label: "scheduled-roadmap-review",
      runStartedAt: RUN_START,
      cronName: "cron-roadmap-review",
      octokit,
      stdoutTail: `max-turns. leaked ${SYNTH_SK_ANT} here`,
      stderrTail: `boom ${SYNTH_GHS}`,
      exitCode: 0,
    });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const extra = reportSilentFallbackSpy.mock.calls[0][1].extra as Record<string, unknown>;
    const serialized = JSON.stringify(extra);
    expect(serialized).not.toContain(SYNTH_SK_ANT);
    expect(serialized).not.toContain(SYNTH_GHS);
  });
});

// #5728 — heartbeat POST delivery robustness. The pre-fix postSentryHeartbeat
// POSTed ONCE and never inspected resp.ok, so (a) a transient 5xx/timeout/network
// drop of the OK check-in left a silent `missed` (the 2026-06-13→06-21 H3 class),
// and (b) a resolved non-2xx was treated as success. These tests pin the new
// contract: inspect resp.ok, bounded-retry on 5xx/network/timeout ONLY (never a
// 4xx), then fall back to reportSilentFallback once retries are exhausted. The
// retry wall-clock is bounded by construction (SENTRY_HEARTBEAT_TOTAL_BUDGET_MS,
// well under the 60-min check-in margin) — asserted structurally via the
// at-most-MAX_ATTEMPTS fetch-call cap, not a flaky timing assertion.
describe("postSentryHeartbeat — delivery robustness (#5728)", () => {
  const VALID_DOMAIN = "o4509.ingest.sentry.io";
  const VALID_PROJECT = "4509999";
  const VALID_PUBLIC_KEY = "abcdef0123456789abcdef0123456789";
  let fetchSpy: ReturnType<typeof vi.fn>;
  const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

  const call = (ok = true) =>
    postSentryHeartbeat({
      ok,
      sentryMonitorSlug: "scheduled-community-monitor",
      cronName: "cron-community-monitor",
      logger,
    });

  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    vi.stubEnv("SENTRY_INGEST_DOMAIN", VALID_DOMAIN);
    vi.stubEnv("SENTRY_PROJECT_ID", VALID_PROJECT);
    vi.stubEnv("SENTRY_PUBLIC_KEY", VALID_PUBLIC_KEY);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
    logger.info.mockClear();
    logger.warn.mockClear();
    logger.error.mockClear();
  });

  it("posts exactly once and does NOT fall back when the first POST succeeds (200)", async () => {
    fetchSpy.mockResolvedValue(new Response(null, { status: 202 }));
    await call(false); // ok:false avoids the best-effort cron-fires file write
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    // posts the error status on the documented ?status= query shape
    const url = fetchSpy.mock.calls[0][0] as string;
    expect(url).toContain(`/cron/scheduled-community-monitor/${VALID_PUBLIC_KEY}/?status=error`);
  });

  it("retries a transient 5xx and succeeds on the 200 — one effective check-in, no fallback", async () => {
    fetchSpy
      .mockResolvedValueOnce(new Response("upstream", { status: 503 }))
      .mockResolvedValueOnce(new Response(null, { status: 202 }));
    await call(false);
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("retries a transient network failure and succeeds on the 200 — no fallback", async () => {
    fetchSpy
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValueOnce(new Response(null, { status: 202 }));
    await call(false);
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("treats a resolved non-2xx (all 5xx) as failure → bounded retries then ONE reportSilentFallback (today's silently-swallowed gap)", async () => {
    fetchSpy.mockResolvedValue(new Response("upstream", { status: 500 }));
    await call(false);
    // bounded — never more than MAX_ATTEMPTS POSTs
    expect(fetchSpy.mock.calls.length).toBeGreaterThanOrEqual(2);
    expect(fetchSpy.mock.calls.length).toBeLessThanOrEqual(3);
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1].feature).toBe("cron-sentry-heartbeat");
  });

  it("does NOT retry a 4xx (permanent bad-slug/DSN) — posts once, falls back immediately", async () => {
    fetchSpy.mockResolvedValue(new Response("bad request", { status: 400 }));
    await call(false);
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
  });

  it("exhausts retries on repeated timeouts then falls back once (bounded)", async () => {
    fetchSpy.mockRejectedValue(
      Object.assign(new Error("The operation timed out."), { name: "TimeoutError" }),
    );
    await call(false);
    // Lower bound is load-bearing: a regression that STOPPED retrying timeouts
    // (post once → straight to fallback) yields exactly 1 call, which is <= 3 and
    // would pass without it. Assert the retry actually fired, bounded by the cap.
    expect(fetchSpy.mock.calls.length).toBeGreaterThanOrEqual(2);
    expect(fetchSpy.mock.calls.length).toBeLessThanOrEqual(3);
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
  });
});

// ---------------------------------------------------------------------------
// digestIssueExistsForDate / isRealScheduledDigest (#5751) — producer-side
// date-dedup. Distinct from ensureScheduledAuditIssue's title-dedup (which
// INTENTIONALLY counts FAILED/audit stubs to avoid double-auditing): this read
// must EXCLUDE those stubs so a same-day recovery still files the real digest.
// ---------------------------------------------------------------------------

const CM_LABEL = "scheduled-community-monitor";
const CM_PREFIX = "[Scheduled] Community Monitor -";
const CM_DATE = "2026-06-30";
// #5786 — campaign-calendar carries a trailing ` (heartbeat)` title suffix that
// the widened matcher must accept via the optional titleSuffix arg.
const CC_LABEL = "scheduled-campaign-calendar";
const CC_PREFIX = "[Scheduled] Campaign Calendar -";
const CC_SUFFIX = " (heartbeat)";
const CC_DATE = "2026-06-15";

function octokitReturningIssues(
  issues: Array<{ title?: string | null; body?: string | null }>,
) {
  const request = vi.fn().mockResolvedValue({ data: issues });
  return { request } as unknown as Parameters<
    typeof digestIssueExistsForDate
  >[0]["octokit"] & { request: typeof request };
}

describe("isRealScheduledDigest", () => {
  it("matches a real digest with today's dated title", () => {
    expect(
      isRealScheduledDigest(
        { title: `${CM_PREFIX} ${CM_DATE}`, body: "## Platform Status" },
        CM_DATE,
        CM_PREFIX,
      ),
    ).toBe(true);
  });

  it("EXCLUDES the audit FAILED self-report (byte-identical dated title, hardcoded body)", () => {
    expect(
      isRealScheduledDigest(
        {
          title: `${CM_PREFIX} ${CM_DATE}`,
          body: "Automated FAILED self-report from `cron-community-monitor`.",
        },
        CM_DATE,
        CM_PREFIX,
      ),
    ).toBe(false);
  });

  it("EXCLUDES the no-platform `- FAILED` title (no date suffix)", () => {
    expect(
      isRealScheduledDigest(
        { title: `${CM_PREFIX} FAILED`, body: "misconfig" },
        CM_DATE,
        CM_PREFIX,
      ),
    ).toBe(false);
  });

  it("EXCLUDES a real digest for a DIFFERENT date (replay-stable anchor)", () => {
    expect(
      isRealScheduledDigest(
        { title: `${CM_PREFIX} 2026-06-29`, body: "## Platform Status" },
        CM_DATE,
        CM_PREFIX,
      ),
    ).toBe(false);
  });

  it("EXCLUDES a coincidental-date issue whose title merely ENDS in the date (positive-anchor)", () => {
    // A human/triage issue like `Investigate community drop 2026-06-30` ends in
    // today's date but is NOT the canonical digest title. The old
    // endsWith(date) check misclassified it as a real digest → would suppress
    // the genuine digest. The positive title-shape anchor closes that gap.
    expect(
      isRealScheduledDigest(
        { title: `Investigate community drop ${CM_DATE}`, body: "looks low" },
        CM_DATE,
        CM_PREFIX,
      ),
    ).toBe(false);
  });

  it("EXCLUDES an LLM-drifted `- FAILED - <date>` title (positive-anchor)", () => {
    // A drifted title that both ends in the date AND carries `- FAILED` would
    // have slipped past endsWith(date) (the dead /-FAILED$/ belt only matched a
    // trailing FAILED). Only the exact canonical title counts now.
    expect(
      isRealScheduledDigest(
        { title: `${CM_PREFIX} FAILED - ${CM_DATE}`, body: "## Platform Status" },
        CM_DATE,
        CM_PREFIX,
      ),
    ).toBe(false);
  });

  // #5786 — campaign-calendar's producer digest carries a trailing
  // ` (heartbeat)` suffix (STEP 2.5). The widened matcher must accept it via
  // the optional titleSuffix arg (AC4).
  it("matches a suffixed campaign-calendar digest when titleSuffix is supplied (AC4)", () => {
    expect(
      isRealScheduledDigest(
        {
          title: `${CC_PREFIX} ${CC_DATE}${CC_SUFFIX}`,
          body: "## Campaign Calendar\nupcoming",
        },
        CC_DATE,
        CC_PREFIX,
        CC_SUFFIX,
      ),
    ).toBe(true);
  });

  it("REJECTS the bare campaign-calendar title (the FAILED-audit fallback shape) when titleSuffix is required (AC4)", () => {
    expect(
      isRealScheduledDigest(
        { title: `${CC_PREFIX} ${CC_DATE}`, body: "## Campaign Calendar" },
        CC_DATE,
        CC_PREFIX,
        CC_SUFFIX,
      ),
    ).toBe(false);
  });
});

describe("digestIssueExistsForDate", () => {
  it("returns true when a real digest exists for the date", async () => {
    const octokit = octokitReturningIssues([
      { title: `${CM_PREFIX} ${CM_DATE}`, body: "## Platform Status" },
    ]);
    const exists = await digestIssueExistsForDate({
      label: CM_LABEL,
      date: CM_DATE,
      cronName: "cron-community-monitor",
      titlePrefix: CM_PREFIX,
      octokit,
    });
    expect(exists).toBe(true);
  });

  it("returns false when only a FAILED audit stub exists (does NOT suppress a real digest)", async () => {
    const octokit = octokitReturningIssues([
      {
        title: `${CM_PREFIX} ${CM_DATE}`,
        body: "Automated FAILED self-report from `cron-community-monitor`.",
      },
    ]);
    const exists = await digestIssueExistsForDate({
      label: CM_LABEL,
      date: CM_DATE,
      cronName: "cron-community-monitor",
      titlePrefix: CM_PREFIX,
      octokit,
    });
    expect(exists).toBe(false);
  });

  it("reads the fresh LIST endpoint (sort=created desc, state=all, labels)", async () => {
    const octokit = octokitReturningIssues([]);
    await digestIssueExistsForDate({
      label: CM_LABEL,
      date: CM_DATE,
      cronName: "cron-community-monitor",
      titlePrefix: CM_PREFIX,
      octokit,
    });
    const [route, params] = octokit.request.mock.calls[0];
    expect(route).toBe("GET /repos/{owner}/{repo}/issues");
    expect(params).toMatchObject({
      labels: CM_LABEL,
      state: "all",
      sort: "created",
      direction: "desc",
    });
  });

  it("fails OPEN (returns false) and reports when the LIST read throws", async () => {
    const request = vi.fn().mockRejectedValue(new Error("GitHub 502"));
    const octokit = { request } as unknown as Parameters<
      typeof digestIssueExistsForDate
    >[0]["octokit"];
    const exists = await digestIssueExistsForDate({
      label: CM_LABEL,
      date: CM_DATE,
      cronName: "cron-community-monitor",
      titlePrefix: CM_PREFIX,
      octokit,
    });
    expect(exists).toBe(false);
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
    expect(
      reportSilentFallbackSpy.mock.calls.some(
        (c) => c[1]?.op === "digest-dedup-read-failed",
      ),
    ).toBe(true);
  });

  // #5786 — campaign-calendar threads its ` (heartbeat)` suffix through (AC4).
  it("matches a suffixed campaign-calendar digest when titleSuffix is threaded through", async () => {
    const octokit = octokitReturningIssues([
      {
        title: `${CC_PREFIX} ${CC_DATE}${CC_SUFFIX}`,
        body: "## Campaign Calendar\nupcoming",
      },
    ]);
    const exists = await digestIssueExistsForDate({
      label: CC_LABEL,
      date: CC_DATE,
      cronName: "cron-campaign-calendar",
      titlePrefix: CC_PREFIX,
      titleSuffix: CC_SUFFIX,
      octokit,
    });
    expect(exists).toBe(true);
  });

  it("does NOT match the bare campaign-calendar title when titleSuffix is required", async () => {
    const octokit = octokitReturningIssues([
      { title: `${CC_PREFIX} ${CC_DATE}`, body: "## Campaign Calendar" },
    ]);
    const exists = await digestIssueExistsForDate({
      label: CC_LABEL,
      date: CC_DATE,
      cronName: "cron-campaign-calendar",
      titlePrefix: CC_PREFIX,
      titleSuffix: CC_SUFFIX,
      octokit,
    });
    expect(exists).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// #4861 — postSentryHeartbeat silent-skip is now LOUD. The unset/malformed-env
// branches previously logged at info/warn and returned; a blank heartbeat env
// then paged nowhere. They now route through the DEBOUNCED warn wrapper
// (mirrorWarnWithDebounce → warnSilentFallback → @sentry/nextjs SDK via
// SENTRY_DSN, a DIFFERENT var from the three ingest vars), so the loud path
// lands even when the ingest vars are blank. The early return is preserved (the
// change is observability, not control flow) — the POST is never attempted.
// ---------------------------------------------------------------------------
describe("postSentryHeartbeat — loud silent-skip on unset/malformed env (#4861)", () => {
  const VALID_DOMAIN = "o4509.ingest.sentry.io";
  const VALID_PROJECT = "4509999";
  const VALID_PUBLIC_KEY = "abcdef0123456789abcdef0123456789";
  let fetchSpy: ReturnType<typeof vi.fn>;
  const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

  const call = () =>
    postSentryHeartbeat({
      ok: false, // avoids the best-effort cron-fires file write
      sentryMonitorSlug: "scheduled-content-publisher",
      cronName: "cron-content-publisher",
      logger,
    });

  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    mirrorWarnWithDebounceSpy.mockClear();
    warnSilentFallbackSpy.mockClear();
    logger.info.mockClear();
    logger.warn.mockClear();
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  it("unset ingest var → mirrorWarnWithDebounce op=heartbeat-env-unset; POST NOT attempted", async () => {
    // Only two of three ingest vars set → unset branch.
    vi.stubEnv("SENTRY_INGEST_DOMAIN", VALID_DOMAIN);
    vi.stubEnv("SENTRY_PROJECT_ID", VALID_PROJECT);
    vi.stubEnv("SENTRY_PUBLIC_KEY", "");
    await call();
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(mirrorWarnWithDebounceSpy).toHaveBeenCalledTimes(1);
    const [, ctx, key, errorClass] = mirrorWarnWithDebounceSpy.mock.calls[0];
    expect((ctx as { op: string }).op).toBe("heartbeat-env-unset");
    expect((ctx as { feature: string }).feature).toBe("cron-sentry-heartbeat");
    expect((ctx as { tags: { cron: string } }).tags.cron).toBe("cron-content-publisher");
    // Debounce keyed on (cronName, op) so ~45 crons sharing this env do not flood.
    expect(key).toBe("cron-content-publisher");
    expect(errorClass).toBe("heartbeat-env-unset");
  });

  it("malformed ingest var → mirrorWarnWithDebounce op=heartbeat-env-malformed; POST NOT attempted", async () => {
    vi.stubEnv("SENTRY_INGEST_DOMAIN", "not-a-sentry-domain");
    vi.stubEnv("SENTRY_PROJECT_ID", VALID_PROJECT);
    vi.stubEnv("SENTRY_PUBLIC_KEY", VALID_PUBLIC_KEY);
    await call();
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(mirrorWarnWithDebounceSpy).toHaveBeenCalledTimes(1);
    const [, ctx, , errorClass] = mirrorWarnWithDebounceSpy.mock.calls[0];
    expect((ctx as { op: string }).op).toBe("heartbeat-env-malformed");
    expect(errorClass).toBe("heartbeat-env-malformed");
  });

  it("valid env still POSTs and does NOT emit a warn (no regression)", async () => {
    fetchSpy.mockResolvedValue(new Response(null, { status: 202 }));
    vi.stubEnv("SENTRY_INGEST_DOMAIN", VALID_DOMAIN);
    vi.stubEnv("SENTRY_PROJECT_ID", VALID_PROJECT);
    vi.stubEnv("SENTRY_PUBLIC_KEY", VALID_PUBLIC_KEY);
    await call();
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(mirrorWarnWithDebounceSpy).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// ensureDedupIssue (#2756 starvation backstop) — a stable-title, open-issue
// dedup sibling of ensureScheduledAuditIssue. Reuses the same read shape
// (labels, sort:created desc, per_page:10) but matches the EXACT title and
// scopes the dedup read to OPEN issues so an auto-closed prior alert never
// suppresses a fresh drought (the standing-condition contract).
// ---------------------------------------------------------------------------
describe("ensureDedupIssue (stable-title standing alert)", () => {
  function octokit(existing: Array<{ title: string; number: number }>) {
    const request = vi.fn(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}/issues") return { data: existing };
      return { data: { number: 4242 } };
    });
    return { request } as unknown as Parameters<typeof ensureDedupIssue>[0];
  }

  it("creates the issue when no open issue with the exact title exists", async () => {
    const client = octokit([{ title: "Some other alert", number: 7 }]);
    const res = await ensureDedupIssue(client, {
      title: "Content starvation: schedule empty",
      body: "drought",
      labels: ["action-required"],
    });
    expect(res.created).toBe(true);
    const calls = (client.request as unknown as ReturnType<typeof vi.fn>).mock.calls;
    // GET then POST
    expect(calls[0][0]).toBe("GET /repos/{owner}/{repo}/issues");
    expect(calls[0][1].state).toBe("open");
    expect(calls[0][1].sort).toBe("created");
    expect(calls[0][1].direction).toBe("desc");
    expect(calls[0][1].per_page).toBe(10);
    expect(calls[1][0]).toBe("POST /repos/{owner}/{repo}/issues");
  });

  it("does NOT create a duplicate when an open issue with the exact title exists", async () => {
    const client = octokit([
      { title: "Content starvation: schedule empty", number: 99 },
    ]);
    const res = await ensureDedupIssue(client, {
      title: "Content starvation: schedule empty",
      body: "drought",
      labels: ["action-required"],
    });
    expect(res.created).toBe(false);
    expect(res.issueNumber).toBe(99);
    const calls = (client.request as unknown as ReturnType<typeof vi.fn>).mock.calls;
    expect(calls.length).toBe(1); // GET only, no POST
  });
});

// #cost-attribution (plan Phase 3, AC6 security F1) — getAnthropicAdminReport
// MUST mirror postAnthropicMessage's two redaction properties: the network-catch
// rethrow carries neither the admin key nor request context, and the non-ok body
// excerpt routes through formatTailForSentry.
describe("getAnthropicAdminReport (Admin transport redaction, security F1)", () => {
  const ADMIN_KEY = "sk-ant-admin01-" + "synthetic";
  let fetchSpy: ReturnType<typeof vi.fn>;
  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("sends x-api-key + version headers and appends array query params (group_by[])", async () => {
    fetchSpy.mockResolvedValue(new Response(JSON.stringify({ data: [] }), { status: 200 }));
    await getAnthropicAdminReport({
      adminKey: ADMIN_KEY,
      path: "/v1/organizations/usage_report/messages",
      query: { starting_at: "2026-07-08", bucket_width: "1d", "group_by[]": ["model"] },
    });
    const [url, init] = fetchSpy.mock.calls[0] as [URL, RequestInit & { headers: Record<string, string> }];
    expect(url.toString()).toContain("group_by%5B%5D=model");
    expect(url.toString()).toContain("bucket_width=1d");
    expect(init.method).toBe("GET");
    expect(init.headers["x-api-key"]).toBe(ADMIN_KEY);
    expect(init.headers["anthropic-version"]).toBe("2023-06-01");
  });

  it("network-catch rethrow contains NEITHER the admin key NOR request context", async () => {
    fetchSpy.mockRejectedValue(
      new TypeError(`fetch failed to https://api.anthropic.com with x-api-key ${ADMIN_KEY}`),
    );
    const err = await getAnthropicAdminReport({
      adminKey: ADMIN_KEY,
      path: "/v1/organizations/cost_report",
      query: {},
    }).catch((e: Error) => e);
    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).not.toContain(ADMIN_KEY);
    expect((err as Error).message).toBe("Anthropic Admin API request failed (TypeError)");
  });

  it("non-ok throws a typed AnthropicApiError with the status (401/403 classifiable)", async () => {
    fetchSpy.mockResolvedValue(new Response("forbidden", { status: 403 }));
    const err = await getAnthropicAdminReport({
      adminKey: ADMIN_KEY,
      path: "/v1/organizations/cost_report",
      query: {},
    }).catch((e: Error) => e);
    expect(err).toBeInstanceOf(AnthropicApiError);
    expect((err as AnthropicApiError).status).toBe(403);
  });
});
