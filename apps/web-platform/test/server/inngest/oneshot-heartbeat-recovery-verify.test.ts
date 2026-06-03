// Unit tests for the one-time watchdog-recovery verifier (PR #4881 follow-up).
//
// Coverage:
//   (a) Registration smoke + source-shape anchors (event name, id).
//   (b) Handler behavior — date guard, clean-pass verdict, regression detection.

import { beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const reportSilentFallbackSpy = vi.fn();
const warnSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: (...a: unknown[]) => warnSilentFallbackSpy(...a),
}));

const octokitRequestSpy = vi.fn();
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = (...a: unknown[]) => octokitRequestSpy(...a);
  },
}));

vi.mock("@/server/inngest/functions/_cron-shared", () => ({
  REPO_OWNER: "jikig-ai",
  REPO_NAME: "soleur",
  mintInstallationToken: vi.fn().mockResolvedValue("ghs_test_token"),
}));

import {
  oneshotHeartbeatRecoveryVerify,
  oneshotHeartbeatRecoveryVerifyHandler,
} from "@/server/inngest/functions/oneshot-heartbeat-recovery-verify";

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/**
 * Octokit dispatcher. `openSilenceTitles` are the OPEN cloud-task-silence issue
 * titles; `cmCreatedAt` is the latest scheduled-community-monitor issue's
 * created_at (or null for none).
 */
function dispatcher(opts: {
  openSilenceTitles?: string[];
  cmCreatedAt?: string | null;
}) {
  return async (route: string, params: Record<string, unknown> = {}) => {
    if (route === "GET /repos/{owner}/{repo}/issues") {
      if (params.labels === "cloud-task-silence") {
        return { data: (opts.openSilenceTitles ?? []).map((title) => ({ title })) };
      }
      if (params.labels === "scheduled-community-monitor") {
        return {
          data: opts.cmCreatedAt ? [{ created_at: opts.cmCreatedAt }] : [],
        };
      }
    }
    // POST comment
    return { data: {} };
  };
}

function makeArgs(data: Record<string, unknown>) {
  return {
    event: { data },
    step: { run: async (_name: string, fn: () => unknown) => fn() },
    logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  } as unknown as Parameters<typeof oneshotHeartbeatRecoveryVerifyHandler>[0];
}

describe("oneshotHeartbeatRecoveryVerify — registration", () => {
  it("loads without throwing", () => {
    expect(oneshotHeartbeatRecoveryVerify).toBeDefined();
    expect(typeof oneshotHeartbeatRecoveryVerify).toBe("object");
  });

  const SUT_SOURCE = readFileSync(
    resolve(
      __dirname,
      "../../../server/inngest/functions/oneshot-heartbeat-recovery-verify.ts",
    ),
    "utf-8",
  );

  it.each([
    ['id: "oneshot-heartbeat-recovery-verify"', "canonical function id"],
    ['event: "oneshot/heartbeat-recovery-verify.fire"', "self-armed event name"],
    ["#2714", "tracking issue reference"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor as string);
  });
});

describe("oneshotHeartbeatRecoveryVerifyHandler — behavior", () => {
  beforeEach(() => {
    octokitRequestSpy.mockReset();
    reportSilentFallbackSpy.mockReset();
    warnSilentFallbackSpy.mockReset();
  });

  it("fires before expected_date → date-guard no-op, no GitHub calls", async () => {
    octokitRequestSpy.mockImplementation(dispatcher({}));
    const out = await oneshotHeartbeatRecoveryVerifyHandler(
      makeArgs({ expected_date: "2026-06-04", date_override: "2026-06-03" }),
    );
    expect(out).toEqual({ ok: false, reason: "date-guard" });
    expect(warnSilentFallbackSpy.mock.calls[0][1].op).toBe("date-guard");
    expect(octokitRequestSpy).not.toHaveBeenCalled();
  });

  it("clean pass → posts verdict to #2714, no regression error", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({
        // content-generator/roadmap-review may legitimately still be open;
        // only legal-audit / strategy-review re-firing is a regression.
        openSilenceTitles: ["[cloud-task-silence] content-generator silent"],
        cmCreatedAt: "2026-06-04T08:05:00Z",
      }),
    );
    const out = await oneshotHeartbeatRecoveryVerifyHandler(
      makeArgs({ expected_date: "2026-06-04", date_override: "2026-06-04" }),
    );
    expect(out).toEqual({ ok: true, reason: "verified" });
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();

    const post = octokitRequestSpy.mock.calls.find(
      (c) =>
        c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments" &&
        (c[1] as { issue_number?: number }).issue_number === 2714,
    );
    expect(post).toBeDefined();
    const body = (post![1] as { body: string }).body;
    expect(body).toContain("✅ PASS");
    expect(body).toContain("recovered"); // community-monitor produced a fresh issue
  });

  it("false positive re-fired → reportSilentFallback(calibration-regression)", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({
        openSilenceTitles: ["[cloud-task-silence] legal-audit silent"],
        cmCreatedAt: null,
      }),
    );
    const out = await oneshotHeartbeatRecoveryVerifyHandler(
      makeArgs({ expected_date: "2026-06-04", date_override: "2026-06-04" }),
    );
    expect(out).toEqual({ ok: false, reason: "calibration-regression" });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("calibration-regression");
    // still posts the verdict (REGRESSION) before alerting
    const post = octokitRequestSpy.mock.calls.find(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect((post![1] as { body: string }).body).toContain("🔴 REGRESSION");
  });

  it("invalid expected_date → reportSilentFallback, no GitHub calls", async () => {
    octokitRequestSpy.mockImplementation(dispatcher({}));
    const out = await oneshotHeartbeatRecoveryVerifyHandler(
      makeArgs({ expected_date: "2026-13-45" }),
    );
    expect(out).toEqual({ ok: false, reason: "invalid-expected-date" });
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("expected-date-validation");
    expect(octokitRequestSpy).not.toHaveBeenCalled();
  });
});
