import { beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest), mirroring oneshot-4650 -------------

const {
  reportSilentFallbackSpy,
  warnSilentFallbackSpy,
  mintInstallationTokenSpy,
  octokitRequestSpy,
} = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  warnSilentFallbackSpy: vi.fn(),
  mintInstallationTokenSpy: vi.fn(async () => "ghs_test_token_abc"),
  octokitRequestSpy: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { createFunction: vi.fn(), send: vi.fn() },
}));

vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return { ...actual, mintInstallationToken: mintInstallationTokenSpy };
});

vi.mock("@octokit/core", () => ({
  Octokit: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.request = octokitRequestSpy;
  }),
}));

import {
  eventScheduledReminderHandler,
  CHECK_REGISTRY,
} from "@/server/inngest/functions/event-scheduled-reminder";

// --- Helpers ----------------------------------------------------------------

function makeStep() {
  const calls: { name: string }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      calls.push({ name });
      return cb();
    },
  };
}

function run(data: Record<string, unknown>) {
  const step = makeStep();
  return {
    step,
    result: eventScheduledReminderHandler({
      event: { data },
      step,
    } as never),
  };
}

const FIRE_AT = "2026-06-04T09:45:00Z";

beforeEach(() => {
  reportSilentFallbackSpy.mockReset();
  warnSilentFallbackSpy.mockReset();
  octokitRequestSpy.mockReset();
  mintInstallationTokenSpy.mockClear();
  octokitRequestSpy.mockResolvedValue({ data: [] });
});

describe("eventScheduledReminderHandler — guards", () => {
  it("invalid fire_at → reportSilentFallback(invalid-fire-at), no IO", async () => {
    const { result, step } = run({
      reminder_id: "r1",
      fire_at: "not-a-date",
      actor: "platform",
      action: { type: "issue-comment", issue: 2714, body: "hi" },
    });
    expect(await result).toEqual({ ok: false, reason: "invalid-fire-at" });
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("invalid-fire-at");
    expect(step.calls).toHaveLength(0);
    expect(octokitRequestSpy).not.toHaveBeenCalled();
  });

  it("non-allowlisted action.type → reject, no IO", async () => {
    const { result, step } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "label", issue: 1, name: "bug" },
    });
    expect(await result).toEqual({ ok: false, reason: "action-not-allowlisted" });
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("action-not-allowlisted");
    expect(step.calls).toHaveLength(0);
  });

  it("issue-comment body over cap → reject before any IO", async () => {
    const { result } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "issue-comment", issue: 1, body: "x".repeat(65001) },
    });
    expect(await result).toEqual({ ok: false, reason: "invalid-issue-comment" });
    expect(octokitRequestSpy).not.toHaveBeenCalled();
  });
});

describe("eventScheduledReminderHandler — issue-comment", () => {
  it("posts a comment via the installation token", async () => {
    const { result, step } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "issue-comment", issue: 2714, body: "scheduled note" },
    });
    expect(await result).toEqual({ ok: true, reason: "issue-comment-posted" });
    expect(step.calls).toEqual([{ name: "post-comment" }]);
    expect(mintInstallationTokenSpy).toHaveBeenCalledTimes(1);
    const post = octokitRequestSpy.mock.calls.find(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(post![1]).toMatchObject({ issue_number: 2714, body: "scheduled note" });
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });
});

describe("eventScheduledReminderHandler — named-check", () => {
  it("unregistered check → reportSilentFallback(unregistered-check), no comment", async () => {
    const { result } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "named-check", check: "does-not-exist", report_to_issue: 2714 },
    });
    expect(await result).toEqual({ ok: false, reason: "unregistered-check" });
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("unregistered-check");
    const posts = octokitRequestSpy.mock.calls.filter((c) =>
      String(c[0]).includes("/comments"),
    );
    expect(posts).toHaveLength(0);
  });

  it("registered demonstrator → runs check, posts body to report_to_issue", async () => {
    // The seeded check reads cloud-task-silence issues, then posts.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}/issues") {
        return { data: [{ id: 1 }, { id: 2 }] };
      }
      return { data: {} };
    });
    const { result } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: {
        type: "named-check",
        check: "open-silence-issue-count",
        report_to_issue: 2714,
      },
    });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    const post = octokitRequestSpy.mock.calls.find(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(post![1]).toMatchObject({ issue_number: 2714 });
    expect((post![1] as { body: string }).body).toContain("2 open");
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("verdict fail → reportSilentFallback(named-check-failed) but still posts", async () => {
    // Inject a temporary failing check into the registry (restore after).
    CHECK_REGISTRY["__test-fail"] = async () => ({ verdict: "fail", body: "boom" });
    try {
      const { result } = run({
        reminder_id: "r1",
        fire_at: FIRE_AT,
        actor: "platform",
        action: { type: "named-check", check: "__test-fail", report_to_issue: 2714 },
      });
      expect(await result).toEqual({ ok: true, reason: "named-check-fail" });
      expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("named-check-failed");
      const post = octokitRequestSpy.mock.calls.find(
        (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      );
      expect((post![1] as { body: string }).body).toBe("boom");
    } finally {
      delete CHECK_REGISTRY["__test-fail"];
    }
  });

  it("seeds exactly the open-silence-issue-count demonstrator", () => {
    expect(Object.keys(CHECK_REGISTRY)).toEqual(["open-silence-issue-count"]);
  });
});
