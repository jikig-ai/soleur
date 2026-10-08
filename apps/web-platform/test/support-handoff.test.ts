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

beforeEach(() => {
  vi.clearAllMocks();
  clearSupportEscalation("conv-1");
  clearSupportEscalation("conv-support-1");
});

describe("support escalation registry", () => {
  test("record → consume returns the source, consume-on-read empties it", () => {
    recordSupportEscalation("conv-1", "skill");
    expect(consumeSupportEscalation("conv-1")?.source).toBe("skill");
    expect(consumeSupportEscalation("conv-1")).toBeNull();
  });

  test("clear drops a live flag (returns true) and reports false when empty", () => {
    expect(clearSupportEscalation("conv-1")).toBe(false);
    recordSupportEscalation("conv-1", "bash");
    expect(clearSupportEscalation("conv-1")).toBe(true);
    expect(consumeSupportEscalation("conv-1")).toBeNull();
  });

  test("FIFO cap evicts the OLDEST key and retains the newest", () => {
    for (let i = 0; i < 1001; i++) {
      recordSupportEscalation(`conv-cap-${i}`, "skill");
    }
    expect(consumeSupportEscalation("conv-cap-0")).toBeNull(); // evicted
    expect(consumeSupportEscalation("conv-cap-1000")?.source).toBe("skill"); // newest kept
    for (let i = 1; i < 1001; i++) clearSupportEscalation(`conv-cap-${i}`);
  });

  test("re-recording refreshes insertion order (oldest is not the newest)", () => {
    recordSupportEscalation("conv-cap-a", "skill");
    for (let i = 0; i < 999; i++) recordSupportEscalation(`conv-rr-${i}`, "skill");
    recordSupportEscalation("conv-cap-a", "bash"); // re-record → newest
    recordSupportEscalation("conv-rr-overflow", "skill"); // evicts oldest
    // conv-cap-a was refreshed, so conv-rr-0 (the true oldest) is evicted.
    expect(consumeSupportEscalation("conv-rr-0")).toBeNull();
    expect(consumeSupportEscalation("conv-cap-a")?.source).toBe("bash");
    clearSupportEscalation("conv-rr-overflow");
    for (let i = 1; i < 999; i++) clearSupportEscalation(`conv-rr-${i}`);
  });

  // #9556 — the registry value is a record, not a bare source: repoConnected
  // rides the deny → emit bridge to the `support_handoff` frame (FR-1).
  test("record shape: source + repoConnected tri-state", () => {
    recordSupportEscalation("conv-1", "skill", false);
    expect(consumeSupportEscalation("conv-1")).toEqual({
      source: "skill",
      repoConnected: false,
    });
    recordSupportEscalation("conv-1", "bash", true);
    expect(consumeSupportEscalation("conv-1")).toEqual({
      source: "bash",
      repoConnected: true,
    });
    // Dep-unwired record (legacy runner / pre-resolution deny): field absent.
    recordSupportEscalation("conv-1", "tool");
    const rec = consumeSupportEscalation("conv-1");
    expect(rec?.source).toBe("tool");
    expect(rec?.repoConnected).toBeUndefined();
  });
});

