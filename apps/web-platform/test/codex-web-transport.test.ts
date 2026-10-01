import { describe, expect, it } from "vitest";
import { createCodexWebTransport } from "@/server/codex-web-transport";

describe("Codex Web transport", () => {
  it("composes the approved launcher with lifecycle and neutral adapter methods", () => {
    const transport = createCodexWebTransport({
      launcher: { spawn: async () => { throw new Error("not started in this composition test"); } },
      nextRequestId: () => "request-1",
    });

    expect(transport.start).toBeTypeOf("function");
    expect(transport.continue).toBeTypeOf("function");
    expect(transport.cancel).toBeTypeOf("function");
    expect(transport.reconcile).toBeTypeOf("function");
    expect(transport.resumeFromCursor).toBeTypeOf("function");
    expect(transport.respondToApproval).toBeTypeOf("function");
    expect(transport.erase).toBeTypeOf("function");
    expect(transport.dispose).toBeTypeOf("function");
  });
});
