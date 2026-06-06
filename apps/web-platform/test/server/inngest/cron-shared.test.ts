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

import { afterEach, describe, expect, it, vi } from "vitest";

const reportSilentFallbackSpy = vi.fn();
const warnSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: (...a: unknown[]) => warnSilentFallbackSpy(...a),
}));

import {
  ensureScheduledAuditIssue,
  resolveOutputAwareOk,
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

  it("credits a dedup-comment: issue created last week but UPDATED this run window → true", async () => {
    // roadmap-review's DEDUP RULE comments on the most-recent existing issue
    // instead of creating a new one (manual-trigger + cron same week). That is
    // a HEALTHY run with no new issue — updated_at moved into the window, so
    // it must NOT false-red. Verifying on created_at would have failed here.
    const octokit = octokitReturning([
      { updated_at: "2026-05-31T09:31:00.000Z" }, // commented this run...
    ]);
    const result = await verifyScheduledIssueCreated({
      label: "scheduled-roadmap-review",
      sinceIso: RUN_START, // ...even though the issue was created days earlier
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
