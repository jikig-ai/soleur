import { describe, test, expect, vi, beforeEach } from "vitest";

// #8211 / #9066 follow-up (copy derived from the merged Privacy Policy, best effort): the agent tool must not report a
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
import {
  ERASURE_COMPLETE_TOOL_MESSAGE,
  ERASURE_PENDING_AGENT_INSTRUCTION,
  ERASURE_PENDING_TOOL_MESSAGE,
  PRIVACY_POLICY_CITATION,
} from "../lib/legal/account-deletion-copy";

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

  test("plain success returns the shared complete message and no pending flag or instruction", async () => {
    const { res, body } = await run({ success: true });
    expect(res.isError).toBeUndefined();
    expect(body).toEqual({ success: true, message: ERASURE_COMPLETE_TOOL_MESSAGE });
  });

  test("gitDataErasurePending: true returns the shared message, the flag and a SEPARATE agentInstruction", async () => {
    const { res, body } = await run({ success: true, gitDataErasurePending: true });
    expect(res.isError).toBeUndefined();
    expect(body.success).toBe(true);
    expect(body.gitDataErasurePending).toBe(true);
    expect(body.message).toBe(ERASURE_PENDING_TOOL_MESSAGE);
    expect(body.agentInstruction).toBe(ERASURE_PENDING_AGENT_INSTRUCTION);
    // the instruction is not inside the user-facing message
    expect(String(body.message)).not.toContain(String(body.agentInstruction));
    expect(String(body.message)).not.toMatch(/relay/i);
    expect(String(body.message)).toContain(PRIVACY_POLICY_CITATION);
  });

  test("golden strings: the legal copy changes only with a reviewed diff here", () => {
    expect(ERASURE_PENDING_TOOL_MESSAGE).toBe(
      "Your account is deleted, but we cannot yet confirm the repository copy is removed. " +
        "The server that holds the repository copy of your workspace has not confirmed its removal. " +
        "If the server that holds your repository copy does not confirm its removal, we try to keep " +
        "a record of your workspace ID so that we can ask again until it confirms. The record is " +
        "best effort, so this is not a guarantee of removal. " +
        "See Privacy Policy, \u201cPending-erasure record after account deletion\u201d.",
    );
    expect(ERASURE_PENDING_AGENT_INSTRUCTION).toBe(
      "Relay the message to the user with its qualification intact. Do not tell the user the " +
        "repository copy has been, or will certainly be, erased or removed.",
    );
    expect(ERASURE_COMPLETE_TOOL_MESSAGE).toBe(
      "Your account and conversations have been deleted from our application, and no repository " +
        "removal is outstanding.",
    );
  });

  test("pending message is a closed set: only the one allowed negated phrase, no residue talk, no guarantee", () => {
    const allowed = [
      "Your account is deleted",
      "we cannot yet confirm the repository copy is removed",
    ];
    let msg = ERASURE_PENDING_TOOL_MESSAGE;
    for (const phrase of allowed) {
      expect(msg).toContain(phrase);
      msg = msg.replace(phrase, "");
    }
    expect(msg).not.toMatch(/erased|removed|purged|wiped|destroyed|deleted|gone/i);
    expect(ERASURE_PENDING_TOOL_MESSAGE).not.toMatch(/cascade complete|straight away|will be completed|nothing further/i);
    expect(ERASURE_PENDING_TOOL_MESSAGE).not.toMatch(/\.gc-cursor|\.init\.lock|lock file|purge|workspace files/i);
    expect(ERASURE_PENDING_TOOL_MESSAGE).toMatch(/best effort/i);
  });

  test("complete message makes no workspace-file or residue claim and uses no jargon", () => {
    expect(ERASURE_COMPLETE_TOOL_MESSAGE).not.toMatch(/cascade|workspace files|\.gc-cursor|lock file|purge|erased|wiped/i);
  });

  test("failure path is unchanged", async () => {
    mockDeleteAccount.mockResolvedValue({ success: false, error: "boom" });
    const res = await deleteTool().handler(INPUT);
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text)).toEqual({ error: "delete_failed", message: "boom" });
  });

  test("description drops the workspace-files claim, documents the flag and promises only best effort", () => {
    const d = deleteTool().description;
    expect(d).toContain("gitDataErasurePending");
    expect(d).toContain("agentInstruction");
    expect(d).toMatch(/best-effort/i);
    expect(d).not.toMatch(/retried automatically|deletes all account data|workspace files/i);
    expect(d).toMatch(/not tell[^.]*(?:erased|removed)/i);
  });
});
