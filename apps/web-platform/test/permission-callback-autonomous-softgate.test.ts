/**
 * feat-bash-autonomous-default-on — first-run consent soft-gate.
 *
 * Default-ON autonomous workspaces must HOLD the FIRST non-blocked Bash command
 * behind a one-time owner disclosure ack, instead of silently auto-running it.
 *
 *   - bashAutonomous && ackAt == null && owner  ⇒ HOLD: emit an
 *     `autonomous_disclosure` frame, await the ack via the review-gate bridge,
 *     do NOT `allow()` until the owner responds.
 *   - bashAutonomous && ackAt != null           ⇒ friction-free `allow` (no frame).
 *   - bashAutonomous && ackAt == null && !owner  ⇒ fall through to the
 *     review-gate (treat as not-autonomous — no ack button they can't use).
 *   - blocklist stays authoritative BEFORE the autonomous branch.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";

const {
  mockIsFileTool,
  mockIsSafeTool,
  mockIsPathInWorkspace,
  mockExtractToolPath,
  mockGetToolTier,
  mockExtractReviewGateInput,
  mockBuildReviewGateResponse,
  mockBuildGateMessage,
  mockWarnSilentFallback,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockIsFileTool: vi.fn(() => false),
  mockIsSafeTool: vi.fn(() => false),
  mockIsPathInWorkspace: vi.fn(() => true),
  mockExtractToolPath: vi.fn(() => null as string | null),
  mockGetToolTier: vi.fn(() => "auto-approve" as const),
  mockExtractReviewGateInput: vi.fn(() => ({
    question: "",
    options: ["Approve", "Reject"],
    descriptions: {},
    header: undefined,
    isNewSchema: false,
  })),
  mockBuildReviewGateResponse: vi.fn(() => ({ answer: "Approve" })),
  mockBuildGateMessage: vi.fn(() => "Permission needed"),
  mockWarnSilentFallback: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [] as readonly string[],
  extractToolPath: mockExtractToolPath,
  isFileTool: mockIsFileTool,
  isSafeTool: mockIsSafeTool,
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: mockIsPathInWorkspace }));
vi.mock("../server/tool-tiers", () => ({
  getToolTier: mockGetToolTier,
  buildGateMessage: mockBuildGateMessage,
}));
vi.mock("../server/review-gate", () => ({
  extractReviewGateInput: mockExtractReviewGateInput,
  buildReviewGateResponse: mockBuildReviewGateResponse,
}));
vi.mock("../server/observability", () => ({
  warnSilentFallback: mockWarnSilentFallback,
  reportSilentFallback: mockReportSilentFallback,
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));

import {
  createCanUseTool,
  type CanUseToolContext,
} from "../server/permission-callback";

function buildContext(depsOverrides: Record<string, unknown> = {}) {
  const deps = {
    abortableReviewGate: vi.fn().mockResolvedValue("Got it"),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(undefined),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
    ...depsOverrides,
  };
  const ctx = {
    userId: "user-1",
    conversationId: "conv-1",
    leaderId: "cc_router",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "alice",
    repoName: "repo",
    session: {
      abort: new AbortController(),
      reviewGateResolvers: new Map(),
      sessionId: null,
    },
    controllerSignal: new AbortController().signal,
    deps,
  } as unknown as CanUseToolContext;
  return { ctx, deps };
}

function sdkOptions() {
  return { signal: new AbortController().signal, toolUseID: "tu-1" };
}

describe("autonomous first-run soft-gate", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsFileTool.mockReturnValue(false);
    mockIsSafeTool.mockReturnValue(false);
  });

  test("autonomous + un-acked + owner ⇒ HOLD: emits autonomous_disclosure, no auto-allow", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: true,
      autonomousAckAt: null,
      isOwner: true,
    });
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "rm -rf build" },
      sdkOptions(),
    );
    // The disclosure frame must be sent.
    const disclosureSends = (deps.sendToClient as ReturnType<typeof vi.fn>).mock
      .calls.map((c) => c[1])
      .filter((p: { type?: string }) => p.type === "autonomous_disclosure");
    expect(disclosureSends.length).toBe(1);
    expect(disclosureSends[0].existingWorkspace).toBe(false);
    // The held command awaited the gate bridge (did not silently auto-bypass).
    expect(deps.abortableReviewGate).toHaveBeenCalled();
    // After "Got it" the command proceeds.
    expect(result.behavior).toBe("allow");
  });

  test("autonomous + ACKED ⇒ friction-free allow, NO disclosure frame", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: true,
      autonomousAckAt: 1_700_000_000_000,
      isOwner: true,
    });
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "rm -rf build" },
      sdkOptions(),
    );
    expect(result.behavior).toBe("allow");
    const disclosureSends = (deps.sendToClient as ReturnType<typeof vi.fn>).mock
      .calls.map((c) => c[1])
      .filter((p: { type?: string }) => p.type === "autonomous_disclosure");
    expect(disclosureSends.length).toBe(0);
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
  });

  test("autonomous + un-acked + NON-owner ⇒ review-gate fallback (no disclosure frame)", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: true,
      autonomousAckAt: null,
      isOwner: false,
    });
    const canUseTool = createCanUseTool(ctx);
    await canUseTool("Bash", { command: "git push origin HEAD" }, sdkOptions());
    const sends = (deps.sendToClient as ReturnType<typeof vi.fn>).mock.calls.map(
      (c) => c[1],
    );
    expect(
      sends.some((p: { type?: string }) => p.type === "autonomous_disclosure"),
    ).toBe(false);
    // Falls through to the review-gate.
    expect(
      sends.some((p: { type?: string }) => p.type === "review_gate"),
    ).toBe(true);
  });

  test("blocklist authoritative under un-acked autonomy: `sudo` STILL denies", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: true,
      autonomousAckAt: null,
      isOwner: true,
    });
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "sudo rm -rf /" },
      sdkOptions(),
    );
    expect(result.behavior).toBe("deny");
    expect(deps.sendToClient).not.toHaveBeenCalled();
  });

  test("P1 stale-snapshot: command #2 after an in-session ack is allowed with NO second hold", async () => {
    // The cold-start ack snapshot is null (un-acked). After the owner acks, the
    // in-session posture flips (resolveAckPosture returns a non-null ts). Command
    // #2 in the SAME dispatch must auto-allow WITHOUT re-emitting a disclosure
    // frame or re-awaiting a gate.
    let ackPosture: number | null = null;
    const { ctx, deps } = buildContext({
      bashAutonomous: true,
      autonomousAckAt: null, // frozen cold-start snapshot stays null
      isOwner: true,
      // Mutable in-session posture getter (mirrors setBashAutonomous cell).
      resolveAckPosture: () => ackPosture,
      verifyAutonomousAck: vi.fn().mockResolvedValue("2026-06-04T00:00:00Z"),
      abortableReviewGate: vi.fn().mockImplementation(async () => {
        // Simulate the ws-handler writing the ack on "Got it".
        ackPosture = 1_700_000_000_000;
        return "Got it";
      }),
    });
    const canUseTool = createCanUseTool(ctx);

    // Command #1 — held, acked, released.
    const r1 = await canUseTool("Bash", { command: "rm -rf build" }, sdkOptions());
    expect(r1.behavior).toBe("allow");
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1);

    // Command #2 — must NOT hold again (posture now acked).
    const r2 = await canUseTool("Bash", { command: "npm run build" }, sdkOptions());
    expect(r2.behavior).toBe("allow");
    // No SECOND gate awaited.
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1);
    const disclosureSends = (deps.sendToClient as ReturnType<typeof vi.fn>).mock
      .calls.map((c) => c[1])
      .filter((p: { type?: string }) => p.type === "autonomous_disclosure");
    expect(disclosureSends.length).toBe(1); // only the first command emitted one
  });

  test("P1 defense-in-depth: gate released but ack NOT persisted ⇒ command re-held (deny)", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: true,
      autonomousAckAt: null,
      isOwner: true,
      // The gate resolved "Got it" but the ack write never landed.
      verifyAutonomousAck: vi.fn().mockResolvedValue(null),
      abortableReviewGate: vi.fn().mockResolvedValue("Got it"),
    });
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "rm -rf build" },
      sdkOptions(),
    );
    expect(
      (deps as unknown as { verifyAutonomousAck: ReturnType<typeof vi.fn> })
        .verifyAutonomousAck,
    ).toHaveBeenCalled();
    expect(result.behavior).toBe("deny");
  });

  test("P3 existing-workspace: un-acked owner with bashAutonomous=false ⇒ HOLD w/ existingWorkspace:true; 'Keep autonomous on' ⇒ allow", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: false, // existing (stored false) workspace
      autonomousAckAt: null,
      isOwner: true,
      verifyAutonomousAck: vi.fn().mockResolvedValue("2026-06-04T00:00:00Z"),
      abortableReviewGate: vi.fn().mockResolvedValue("Keep autonomous on"),
    });
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "rm -rf build" },
      sdkOptions(),
    );
    const disclosureSends = (deps.sendToClient as ReturnType<typeof vi.fn>).mock
      .calls.map((c) => c[1])
      .filter((p: { type?: string }) => p.type === "autonomous_disclosure");
    expect(disclosureSends.length).toBe(1);
    expect(disclosureSends[0].existingWorkspace).toBe(true);
    expect(result.behavior).toBe("allow");
  });

  test("P3 existing-workspace: 'Ask me each time' ⇒ falls through to the review-gate (manual approve)", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: false,
      autonomousAckAt: null,
      isOwner: true,
      // First call (disclosure hold) returns "Ask me each time"; second call
      // (the review-gate fallback) returns "Approve".
      abortableReviewGate: vi
        .fn()
        .mockResolvedValueOnce("Ask me each time")
        .mockResolvedValueOnce("Approve"),
    });
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "rm -rf build" },
      sdkOptions(),
    );
    const sends = (deps.sendToClient as ReturnType<typeof vi.fn>).mock.calls.map(
      (c) => c[1],
    );
    // Both a disclosure (existingWorkspace:true) AND a review_gate were emitted.
    expect(
      sends.some(
        (p: { type?: string; existingWorkspace?: boolean }) =>
          p.type === "autonomous_disclosure" && p.existingWorkspace === true,
      ),
    ).toBe(true);
    expect(sends.some((p: { type?: string }) => p.type === "review_gate")).toBe(
      true,
    );
    // The review-gate "Approve" allows the command.
    expect(result.behavior).toBe("allow");
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(2);
  });

  test("P3 existing-workspace: NON-owner with bashAutonomous=false ⇒ straight to review-gate (no disclosure)", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: false,
      autonomousAckAt: null,
      isOwner: false,
      abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
    });
    const canUseTool = createCanUseTool(ctx);
    await canUseTool("Bash", { command: "rm -rf build" }, sdkOptions());
    const sends = (deps.sendToClient as ReturnType<typeof vi.fn>).mock.calls.map(
      (c) => c[1],
    );
    expect(
      sends.some((p: { type?: string }) => p.type === "autonomous_disclosure"),
    ).toBe(false);
    expect(sends.some((p: { type?: string }) => p.type === "review_gate")).toBe(
      true,
    );
  });

  test("user rejects via 'Ask me each time' ⇒ command denied (review-gate fallback semantics)", async () => {
    const { ctx, deps } = buildContext({
      bashAutonomous: true,
      autonomousAckAt: null,
      isOwner: true,
      abortableReviewGate: vi.fn().mockResolvedValue("Ask me each time"),
    });
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "rm -rf build" },
      sdkOptions(),
    );
    expect(deps.abortableReviewGate).toHaveBeenCalled();
    expect(result.behavior).toBe("deny");
  });
});
