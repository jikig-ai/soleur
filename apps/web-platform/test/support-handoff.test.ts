/**
 * Support-persona write-requiring-task handoff affordance (#9539, ADR-113 addendum).
 *
 * Deterministic unit tests — no SDK/LLM invocation
 * (learning 2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md).
 *
 * Covers: the escalation registry, the deny→record wiring in createCanUseTool
 * (Skill deny, Bash short-circuit incl. the autonomous auto-allow path, the
 * blocklist deny, and the AskUserQuestion belt), the consume-gated terminal
 * emit (`supportTerminalPrefixFrames`), the `handoffMarkdown` reducer field +
 * `composeSupportBubbleText` (which survives stream-replace AND error-fallback),
 * and the route-level emit ordering through the SSE body.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";
import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";
import type { WSMessage } from "@/lib/types";

const { mockIsFileTool, mockIsSafeTool } = vi.hoisted(() => ({
  mockIsFileTool: vi.fn(() => false),
  // Real SAFE_TOOLS includes "Skill" → without the support branch, any Skill call allows.
  mockIsSafeTool: vi.fn((t: string) => t === "Skill"),
}));

vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [] as readonly string[],
  extractToolPath: vi.fn(() => null),
  isFileTool: mockIsFileTool,
  isSafeTool: mockIsSafeTool,
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-tiers", () => ({
  getToolTier: vi.fn(() => "auto-approve"),
  buildGateMessage: vi.fn(() => "Permission needed"),
}));
vi.mock("../server/review-gate", () => ({
  extractReviewGateInput: vi.fn(() => ({
    question: "Continue?",
    options: ["Approve", "Reject"],
    descriptions: {},
    header: undefined,
    isNewSchema: false,
  })),
  buildReviewGateResponse: vi.fn(() => ({ answer: "Approve" })),
}));

import {
  createCanUseTool,
  type CanUseToolContext,
  type CanUseToolDeps,
} from "../server/permission-callback";
import {
  recordSupportEscalation,
  consumeSupportEscalation,
  clearSupportEscalation,
} from "../server/support-escalation";
import {
  parseSupportSseChunks,
  reduceSupportFrame,
  initialSupportStream,
  composeSupportBubbleText,
  supportTerminalPrefixFrames,
  SUPPORT_TERMINAL_FRAME_TYPES,
} from "../lib/support-sse";
import {
  buildSupportHandoffMarkdown,
  truncateSupportHandoffTask,
} from "../lib/support-handoff";

function buildDeps(overrides: Partial<CanUseToolDeps> = {}): CanUseToolDeps {
  return {
    abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  };
}

function buildContext(overrides: Partial<CanUseToolContext> = {}): CanUseToolContext {
  return {
    userId: "user-1",
    conversationId: "conv-1",
    leaderId: "cc-router",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: new AbortController().signal,
    deps: buildDeps(),
    ...overrides,
  };
}

const opts = () => ({ signal: new AbortController().signal, toolUseID: "tu-1", requestId: "req-1" });

function assertDeny(r: PermissionResult | null) {
  expect(r).not.toBeNull();
  if (r === null) throw new Error("unreachable");
  expect(r.behavior).toBe("deny");
  if (r.behavior !== "deny") throw new Error("unreachable");
  return r;
}
function assertAllow(r: PermissionResult | null) {
  expect(r).not.toBeNull();
  if (r === null) throw new Error("unreachable");
  expect(r.behavior).toBe("allow");
  return r;
}

const GATE_FRAME_TYPES = new Set([
  "review_gate",
  "bash_approval",
  "autonomous_disclosure",
  "interactive_prompt",
]);

function gateFramesSent(deps: CanUseToolDeps): unknown[] {
  const send = deps.sendToClient as ReturnType<typeof vi.fn>;
  return send.mock.calls
    .map((c) => c[1])
    .filter((m: { type?: string }) => GATE_FRAME_TYPES.has(m?.type ?? ""));
}

beforeEach(() => {
  vi.clearAllMocks();
  clearSupportEscalation("conv-1");
  clearSupportEscalation("conv-support-1");
});

describe("support escalation registry", () => {
  test("record → consume returns the source, consume-on-read empties it", () => {
    recordSupportEscalation("conv-1", "skill");
    expect(consumeSupportEscalation("conv-1")).toBe("skill");
    expect(consumeSupportEscalation("conv-1")).toBeNull();
  });

  test("clear drops a live flag (returns true) and reports false when empty", () => {
    expect(clearSupportEscalation("conv-1")).toBe(false);
    recordSupportEscalation("conv-1", "bash");
    expect(clearSupportEscalation("conv-1")).toBe(true);
    expect(consumeSupportEscalation("conv-1")).toBeNull();
  });
});

describe("support persona — deny → escalation record", () => {
  test("(a) non-allowlisted Skill records escalation + names 'Ask an agent'", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    const r = assertDeny(await canUse("Skill", { skill: "soleur:one-shot" }, opts()));
    expect(consumeSupportEscalation("conv-1")).toBe("skill");
    if (r.behavior === "deny") {
      expect(r.message).toMatch(/Ask an agent/);
    }
  });

  test("(b) non-safe Bash denies with zero gate frames + records 'bash'", async () => {
    const deps = buildDeps();
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    const r = assertDeny(await canUse("Bash", { command: "git checkout -b x" }, opts()));
    expect(gateFramesSent(deps)).toEqual([]);
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(consumeSupportEscalation("conv-1")).toBe("bash");
    if (r.behavior === "deny") {
      expect(r.message).toMatch(/Ask an agent/);
    }
  });

  test("(b2) autonomous + owner + acked still denies on support (silent-allow regression)", async () => {
    const deps = buildDeps({
      bashAutonomous: true,
      isOwner: true,
      autonomousAckAt: Date.now(),
      resolveAckPosture: () => Date.now(),
    });
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    assertDeny(await canUse("Bash", { command: "git checkout -b x" }, opts()));
    expect(gateFramesSent(deps)).toEqual([]);
    expect(consumeSupportEscalation("conv-1")).toBe("bash");
  });

  test("(b3) blocklisted command on support records the escalation", async () => {
    const deps = buildDeps();
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    assertDeny(await canUse("Bash", { command: "sudo ls" }, opts()));
    expect(consumeSupportEscalation("conv-1")).toBe("bash");
  });

  test("(b4) AskUserQuestion denies on support — no gate frame, NO escalation", async () => {
    const deps = buildDeps();
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    const r = assertDeny(
      await canUse(
        "AskUserQuestion",
        { questions: [{ question: "which repo?", options: [{ label: "a" }, { label: "b" }] }] },
        opts(),
      ),
    );
    expect(deps.sendToClient).not.toHaveBeenCalled();
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(consumeSupportEscalation("conv-1")).toBeNull();
    if (r.behavior === "deny") {
      expect(r.message).toMatch(/reply text/i);
    }
  });

  test("(c) command_center is byte-neutral on both paths", async () => {
    const deps = buildDeps();
    const canUse = createCanUseTool(buildContext({ deps }));
    // Non-safe Bash still reaches the review-gate (sendToClient fires).
    assertAllow(await canUse("Bash", { command: "git checkout -b x" }, opts()));
    expect(deps.sendToClient).toHaveBeenCalledWith(
      "user-1",
      expect.objectContaining({ type: "review_gate" }),
    );
    expect(consumeSupportEscalation("conv-1")).toBeNull();

    const deps2 = buildDeps();
    const canUse2 = createCanUseTool(buildContext({ deps: deps2 }));
    const r2 = await canUse2(
      "AskUserQuestion",
      { questions: [{ question: "ok?", options: [{ label: "yes" }] }] },
      opts(),
    );
    assertAllow(r2);
    expect(deps2.sendToClient).toHaveBeenCalledWith(
      "user-1",
      expect.objectContaining({ type: "review_gate" }),
    );
  });

  test("safe Bash on support still auto-allows (kb-search shell-out unaffected)", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertAllow(await canUse("Bash", { command: "git status" }, opts()));
    expect(consumeSupportEscalation("conv-1")).toBeNull();
  });
});

describe("supportTerminalPrefixFrames (consume-gated terminal emit)", () => {
  const handoff = { type: "support_handoff" as const, task: "do x", conversationId: "conv-1" };
  const end = { type: "stream_end", leaderId: "cc_router" } as WSMessage;

  test("(e) emitted BEFORE the terminal frame when an escalation was consumed", () => {
    const frames = supportTerminalPrefixFrames(end, handoff);
    expect(frames.map((f) => f.type)).toEqual(["support_handoff", "stream_end"]);
  });

  test("(f) no handoff → pass-through (vacuity guard)", () => {
    const frames = supportTerminalPrefixFrames(end, null);
    expect(frames.map((f) => f.type)).toEqual(["stream_end"]);
  });

  test("non-terminal frame → pass-through even with a handoff pending", () => {
    const stream = { type: "stream", content: "t", partial: true, leaderId: "cc_router" } as WSMessage;
    expect(supportTerminalPrefixFrames(stream, handoff)).toEqual([stream]);
  });

  test("covers every terminal type", () => {
    for (const t of SUPPORT_TERMINAL_FRAME_TYPES) {
      const terminal = { type: t } as WSMessage;
      expect(supportTerminalPrefixFrames(terminal, handoff)[0]).toEqual(handoff);
    }
  });
});

describe("reduceSupportFrame + composeSupportBubbleText (handoffMarkdown)", () => {
  test("(d) support_handoff sets handoffMarkdown and leaves text untouched", () => {
    const s = [
      { type: "stream", content: "I can't edit files.", partial: false, leaderId: "cc_router" } as WSMessage,
      { type: "support_handoff", task: "fix my page", conversationId: "c" } as unknown as WSMessage,
    ].reduce(reduceSupportFrame, initialSupportStream());
    expect(s.text).toBe("I can't edit files.");
    expect(s.handoffMarkdown).toContain("dashboard/chat/new?msg=fix%20my%20page");
  });

  test("encoding escapes parens and quotes so the markdown destination survives", () => {
    const md = buildSupportHandoffMarkdown("fix my board (CRM) page's footer");
    expect(md).toContain("?msg=fix%20my%20board%20%28CRM%29%20page%27s%20footer");
    expect(md).toMatch(/\]\(<.*>\)$/);
  });

  test("truncateSupportHandoffTask is code-point aware (no lone surrogate)", () => {
    const emoji = "🙂".repeat(600);
    const t = truncateSupportHandoffTask(emoji, 500);
    // Never throws in encodeURIComponent — would throw URIError on a lone surrogate.
    expect(() => encodeURIComponent(t)).not.toThrow();
    expect(t.endsWith("…")).toBe(true);
  });

  test("composeSupportBubbleText appends the handoff after reply text", () => {
    const s = {
      text: "reply",
      status: "done" as const,
      handoffMarkdown: "[Ask an agent](x)",
    };
    expect(composeSupportBubbleText(s)).toBe("reply\n\n[Ask an agent](x)");
  });

  test("(h) error-status state still composes the handoff (emitted-then-discarded regression)", () => {
    const s = {
      text: "partial",
      status: "error" as const,
      error: "boom",
      handoffMarkdown: "[Ask an agent](x)",
    };
    expect(composeSupportBubbleText(s)).toContain("[Ask an agent](x)");
  });

  test("handoff alone renders standalone when the reply is empty", () => {
    const s = {
      text: "",
      status: "done" as const,
      handoffMarkdown: "[Ask an agent](x)",
    };
    expect(composeSupportBubbleText(s)).toBe("[Ask an agent](x)");
  });
});

describe("SUPPORT_EXTRA_DISALLOWED_TOOLS widened", () => {
  test("interactive-prompt emitters removed at the schema layer", async () => {
    const { SUPPORT_EXTRA_DISALLOWED_TOOLS } = await import("../server/support-directive");
    for (const t of ["AskUserQuestion", "TodoWrite", "ExitPlanMode"]) {
      expect(SUPPORT_EXTRA_DISALLOWED_TOOLS).toContain(t);
    }
    expect(SUPPORT_EXTRA_DISALLOWED_TOOLS).not.toContain("Bash");
  });
});

/**
 * Route-level emit tests — exercise POST /api/support's enqueue chokepoint end
 * to end (real registry, mocked dispatch). The deny→consume→emit ordering and
 * the stream-open stale-flag clear can only be proven through the SSE body.
 */
