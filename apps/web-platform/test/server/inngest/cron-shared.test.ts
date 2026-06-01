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