describe("support persona — deny → escalation record", () => {
  test("(a) non-allowlisted Skill records escalation + names 'Ask an agent'", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    const r = assertDeny(await canUse("Skill", { skill: "soleur:one-shot" }, opts()));
    expect(consumeSupportEscalation("conv-1")?.source).toBe("skill");
    if (r.behavior === "deny") {
      expect(r.message).toMatch(/Ask an agent/);
    }
  });

  test("(b) non-safe Bash denies with zero frames on the WS sink + records 'bash'", async () => {
    const deps = buildDeps();
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    const r = assertDeny(await canUse("Bash", { command: "git checkout -b x" }, opts()));
    // "No emit, ever" — stronger than a frame-type allowlist.
    expect(deps.sendToClient).not.toHaveBeenCalled();
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(consumeSupportEscalation("conv-1")?.source).toBe("bash");
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
    expect(deps.sendToClient).not.toHaveBeenCalled();
    expect(consumeSupportEscalation("conv-1")?.source).toBe("bash");
  });

  test("(b2b) owner + un-acked + autonomous OFF still denies (opt-out hold arm)", async () => {
    // The existing-workspace opt-out hold emits `autonomous_disclosure` over
    // the WS sink when !bashAutonomous && unAcked && isOwner — the short-
    // circuit must precede that arm too.
    const deps = buildDeps({
      bashAutonomous: false,
      isOwner: true,
      autonomousAckAt: null,
    });
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    assertDeny(await canUse("Bash", { command: "git checkout -b x" }, opts()));
    expect(deps.sendToClient).not.toHaveBeenCalled();
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(consumeSupportEscalation("conv-1")?.source).toBe("bash");
  });

  test("(b3) blocklisted command on support records the escalation + handoff copy", async () => {
    const deps = buildDeps();
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    const r = assertDeny(await canUse("Bash", { command: "sudo ls" }, opts()));
    expect(consumeSupportEscalation("conv-1")?.source).toBe("bash");
    if (r.behavior === "deny") {
      expect(r.message).toMatch(/Ask an agent/);
    }
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

  test("safe Bash on support still auto-allows (kb-search is tool-only, unaffected)", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertAllow(await canUse("Bash", { command: "git status" }, opts()));
    expect(consumeSupportEscalation("conv-1")).toBeNull();
  });

  // #9556 / FR-2 — the closure-local `deny()` wrapper stamps deps.repoConnected
  // onto every support deny path's escalation record (one injection point).
  test("deps.repoConnected === false rides the deny → record", async () => {
    const deps = buildDeps({ repoConnected: false });
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    assertDeny(await canUse("Skill", { skill: "soleur:one-shot" }, opts()));
    expect(consumeSupportEscalation("conv-1")).toEqual({
      source: "skill",
      repoConnected: false,
    });
  });

  test("deps.repoConnected === true records true; unwired deps records the field absent", async () => {
    const canUse = createCanUseTool(
      buildContext({ persona: "support", deps: buildDeps({ repoConnected: true }) }),
    );
    assertDeny(await canUse("Skill", { skill: "soleur:one-shot" }, opts()));
    expect(consumeSupportEscalation("conv-1")).toEqual({
      source: "skill",
      repoConnected: true,
    });

    const canUse2 = createCanUseTool(buildContext({ persona: "support" }));
    assertDeny(await canUse2("Skill", { skill: "soleur:one-shot" }, opts()));
    const rec = consumeSupportEscalation("conv-1");
    expect(rec?.source).toBe("skill");
    expect(rec?.repoConnected).toBeUndefined();
  });
});