const routeH = vi.hoisted(() => ({
  getUser: vi.fn(
    async (): Promise<{ data: { user: { id: string } | null } }> => ({
      data: { user: { id: "user-1" } },
    }),
  ),
  dispatchSoleurGo: vi.fn(),
  resolveOrCreateSupportConversation: vi.fn(async () => "conv-support-1"),
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app" })),
  getRuntimeFlag: vi.fn(async () => true),
  resolveIdentity: vi.fn(async () => ({ userId: "user-1", role: "prd", orgId: null })),
}));
vi.mock("../lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: routeH.getUser } })),
}));
vi.mock("../lib/auth/validate-origin", () => ({
  validateOrigin: routeH.validateOrigin,
  rejectCsrf: () => new Response("csrf", { status: 403 }),
}));
vi.mock("../lib/feature-flags/identity", () => ({ resolveIdentity: routeH.resolveIdentity }));
vi.mock("../lib/feature-flags/server", () => ({ getRuntimeFlag: routeH.getRuntimeFlag }));
vi.mock("../server/cc-dispatcher", () => ({ dispatchSoleurGo: routeH.dispatchSoleurGo }));
vi.mock("../server/support-conversation", () => ({
  resolveOrCreateSupportConversation: routeH.resolveOrCreateSupportConversation,
}));
vi.mock("../server/observability", () => ({ reportSilentFallback: vi.fn() }));

