// Canonical unit tests for the shared prefill-guard helper. The
// cc-dispatcher and legacy agent-runner integration files assert only
// that the helper is invoked with the correct args; the semantic
// contract (positive-match polarity, three observability ops, probe
// failure pass-through, error sanitization) is pinned here.

import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockGetSessionMessages, mockWarnSilentFallback } = vi.hoisted(
  () => ({
    mockGetSessionMessages: vi.fn(),
    mockWarnSilentFallback: vi.fn(),
  }),
);

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  getSessionMessages: mockGetSessionMessages,
}));

vi.mock("@/server/observability", () => ({
  warnSilentFallback: mockWarnSilentFallback,
  reportSilentFallback: vi.fn(),
}));

import { applyPrefillGuard } from "@/server/agent-prefill-guard";

const WORKSPACE_PATH = "/tmp/cc-test-workspace";
const COMMON_ARGS = {
  workspacePath: WORKSPACE_PATH,
  userId: "user-1",
  conversationId: "conv-1",
} as const;

describe("applyPrefillGuard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("short-circuits when resumeSessionId is undefined (no probe, no warn)", async () => {
    const result = await applyPrefillGuard({
      ...COMMON_ARGS,
      resumeSessionId: undefined,
      feature: "cc-concierge",
    });

    expect(result.safeResumeSessionId).toBeUndefined();
    expect(mockGetSessionMessages).not.toHaveBeenCalled();
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  it("invokes getSessionMessages with { dir: workspacePath } (drift-guard)", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([
      { type: "user", uuid: "u1", session_id: "s", message: {}, parent_tool_use_id: null },
    ]);

    await applyPrefillGuard({
      ...COMMON_ARGS,
      resumeSessionId: "s",
      feature: "cc-concierge",
    });

    expect(mockGetSessionMessages).toHaveBeenCalledOnce();
    expect(mockGetSessionMessages).toHaveBeenCalledWith("s", {
      dir: WORKSPACE_PATH,
    });
  });

  it("preserves resume when persisted session ends with user message", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([
      { type: "user", uuid: "u1", session_id: "s", message: {}, parent_tool_use_id: null },
      { type: "assistant", uuid: "a1", session_id: "s", message: {}, parent_tool_use_id: null },
      { type: "user", uuid: "u2", session_id: "s", message: {}, parent_tool_use_id: null },
    ]);

    const result = await applyPrefillGuard({
      ...COMMON_ARGS,
      resumeSessionId: "s",
      feature: "cc-concierge",
    });

    expect(result.safeResumeSessionId).toBe("s");
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  it("drops resume and emits prefill-guard warn when last message is assistant", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([
      { type: "user", uuid: "u1", session_id: "s", message: {}, parent_tool_use_id: null },
      { type: "assistant", uuid: "a1", session_id: "s", message: {}, parent_tool_use_id: null },
    ]);

    const result = await applyPrefillGuard({
      ...COMMON_ARGS,
      resumeSessionId: "s",
      feature: "cc-concierge",
      leaderId: "cc_router",
    });

    expect(result.safeResumeSessionId).toBeUndefined();
    expect(mockWarnSilentFallback).toHaveBeenCalledOnce();
    const [errArg, optsArg] = mockWarnSilentFallback.mock.calls[0];
    expect(errArg).toBeNull();
    expect(optsArg.feature).toBe("cc-concierge");
    expect(optsArg.op).toBe("prefill-guard");
    expect(optsArg.extra).toMatchObject({
      userId: "user-1",
      conversationId: "conv-1",
      resumeSessionId: "s",
      workspacePath: WORKSPACE_PATH,
      leaderId: "cc_router",
      lastType: "assistant",
      historyLength: 2,
    });
  });

  it("preserves resume and emits prefill-guard-empty-history when history is empty", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([]);

    const result = await applyPrefillGuard({
      ...COMMON_ARGS,
      resumeSessionId: "s",
      feature: "agent-runner",
      leaderId: "cpo",
    });

    expect(result.safeResumeSessionId).toBe("s");
    expect(mockWarnSilentFallback).toHaveBeenCalledOnce();
    expect(mockWarnSilentFallback.mock.calls[0][1].op).toBe(
      "prefill-guard-empty-history",
    );
    expect(mockWarnSilentFallback.mock.calls[0][1].feature).toBe(
      "agent-runner",
    );
  });

  it("preserves resume and emits sanitized probe-failed warn when getSessionMessages throws", async () => {
    const probeErr = Object.assign(
      new Error(
        "ENOENT: no such file or directory, open '/home/jean/.claude/projects/-encoded-cwd/abc.jsonl'",
      ),
      { code: "ENOENT" },
    );
    mockGetSessionMessages.mockRejectedValueOnce(probeErr);

    const result = await applyPrefillGuard({
      ...COMMON_ARGS,
      resumeSessionId: "s",
      feature: "cc-concierge",
    });

    expect(result.safeResumeSessionId).toBe("s");
    expect(mockWarnSilentFallback).toHaveBeenCalledOnce();
    expect(mockWarnSilentFallback.mock.calls[0][1].op).toBe(
      "prefill-guard-probe-failed",
    );

    const forwardedErr = mockWarnSilentFallback.mock.calls[0][0] as Error & {
      code?: string;
    };
    expect(forwardedErr).toBeInstanceOf(Error);
    expect(forwardedErr.message).not.toContain(
      "/home/jean/.claude/projects/-encoded-cwd/abc.jsonl",
    );
    expect(forwardedErr.message).toContain("ENOENT");
    // System-error code preserved for Sentry fingerprinting.
    expect(forwardedErr.code).toBe("ENOENT");
  });

  it("forwards the feature tag verbatim so cc-concierge and agent-runner are distinguishable in Sentry", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([
      { type: "assistant", uuid: "a1", session_id: "s", message: {}, parent_tool_use_id: null },
    ]);

    await applyPrefillGuard({
      ...COMMON_ARGS,
      resumeSessionId: "s",
      feature: "agent-runner",
      leaderId: "cmo",
    });

    expect(mockWarnSilentFallback.mock.calls[0][1].feature).toBe(
      "agent-runner",
    );
  });

  // -------------------------------------------------------------------------
  // #3269 — context-reset notice + reason discriminator. The helper now
  // returns a single-turn `contextResetNotice` (system-prompt append) and a
  // `reason` discriminator the dispatcher uses to emit the WS event.
  // -------------------------------------------------------------------------

  describe("contextResetNotice + reason (#3269)", () => {
    it("returns generic notice + reason 'prefill-guard' when last message is plain assistant (content: string)", async () => {
      mockGetSessionMessages.mockResolvedValueOnce([
        { type: "user", uuid: "u1", session_id: "s", message: {}, parent_tool_use_id: null },
        {
          type: "assistant",
          uuid: "a1",
          session_id: "s",
          message: { content: "all done" },
          parent_tool_use_id: null,
        },
      ]);

      const result = await applyPrefillGuard({
        ...COMMON_ARGS,
        resumeSessionId: "s",
        feature: "cc-concierge",
      });

      expect(result.safeResumeSessionId).toBeUndefined();
      expect(result.contextResetNotice).toBe(
        "Prior conversation context was reset. Treat the user's next message as standalone; ask for clarification if it references earlier turns.",
      );
      expect(result.reason).toBe("prefill-guard");
    });

    it("returns tool-aware notice + reason 'tool_use_orphan' when last assistant message has a tool_use content block", async () => {
      mockGetSessionMessages.mockResolvedValueOnce([
        { type: "user", uuid: "u1", session_id: "s", message: {}, parent_tool_use_id: null },
        {
          type: "assistant",
          uuid: "a1",
          session_id: "s",
          message: {
            content: [
              { type: "text", text: "let me run a command" },
              { type: "tool_use", id: "tu1", name: "Bash", input: { command: "ls" } },
            ],
          },
          parent_tool_use_id: null,
        },
      ]);

      const result = await applyPrefillGuard({
        ...COMMON_ARGS,
        resumeSessionId: "s",
        feature: "cc-concierge",
      });

      expect(result.safeResumeSessionId).toBeUndefined();
      expect(result.reason).toBe("tool_use_orphan");
      expect(result.contextResetNotice).toBe(
        "Prior conversation context was reset. The previous turn proposed a tool action you no longer have context on. Do NOT execute any action without explicit re-confirmation by name — ask the user to restate which action they want to run.",
      );
    });

    it("returns generic notice (not tool-aware) when last assistant message has content: string (tool_use never appears in string form)", async () => {
      mockGetSessionMessages.mockResolvedValueOnce([
        {
          type: "assistant",
          uuid: "a1",
          session_id: "s",
          message: { content: "type: tool_use is just text here" },
          parent_tool_use_id: null,
        },
      ]);

      const result = await applyPrefillGuard({
        ...COMMON_ARGS,
        resumeSessionId: "s",
        feature: "cc-concierge",
      });

      expect(result.reason).toBe("prefill-guard");
      expect(result.contextResetNotice).toContain(
        "Treat the user's next message as standalone",
      );
      expect(result.contextResetNotice).not.toContain("tool action");
    });

    it("returns generic notice (no crash) when message is null, undefined, or non-object", async () => {
      const shapes = [
        null,
        undefined,
        "not-an-object",
        42,
        { /* no content key */ },
        { content: { type: "tool_use" } /* not array, not string */ },
        { content: [{ type: "text", text: "hi" }, "not-an-object", null] },
      ];

      for (const message of shapes) {
        mockGetSessionMessages.mockResolvedValueOnce([
          {
            type: "assistant",
            uuid: "a1",
            session_id: "s",
            message,
            parent_tool_use_id: null,
          },
        ]);

        const result = await applyPrefillGuard({
          ...COMMON_ARGS,
          resumeSessionId: "s",
          feature: "cc-concierge",
        });

        expect(result.safeResumeSessionId).toBeUndefined();
        expect(result.reason).toBe("prefill-guard");
        expect(result.contextResetNotice).toContain(
          "Treat the user's next message as standalone",
        );
      }
    });

    it("returns contextResetNotice undefined and reason undefined on cold start, user-final, empty history, probe failure", async () => {
      // Cold start (no resumeSessionId)
      let result = await applyPrefillGuard({
        ...COMMON_ARGS,
        resumeSessionId: undefined,
        feature: "cc-concierge",
      });
      expect(result.contextResetNotice).toBeUndefined();
      expect(result.reason).toBeUndefined();

      // User-final
      mockGetSessionMessages.mockResolvedValueOnce([
        { type: "user", uuid: "u1", session_id: "s", message: {}, parent_tool_use_id: null },
        { type: "assistant", uuid: "a1", session_id: "s", message: {}, parent_tool_use_id: null },
        { type: "user", uuid: "u2", session_id: "s", message: {}, parent_tool_use_id: null },
      ]);
      result = await applyPrefillGuard({
        ...COMMON_ARGS,
        resumeSessionId: "s",
        feature: "cc-concierge",
      });
      expect(result.contextResetNotice).toBeUndefined();
      expect(result.reason).toBeUndefined();

      // Empty history
      mockGetSessionMessages.mockResolvedValueOnce([]);
      result = await applyPrefillGuard({
        ...COMMON_ARGS,
        resumeSessionId: "s",
        feature: "cc-concierge",
      });
      expect(result.contextResetNotice).toBeUndefined();
      expect(result.reason).toBeUndefined();

      // Probe failure
      mockGetSessionMessages.mockRejectedValueOnce(new Error("ENOENT"));
      result = await applyPrefillGuard({
        ...COMMON_ARGS,
        resumeSessionId: "s",
        feature: "cc-concierge",
      });
      expect(result.contextResetNotice).toBeUndefined();
      expect(result.reason).toBeUndefined();
    });
  });
});
