// POST /api/support route handler (ADR-113, CTO Option D test #2). Dispatch +
// auth + conversation are mocked; asserts the route calls dispatchSoleurGo with
// persona:"support" and streams the injected sink's frames as SSE.

import { vi, describe, it, expect, beforeEach } from "vitest";
import type { WSMessage } from "@/lib/types";

const h = vi.hoisted(() => ({
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

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: h.getUser } })),
}));
vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: h.validateOrigin,
  rejectCsrf: () => new Response("csrf", { status: 403 }),
}));
vi.mock("@/lib/feature-flags/identity", () => ({ resolveIdentity: h.resolveIdentity }));
vi.mock("@/lib/feature-flags/server", () => ({ getRuntimeFlag: h.getRuntimeFlag }));
vi.mock("@/server/cc-dispatcher", () => ({ dispatchSoleurGo: h.dispatchSoleurGo }));
vi.mock("@/server/support-conversation", () => ({
  resolveOrCreateSupportConversation: h.resolveOrCreateSupportConversation,
}));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));

import { POST } from "@/app/api/support/route";

function req(body: unknown): Request {
  return new Request("https://app/api/support", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function readAll(res: Response): Promise<string> {
  const reader = res.body!.getReader();
  const dec = new TextDecoder();
  let out = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    out += dec.decode(value, { stream: true });
  }
  return out;
}

describe("POST /api/support", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    h.getUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
    h.validateOrigin.mockReturnValue({ valid: true, origin: "https://app" });
    h.resolveOrCreateSupportConversation.mockResolvedValue("conv-support-1");
    h.getRuntimeFlag.mockResolvedValue(true);
  });

  it("dispatches with persona:'support' and the resolved conversation, streaming the sink frames as SSE", async () => {
    h.dispatchSoleurGo.mockImplementation(async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
      args.sendToClient("user-1", { type: "stream", content: "hi", partial: true, leaderId: "cc_router" } as WSMessage);
      args.sendToClient("user-1", { type: "session_ended" } as WSMessage);
    });

    const res = await POST(req({ message: "how do I create a routine?" }));
    expect(res.headers.get("Content-Type")).toContain("text/event-stream");

    const args = h.dispatchSoleurGo.mock.calls[0][0];
    expect(args.persona).toBe("support");
    expect(args.conversationId).toBe("conv-support-1");
    expect(args.userId).toBe("user-1");
    expect(args.userMessage).toBe("how do I create a routine?");

    const sse = await readAll(res);
    expect(sse).toContain(`"type":"stream"`);
    expect(sse).toContain(`"content":"hi"`);
    expect(sse).toContain(`"type":"session_ended"`);
  });

  it("holds the SSE open for frames emitted AFTER dispatch resolves (background-consumer regression)", async () => {
    // The real runner consumes the SDK query on a fire-and-forget task, so
    // `dispatchSoleurGo` RESOLVES before any `stream` frame is emitted. The route
    // must close on a TERMINAL frame, not on the dispatch promise — otherwise it
    // closes the response before the first token and the client sees nothing.
    h.dispatchSoleurGo.mockImplementation(
      async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
        // Emit the reply LATER — after this promise has already resolved.
        setTimeout(() => {
          args.sendToClient("user-1", {
            type: "stream",
            content: "Open Routines from the sidebar.",
            partial: true,
            leaderId: "cc_router",
          } as WSMessage);
          args.sendToClient("user-1", { type: "stream_end", leaderId: "cc_router" } as WSMessage);
        }, 10);
        // resolves immediately, BEFORE the frames above
      },
    );

    const res = await POST(req({ message: "how do I create a routine?" }));
    const sse = await readAll(res);
    // The post-resolution frames survived because the route waited for stream_end.
    expect(sse).toContain("Open Routines from the sidebar.");
    expect(sse).toContain(`"type":"stream_end"`);
  });

  it("forwards newConversation:true as forceNew to the resolver", async () => {
    h.dispatchSoleurGo.mockImplementation(async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
      args.sendToClient("user-1", { type: "session_ended" } as WSMessage);
    });
    await POST(req({ message: "start over", newConversation: true }));
    expect(h.resolveOrCreateSupportConversation).toHaveBeenCalledWith("user-1", { forceNew: true });
  });

  it("omitted/false newConversation resolves with forceNew:false (reuse)", async () => {
    h.dispatchSoleurGo.mockImplementation(async (args: { sendToClient: (u: string, m: WSMessage) => boolean }) => {
      args.sendToClient("user-1", { type: "session_ended" } as WSMessage);
    });
    await POST(req({ message: "hello" }));
    expect(h.resolveOrCreateSupportConversation).toHaveBeenCalledWith("user-1", { forceNew: false });
  });

  it("404 (dark) when support-live is OFF — never invokes the Concierge", async () => {
    h.getRuntimeFlag.mockResolvedValue(false);
    const res = await POST(req({ message: "read your internal roadmap" }));
    expect(res.status).toBe(404);
    expect(h.getRuntimeFlag).toHaveBeenCalledWith("support-live", expect.anything());
    expect(h.dispatchSoleurGo).not.toHaveBeenCalled();
    expect(h.resolveOrCreateSupportConversation).not.toHaveBeenCalled();
  });

  it("401 when unauthenticated", async () => {
    h.getUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(req({ message: "x" }));
    expect(res.status).toBe(401);
    expect(h.dispatchSoleurGo).not.toHaveBeenCalled();
  });

  it("400 on empty message", async () => {
    const res = await POST(req({ message: "   " }));
    expect(res.status).toBe(400);
    expect(h.dispatchSoleurGo).not.toHaveBeenCalled();
  });

  it("503 when the support conversation cannot be created (honest degrade)", async () => {
    h.resolveOrCreateSupportConversation.mockRejectedValue(new Error("rls"));
    const res = await POST(req({ message: "x" }));
    expect(res.status).toBe(503);
    expect(h.dispatchSoleurGo).not.toHaveBeenCalled();
  });

  it("rejects a cross-origin (CSRF) request", async () => {
    h.validateOrigin.mockReturnValue({ valid: false, origin: "https://evil" });
    const res = await POST(req({ message: "x" }));
    expect(res.status).toBe(403);
    expect(h.dispatchSoleurGo).not.toHaveBeenCalled();
  });
});
