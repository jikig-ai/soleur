import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn(
    (name: string, description: string, schema: unknown, handler: Function) => ({
      name,
      description,
      schema,
      handler,
    }),
  ),
}));

const mocks = vi.hoisted(() => ({
  writeC4Diagram: vi.fn(),
}));

vi.mock("@/server/c4-writer", () => ({
  writeC4Diagram: mocks.writeC4Diagram,
}));

import {
  buildC4ConciergeTools,
  EDIT_C4_DIAGRAM_TOOL,
} from "@/server/c4-concierge-tools";

type ToolHandler = (args: Record<string, unknown>) => Promise<{
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
}>;

const opts = {
  userId: "user-1",
  installationId: 42,
  owner: "jikig-ai",
  repo: "soleur",
  workspacePath: "/ws/user-1",
};

function handler(): ToolHandler {
  const tools = buildC4ConciergeTools(opts) as unknown as Array<{
    name: string;
    handler: ToolHandler;
  }>;
  const t = tools.find((x) => x.name === EDIT_C4_DIAGRAM_TOOL);
  if (!t) throw new Error("edit_c4_diagram not registered");
  return t.handler;
}

beforeEach(() => mocks.writeC4Diagram.mockReset());

describe("buildC4ConciergeTools", () => {
  it("registers the edit_c4_diagram tool", () => {
    const tools = buildC4ConciergeTools(opts) as unknown as Array<{
      name: string;
    }>;
    expect(tools.map((t) => t.name)).toContain(EDIT_C4_DIAGRAM_TOOL);
  });

  it("tool description states the diagram re-renders, gated on `rerendered` (Layer 2)", () => {
    const tools = buildC4ConciergeTools(opts) as unknown as Array<{
      name: string;
      description: string;
    }>;
    const t = tools.find((x) => x.name === EDIT_C4_DIAGRAM_TOOL);
    expect(t).toBeTruthy();
    const desc = t!.description;
    // Layer 2: the diagram now re-renders; the model is told to key on `rerendered`.
    expect(desc).toContain("rerendered");
    expect(desc.toLowerCase()).toMatch(/re-render/);
    // The stale Layer-1 copy must be gone.
    expect(desc.toLowerCase()).not.toContain("out-of-band");
    expect(desc.toLowerCase()).not.toContain("cannot trigger");
  });

  it("propagates the writeC4Diagram `rerendered` flag in the tool response", async () => {
    mocks.writeC4Diagram.mockResolvedValue({
      ok: true,
      commitSha: "abc123",
      rerendered: true,
    });
    const res = await handler()({
      relativePath: "engineering/architecture/diagrams/model.c4",
      content: "model {}",
    });
    const payload = JSON.parse(res.content[0].text);
    expect(payload).toMatchObject({ ok: true, rerendered: true });
  });

  it("forwards relativePath + content and closes over the repo coords", async () => {
    mocks.writeC4Diagram.mockResolvedValue({ ok: true, commitSha: "abc123" });
    const res = await handler()({
      relativePath: "engineering/architecture/diagrams/model.c4",
      content: "specification {}",
    });
    // The agent supplies ONLY path + content; identity/repo are closed over.
    expect(mocks.writeC4Diagram).toHaveBeenCalledWith({
      userId: "user-1",
      installationId: 42,
      owner: "jikig-ai",
      repo: "soleur",
      workspacePath: "/ws/user-1",
      relativePath: "engineering/architecture/diagrams/model.c4",
      content: "specification {}",
    });
    const payload = JSON.parse(res.content[0].text);
    expect(payload).toMatchObject({ ok: true, commitSha: "abc123" });
    expect(res.isError).toBeUndefined();
  });

  it("surfaces an out-of-scope rejection as an error response", async () => {
    mocks.writeC4Diagram.mockResolvedValue({
      ok: false,
      status: 400,
      error: "Path is not a writable diagram source",
      code: "OUT_OF_SCOPE",
    });
    const res = await handler()({
      relativePath: "engineering/architecture/secrets.c4",
      content: "x",
    });
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("OUT_OF_SCOPE");
  });

  it("does not let the agent override owner/repo (no such tool inputs)", async () => {
    mocks.writeC4Diagram.mockResolvedValue({ ok: true, commitSha: null });
    await handler()({
      relativePath: "engineering/architecture/diagrams/model.c4",
      content: "x",
      // Attacker-style extra fields must be ignored.
      owner: "evil",
      repo: "pwned",
      installationId: 999,
    } as Record<string, unknown>);
    const call = mocks.writeC4Diagram.mock.calls[0][0];
    expect(call.owner).toBe("jikig-ai");
    expect(call.repo).toBe("soleur");
    expect(call.installationId).toBe(42);
  });

  it("AC9 — reaches writeC4Diagram with NO c4-edit consultation (Concierge stays the live writer)", async () => {
    // Behavioral: the tool handler writes with no feature-flag mock in the loop
    // — proving the Concierge edit path is not gated by c4-edit. (c4-edit OFF is
    // the prod state; the Concierge must keep writing.)
    mocks.writeC4Diagram.mockResolvedValue({ ok: true, commitSha: "abc123" });
    const res = await handler()({
      relativePath: "engineering/architecture/diagrams/model.c4",
      content: "model {}",
    });
    expect(mocks.writeC4Diagram).toHaveBeenCalledTimes(1);
    expect(res.isError).toBeUndefined();
  });

  it("AC9 — the Concierge tool module never references the c4-edit flag (structural independence)", async () => {
    const fs = await import("node:fs");
    const url = await import("node:url");
    const pathMod = await import("node:path");
    const here = pathMod.dirname(url.fileURLToPath(import.meta.url));
    const src = fs.readFileSync(
      pathMod.join(here, "../server/c4-concierge-tools.ts"),
      "utf8",
    );
    // Gating the Concierge write path on c4-edit would re-couple the two
    // surfaces. The module must not mention the edit flag in any form.
    expect(src).not.toContain("c4-edit");
    expect(src).not.toContain("C4_EDIT_FLAG");
    expect(src).not.toContain("FLAG_C4_EDIT");
  });
});