import { POST } from "../app/api/support/route";

function routeReq(body: unknown): Request {
  return new Request("https://app/api/support", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/support — terminal-frame handoff emit", () => {
  beforeEach(() => {
    routeH.getUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
    routeH.validateOrigin.mockReturnValue({ valid: true, origin: "https://app" });
    routeH.resolveOrCreateSupportConversation.mockResolvedValue("conv-support-1");
    routeH.getRuntimeFlag.mockResolvedValue(true);
  });

  test("(AC1) a deny-recorded turn emits support_handoff before the terminal frame, task = user's message", async () => {
    routeH.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        args.sendToClient("user-1", { type: "stream", content: "I can't edit files.", partial: false, leaderId: "cc_router" } as WSMessage);
        // Simulate the deny path recording an escalation mid-turn.
        recordSupportEscalation("conv-support-1", "skill");
        args.sendToClient("user-1", { type: "stream_end", leaderId: "cc_router" } as WSMessage);
      },
    );
    const res = await POST(routeReq({ message: "turn the prospects board into a full page" }));
    const sse = await res.text();
    expect(res.headers.get("Content-Type")).toContain("text/event-stream");
    const handoffIdx = sse.indexOf('"type":"support_handoff"');
    const endIdx = sse.indexOf('"type":"stream_end"');
    expect(handoffIdx).toBeGreaterThan(-1);
    expect(handoffIdx).toBeLessThan(endIdx);
    // The frame carries the RAW task (server-derived from the POST body);
    // URL-encoding is the client's render-time concern (`buildSupportHandoffMarkdown`).
    expect(sse).toContain('"task":"turn the prospects board into a full page"');
  });

  test("(AC6a) a turn with NO deny emits no handoff", async () => {
    routeH.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        args.sendToClient("user-1", { type: "stream", content: "answer", partial: false, leaderId: "cc_router" } as WSMessage);
        args.sendToClient("user-1", { type: "session_ended" } as WSMessage);
      },
    );
    const res = await POST(routeReq({ message: "how do I add a tag?" }));
    const sse = await res.text();
    expect(sse).not.toContain("support_handoff");
  });

  test("(AC6b) a stale flag from a prior zombie turn is cleared at stream open", async () => {
    // Zombie leak: flag recorded but this turn's dispatch never denies.
    recordSupportEscalation("conv-support-1", "bash");
    routeH.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        args.sendToClient("user-1", { type: "session_ended" } as WSMessage);
      },
    );
    const res = await POST(routeReq({ message: "innocent question" }));
    const sse = await res.text();
    expect(sse).not.toContain("support_handoff");
  });

  test("handoff task is server-derived from the POSTed message, not model-generated", async () => {
    routeH.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        recordSupportEscalation("conv-support-1", "bash");
        args.sendToClient("user-1", { type: "error", message: "turn failed" } as WSMessage);
      },
    );
    const res = await POST(routeReq({ message: "fix (my) board's layout" }));
    const sse = await res.text();
    const { messages } = parseSupportSseChunks(sse + "\n\n");
    const handoff = messages.find((m) => m.type === "support_handoff") as { task: string } | undefined;
    expect(handoff?.task).toBe("fix (my) board's layout");
    // error-terminated turn still emits the handoff, BEFORE the error frame.
    expect(sse.indexOf('"type":"support_handoff"')).toBeLessThan(sse.indexOf('"type":"error"'));
  });
});
