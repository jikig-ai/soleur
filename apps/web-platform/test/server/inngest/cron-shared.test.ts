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
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: vi.fn(),
}));

import {
  resolveOutputAwareOk,
  verifyScheduledIssueCreated,
} from "@/server/inngest/functions/_cron-shared";

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
  it("spawn failed → ok:false, verify skipped, no output-missing event", async () => {
    const octokit = octokitReturning([]);
    const ok = await resolveOutputAwareOk({
      spawnOk: false,
      label: "scheduled-roadmap-review",
      runStartedAt: RUN_START,
      cronName: "cron-roadmap-review",
      octokit,
    });
    expect(ok).toBe(false);
    expect(octokit.request).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("spawn ok + issue present → ok:true, no event", async () => {
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
  });

  it("spawn ok + NO issue → ok:false + scheduled-output-missing event (the fix)", async () => {
    const octokit = octokitReturning([
      { updated_at: "2026-05-18T12:00:00.000Z" }, // last week, before window
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
    expect(opts.feature).toBe("cron-roadmap-review");
  });

  it("spawn ok + verify THREW → ok:true (inconclusive) + verify-output-failed event", async () => {
    const request = vi.fn().mockRejectedValue(new Error("GitHub 502"));
    const octokit = { request } as unknown as Parameters<
      typeof resolveOutputAwareOk
    >[0]["octokit"];
    const ok = await resolveOutputAwareOk({
      spawnOk: true,
      label: "scheduled-content-generator",
      runStartedAt: RUN_START,
      cronName: "cron-content-generator",
      octokit,
    });
    expect(ok).toBe(true); // do NOT red-flag a possibly-successful run
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe(
      "verify-output-failed",
    );
  });
});
