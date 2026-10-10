/**
 * #9776 — the lane's two arms the main suite cannot reach.
 *
 *  (1) A classifier that throws is a MATCH, never a pass: the lane asks and mirrors `destroy-classifier-error` to
 *      Sentry (AC-7). The classifier module is replaced here (a separate file: `vi.mock` is file-scoped).
 *  (2) The legacy runner (`agent-runner.ts`) builds `canUseTool` with no `bashAutonomous`, no batch cache and no
 *      resolver, so every non-safe Bash command already reaches the generic gate there (AC-5). Pinned by reading the
 *      call site, anchored on the constructs that define the slice.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const { mockLog, mockWarnSilentFallback, mockReportSilentFallback } = vi.hoisted(() => ({
  mockLog: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockWarnSilentFallback: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("../server/logger", () => ({ createChildLogger: () => mockLog, default: mockLog }));
vi.mock("../server/permission-log", () => ({ logPermissionDecision: vi.fn() }));
vi.mock("../server/observability", () => ({
  warnSilentFallback: mockWarnSilentFallback,
  reportSilentFallback: mockReportSilentFallback,
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));
vi.mock("../server/destroy-ask-classifier", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/destroy-ask-classifier")>();
  return {
    ...actual,
    classifyDestroyFamily: vi.fn(async () => ({
      ruleId: `${actual.DESTROY_RULE_PREFIX}classifier-error`,
      family: "fail-closed" as const,
      error: new Error("classifier blew up"),
      authoritative: null,
    })),
  };
});

import { createCanUseTool, type CanUseToolContext } from "../server/permission-callback";

beforeEach(() => vi.clearAllMocks());

describe("a thrown classifier error is an ask (AC-7)", () => {
  test("the lane shows the card and mirrors destroy-classifier-error to Sentry, without the command", async () => {
    const deps = {
      abortableReviewGate: vi.fn().mockResolvedValue("Reject"),
      sendToClient: vi.fn().mockReturnValue(true),
      notifyOfflineUser: vi.fn().mockResolvedValue(true),
      updateConversationStatus: vi.fn().mockResolvedValue(undefined),
      bashAutonomous: true,
      autonomousAckAt: 1_700_000_000_000,
      isOwner: true,
    };
    const ctx = {
      userId: "u",
      conversationId: "c",
      leaderId: "cc_router",
      workspacePath: "/tmp/ws",
      platformToolNames: [],
      pluginMcpServerNames: [],
      repoOwner: "",
      repoName: "",
      session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
      controllerSignal: new AbortController().signal,
      deps,
    } as unknown as CanUseToolContext;
    const secretish = "make something-unusual SECRET_ARG_77";
    const res = await createCanUseTool(ctx)(
      "Bash",
      { command: secretish },
      { signal: new AbortController().signal, toolUseID: "t", requestId: "r" },
    );
    expect(res?.behavior).toBe("deny"); // the mock gate answered Reject, so the command did not run
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(deps.abortableReviewGate.mock.calls[0][4]).toEqual(["Approve", "Reject"]);
    const call = mockReportSilentFallback.mock.calls.find((c) => c[1]?.op === "destroy-classifier-error");
    expect(call).toBeDefined();
    expect(call![1]).toMatchObject({ feature: "cc-permissions", extra: { ruleId: "hosted-destroy-ask:classifier-error" } });
    expect(JSON.stringify([mockReportSilentFallback.mock.calls, mockWarnSilentFallback.mock.calls, mockLog.warn.mock.calls])).not.toContain("SECRET_ARG_77");
  });
});

describe("legacy runner is always review-gate (AC-5)", () => {
  test("agent-runner's createCanUseTool call passes no bashAutonomous, no batch cache and no resolver", () => {
    const src = readFileSync(join(__dirname, "..", "server", "agent-runner.ts"), "utf8");
    const start = src.indexOf("canUseTool: createCanUseTool({");
    expect(start, "anchor: the legacy call site").toBeGreaterThan(-1);
    const endMarker = "updateConversationStatus(userId, convId";
    const end = src.indexOf(endMarker, start);
    expect(end, "anchor: the deps block closes after updateConversationStatus").toBeGreaterThan(start);
    const slice = src.slice(start, end + endMarker.length);
    // The slice must contain the constructs that define it, or it is a truncated read.
    for (const must of ["abortableReviewGate", "sendToClient", "notifyOfflineUser", "deps: {"]) expect(slice).toContain(must);
    for (const forbidden of ["bashAutonomous", "bashApprovalCache", "resolveProtectedBranches", "autonomousAckAt"]) {
      expect(slice, forbidden).not.toContain(forbidden);
    }
  });
});