describe("support persona — uncovered-path belts (panel enumeration)", () => {
  test("write-class file tool (Edit) denies + records 'tool' at the belt, not deny-default", async () => {
    // isFileTool must report true or the call lands on deny-default instead of
    // the write-class belt — and "tool" alone wouldn't discriminate (deny-
    // default records the same source). The file-path input proves the call
    // reached the file-tool branch.
    mockIsFileTool.mockReturnValue(true);
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertDeny(await canUse("Edit", { file_path: "/tmp/ws/f.ts", old_string: "a", new_string: "b" }, opts()));
    expect(consumeSupportEscalation("conv-1")?.source).toBe("tool");
    mockIsFileTool.mockReturnValue(false);
  });

  test("read-class file tool (Read) still flows through containment", async () => {
    mockIsFileTool.mockReturnValue(true);
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertAllow(await canUse("Read", { file_path: "/tmp/ws/f.ts" }, opts()));
    expect(consumeSupportEscalation("conv-1")).toBeNull();
    mockIsFileTool.mockReturnValue(false);
  });

  test("file tool outside workspace on support records the deny", async () => {
    // vi.clearAllMocks does NOT reset mockReturnValue implementations —
    // restore all three after the test or the impls leak into later tests.
    mockIsFileTool.mockReturnValue(true);
    const { extractToolPath } = await import("../server/tool-path-checker");
    (extractToolPath as ReturnType<typeof vi.fn>).mockReturnValue("/outside/f.ts");
    const { isPathInWorkspace } = await import("../server/sandbox");
    (isPathInWorkspace as ReturnType<typeof vi.fn>).mockReturnValue(false);
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertDeny(await canUse("Read", { file_path: "/outside/f.ts" }, opts()));
    expect(consumeSupportEscalation("conv-1")?.source).toBe("tool");
    mockIsFileTool.mockReturnValue(false);
    (extractToolPath as ReturnType<typeof vi.fn>).mockReturnValue(null);
    (isPathInWorkspace as ReturnType<typeof vi.fn>).mockReturnValue(true);
  });

  test("Agent on support denies + records 'tool' (engineering fan-out)", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertDeny(await canUse("Agent", { prompt: "fix it" }, opts()));
    expect(consumeSupportEscalation("conv-1")?.source).toBe("tool");
  });

  test("platform tool on support denies + records 'tool' (belt for future entries)", async () => {
    const canUse = createCanUseTool(
      buildContext({ persona: "support", platformToolNames: ["mcp__soleur_platform__x"] }),
    );
    assertDeny(await canUse("mcp__soleur_platform__x", {}, opts()));
    expect(consumeSupportEscalation("conv-1")?.source).toBe("tool");
  });

  test("deny-by-default unknown tool on support records 'tool'", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertDeny(await canUse("MultiEdit", { file_path: "/tmp/ws/f" }, opts()));
    expect(consumeSupportEscalation("conv-1")?.source).toBe("tool");
  });

  test("TodoWrite denies on support WITHOUT recording (UX signal, not engineering)", async () => {
    const deps = buildDeps();
    const canUse = createCanUseTool(buildContext({ persona: "support", deps }));
    assertDeny(await canUse("TodoWrite", { todos: [] }, opts()));
    expect(deps.sendToClient).not.toHaveBeenCalled();
    expect(consumeSupportEscalation("conv-1")).toBeNull();
  });

  test("ExitPlanMode denies on support WITHOUT recording", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertDeny(await canUse("ExitPlanMode", {}, opts()));
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

  test("covers every terminal type (literal pin — a removed member can't evade)", () => {
    expect([...SUPPORT_TERMINAL_FRAME_TYPES].sort()).toEqual([
      "error",
      "session_ended",
      "stream_end",
    ]);
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

  // #9556 / FR-5 (AC2) — exact copy pins for all three repoConnected arms.
  test("buildSupportHandoffMarkdown tri-state: false → connect-repo copy", () => {
    // A repo-less user's `?msg=` deep link dead-ends on the Command Center's
    // repo gate — degrade honestly to the canonical connect flow instead.
    expect(buildSupportHandoffMarkdown("fix it", false)).toBe(
      "[Connect a repository to hand this task to an agent →](</connect-repo>)",
    );
  });

  test("buildSupportHandoffMarkdown tri-state: true → clean link, caveat drops", () => {
    expect(buildSupportHandoffMarkdown("fix it", true)).toBe(
      "[Ask an agent to do this →](</dashboard/chat/new?msg=fix%20it>)",
    );
  });

  test("buildSupportHandoffMarkdown tri-state: undefined → legacy copy byte-identical", () => {
    // Dep-unwired contexts (legacy runner, dep-less denies) keep today's copy.
    expect(buildSupportHandoffMarkdown("fix it")).toBe(
      "[Ask an agent to do this (needs a connected repo) →](</dashboard/chat/new?msg=fix%20it>)",
    );
  });

  test("tri-state still percent-encodes the task on the true/undefined arms", () => {
    // `false` carries no task text (connect flow has no ?msg= consumer);
    // the encoding contract is unchanged where the link carries it.
    expect(buildSupportHandoffMarkdown("a (b)'s", true)).toBe(
      "[Ask an agent to do this →](</dashboard/chat/new?msg=a%20%28b%29%27s>)",
    );
    expect(buildSupportHandoffMarkdown("a (b)'s")).toContain(
      "?msg=a%20%28b%29%27s",
    );
  });

  test("truncateSupportHandoffTask is code-point aware (no lone surrogate)", () => {
    const emoji = "🙂".repeat(600);
    // Odd code-unit boundary: a code-unit `slice(0, 501)` mutant lands INSIDE
    // a surrogate pair (2 units each, so index 500 is a lone high surrogate)
    // and would throw URIError — the fixture actually discriminates.
    const t = truncateSupportHandoffTask(emoji, 501);
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
vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  // The mock is file-scoped (vi.mock hoists): permission-callback.ts imports
  // `warnSilentFallback` from this same module — omitting it strips the fn
  // for every test above too.
  warnSilentFallback: vi.fn(),
}));

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

  // #9556 / AC1 — deps.repoConnected rides the REAL deny path (createCanUseTool
  // → deny() wrapper → registry) into the emitted frame; only the dispatch is
  // mocked, so this proves the whole deps → record → consume → emit join.
  test("a deny recorded with deps.repoConnected === false emits repoConnected:false", async () => {
    routeH.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        const canUse = createCanUseTool(
          buildContext({
            persona: "support",
            conversationId: "conv-support-1",
            deps: buildDeps({ repoConnected: false }),
          }),
        );
        await canUse("Skill", { skill: "soleur:one-shot" }, opts());
        args.sendToClient("user-1", { type: "stream_end", leaderId: "cc_router" } as WSMessage);
      },
    );
    const res = await POST(routeReq({ message: "build the prospects board page" }));
    const sse = await res.text();
    const { messages } = parseSupportSseChunks(sse + "\n\n");
    const handoff = messages.find((m) => m.type === "support_handoff") as
      | { repoConnected?: boolean }
      | undefined;
    expect(handoff?.repoConnected).toBe(false);
    // Still emitted BEFORE the terminal frame.
    expect(sse.indexOf('"type":"support_handoff"')).toBeGreaterThan(-1);
    expect(sse.indexOf('"type":"support_handoff"')).toBeLessThan(
      sse.indexOf('"type":"stream_end"'),
    );
  });

  test("a deny recorded with repoConnected:true emits repoConnected:true", async () => {
    routeH.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        recordSupportEscalation("conv-support-1", "bash", true);
        args.sendToClient("user-1", { type: "stream_end", leaderId: "cc_router" } as WSMessage);
      },
    );
    const res = await POST(routeReq({ message: "wire up the webhook" }));
    const sse = await res.text();
    const { messages } = parseSupportSseChunks(sse + "\n\n");
    const handoff = messages.find((m) => m.type === "support_handoff") as
      | { repoConnected?: boolean }
      | undefined;
    expect(handoff?.repoConnected).toBe(true);
  });

  test("a dep-unwired record emits NO repoConnected key (additive-safe absence)", async () => {
    routeH.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        recordSupportEscalation("conv-support-1", "bash");
        args.sendToClient("user-1", { type: "stream_end", leaderId: "cc_router" } as WSMessage);
      },
    );
    const res = await POST(routeReq({ message: "refactor the thing" }));
    const sse = await res.text();
    const { messages } = parseSupportSseChunks(sse + "\n\n");
    const handoff = messages.find((m) => m.type === "support_handoff") as
      | { repoConnected?: boolean }
      | undefined;
    expect(handoff).toBeDefined();
    expect(handoff && "repoConnected" in handoff).toBe(false);
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

  test("a second POST on the in-flight conversation returns 409 (busy guard)", async () => {
    let send!: (u: string, m: WSMessage) => boolean;
    routeH.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        send = args.sendToClient;
      },
    );
    const res1 = await POST(routeReq({ message: "long help question" }));
    expect(res1.status).toBe(200);
    // Turn 1 never emits a terminal frame → still in-flight.
    const res2 = await POST(routeReq({ message: "concurrent double-send" }));
    expect(res2.status).toBe(409);
    // Release turn 1 so the busy flag clears for subsequent tests.
    send("user-1", { type: "stream_end", leaderId: "cc_router" } as WSMessage);
    await res1.text();
  });
});
