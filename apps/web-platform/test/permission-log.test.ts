/**
 * Permission-layer debug log flag (#2336).
 *
 * `SOLEUR_DEBUG_PERMISSION_LAYER=1` emits a structured `log.debug` per
 * allow/deny decision so an operator can bisect which chain layer
 * admitted a tool invocation. Flag unset → zero emissions.
 */
import { vi, describe, test, expect, beforeEach, afterEach } from "vitest";

const { mockDebug } = vi.hoisted(() => ({
  mockDebug: vi.fn(),
}));

vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    debug: mockDebug,
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

import { logPermissionDecision } from "../server/permission-log";

describe("logPermissionDecision (#2336)", () => {
  let originalFlag: string | undefined;

  beforeEach(() => {
    vi.clearAllMocks();
    originalFlag = process.env.SOLEUR_DEBUG_PERMISSION_LAYER;
  });

  afterEach(() => {
    if (originalFlag === undefined) {
      delete process.env.SOLEUR_DEBUG_PERMISSION_LAYER;
    } else {
      process.env.SOLEUR_DEBUG_PERMISSION_LAYER = originalFlag;
    }
  });

  test("flag unset → no debug emission", () => {
    delete process.env.SOLEUR_DEBUG_PERMISSION_LAYER;
    logPermissionDecision("canUseTool-agent", "Agent", "allow");
    expect(mockDebug).not.toHaveBeenCalled();
  });

  test("flag set to anything other than '1' → no debug emission", () => {
    process.env.SOLEUR_DEBUG_PERMISSION_LAYER = "true";
    logPermissionDecision("canUseTool-agent", "Agent", "allow");
    expect(mockDebug).not.toHaveBeenCalled();
  });

  test("flag='1' → one debug emission per call with structured payload", () => {
    process.env.SOLEUR_DEBUG_PERMISSION_LAYER = "1";
    logPermissionDecision("canUseTool-agent", "Agent", "allow");
    expect(mockDebug).toHaveBeenCalledOnce();
    const [payload, message] = mockDebug.mock.calls[0];
    expect(payload).toEqual({
      sec: true,
      layer: "canUseTool-agent",
      tool: "Agent",
      decision: "allow",
      reason: undefined,
    });
    expect(message).toBe("permission-decision");
  });

  test("flag='1' → reason field captured on deny", () => {
    process.env.SOLEUR_DEBUG_PERMISSION_LAYER = "1";
    logPermissionDecision(
      "canUseTool-file-tool",
      "Write",
      "deny",
      "outside workspace",
    );
    const [payload] = mockDebug.mock.calls[0];
    expect(payload).toMatchObject({
      sec: true,
      layer: "canUseTool-file-tool",
      tool: "Write",
      decision: "deny",
      reason: "outside workspace",
    });
  });

  test("flag='1' → multiple invocations emit independently", () => {
    process.env.SOLEUR_DEBUG_PERMISSION_LAYER = "1";
    logPermissionDecision("sandbox-hook", "Read", "allow");
    logPermissionDecision("canUseTool-platform-gated", "mcp__x", "deny", "rejected");
    expect(mockDebug).toHaveBeenCalledTimes(2);
  });
});
