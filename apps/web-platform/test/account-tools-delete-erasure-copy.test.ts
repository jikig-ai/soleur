import { describe, test, expect, vi, beforeEach } from "vitest";

// #8211 / #9066 follow-up (CLO recommendation 2026-11-02): the agent tool must not report a
// completed erasure when deleteAccount() says the repository removal is still owed (ledger row,
// retried by the re-drive cron). It only READS result.gitDataErasurePending.

type Handler = (input: Record<string, unknown>) => Promise<{ content: { text: string }[]; isError?: true }>;
const captured: { name: string; description: string; handler: Handler }[] = [];
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: (name: string, description: string, _schema: unknown, handler: Handler) => {
    const t = { name, description, handler };
    captured.push(t);
    return t;
  },
}));
const mockDeleteAccount = vi.fn();
vi.mock("../server/account-delete", () => ({ deleteAccount: (...a: unknown[]) => mockDeleteAccount(...a) }));
vi.mock("../server/dsar-export", () => ({ enqueueExport: vi.fn() }));

import { buildAccountTools } from "../server/account-tools";

const EMAIL = "t@example.test";
const INPUT = { ack: "DELETE MY ACCOUNT", confirmEmail: EMAIL };

function deleteTool() {
  captured.length = 0;
  buildAccountTools({ userId: "u1", userEmail: EMAIL, sessionId: "s1" });
  const t = captured.find((c) => c.name === "account_delete_initiate");
  if (!t) throw new Error("account_delete_initiate not registered");
  return t;
}
async function run(result: unknown) {
  mockDeleteAccount.mockResolvedValue(result);
  const res = await deleteTool().handler(INPUT);
  return { res, body: JSON.parse(res.content[0].text) as Record<string, unknown> };
}

describe("account_delete_initiate erasure-pending copy", () => {
  beforeEach(() => vi.clearAllMocks());

  test("plain success keeps the plain message and no pending flag", async () => {
    const { res, body } = await run({ success: true });
    expect(res.isError).toBeUndefined();
    expect(body).toEqual({ success: true, message: "Account deletion cascade complete." });
  });

  test("gitDataErasurePending: true returns the qualified message and the flag", async () => {
    const { res, body } = await run({ success: true, gitDataErasurePending: true });
    expect(res.isError).toBeUndefined();
    expect(body.success).toBe(true);
    expect(body.gitDataErasurePending).toBe(true);
    const msg = String(body.message);
    expect(msg).not.toBe("Account deletion cascade complete.");
    expect(msg).toMatch(/could not confirm/i);
    expect(msg).toMatch(/try again until/i);
    expect(msg).toMatch(/workspace identifier/i);
  });

  test("pending message never claims the repository copy is erased/deleted/removed, nor names lock or cursor residue", async () => {
    const { body } = await run({ success: true, gitDataErasurePending: true });
    const msg = String(body.message);
    expect(msg).not.toMatch(/cascade complete/i);
    expect(msg).not.toMatch(/\b(?:repository|repo)\b[^.]*\b(?:has been|was|is) (?:erased|deleted|purged|wiped|removed)\b/i);
    expect(msg).not.toMatch(/\.gc-cursor|\.init\.lock|lock file|purge/i);
  });

  test("failure path is unchanged", async () => {
    mockDeleteAccount.mockResolvedValue({ success: false, error: "boom" });
    const res = await deleteTool().handler(INPUT);
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text)).toEqual({ error: "delete_failed", message: "boom" });
  });

  test("description no longer promises unqualified deletion of workspace files and documents the flag", () => {
    const d = deleteTool().description;
    expect(d).toContain("gitDataErasurePending");
    expect(d).toMatch(/retried automatically until/i);
    expect(d).not.toMatch(/deletes all account data/i);
    expect(d).toMatch(/not (?:tell|say|claim)[^.]*(?:erased|removed|deleted)/i);
  });
});
