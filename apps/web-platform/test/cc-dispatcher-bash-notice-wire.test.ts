import { describe, it, expect, vi, beforeEach } from "vitest";

// #10455 c, A6(b) — drive the dispatcher's REAL onToolResult (not its source text). The classifier and
// `selectCommandStreamOutput` have their own unit rows; this file pins the WIRE between them and the user-facing stream:
//   - an error-flagged lone pre-exec denial streams the fixed platform notice (and ONLY the notice),
//   - the same bytes with isError false stream untouched (forged-line control),
//   - the Sentry mirror always reads the RAW output, never the rewritten text, and runs without the autonomous posture.
// A source-text regex cannot see a comma-operator mutant like `(selectCommandStreamOutput(...), block.output)`;
// a behavioural row does.

const {
  mockReportSilentFallback,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
  mockMirrorP0Deduped,
  autonomous,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockMirrorP0Deduped: vi.fn(),
  autonomous: { value: true },
}));

vi.mock("@/server/conversation-writer", async () => {
  const { conversationWriterFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return conversationWriterFactory({ mockUpdateConversationFor });
});
vi.mock("@/server/observability", async () => {
  const { observabilityFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return observabilityFactory({ mockReportSilentFallback, mockMirrorP0Deduped });
});
vi.mock("@/server/cost-writer", async () => {
  const { costWriterFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return costWriterFactory();
});
vi.mock("@/server/kb-document-resolver", async () => {
  const { kbDocumentResolverFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return kbDocumentResolverFactory({ mockFetchUserWorkspacePath });
});
vi.mock("@/lib/supabase/tenant", async () => {
  const { supabaseTenantFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return supabaseTenantFactory({ mockMessagesInsert, mockConversationWorkspaceId: "ws-A" });
});
vi.mock("@/lib/supabase/service", async () => {
  const { supabaseServiceFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return supabaseServiceFactory({ mockMessagesInsert, mockConversationWorkspaceId: "ws-A" });
});
vi.mock("@/server/resolve-bash-autonomous", () => ({
  resolveBashAutonomous: vi.fn(async () => autonomous.value),
}));

import { dispatchSoleurGo, __resetDispatcherForTests, __setCcRunnerForTests } from "@/server/cc-dispatcher";
import { BASH_UNAVAILABLE_NOTICE } from "@/server/sandbox-startup-classifier";
import { flushMicrotasks } from "./helpers/soleur-go-fixtures";

type ToolResultBlock = { toolUseId: string; command: string; output: string; isError?: boolean };
interface CapturedEvents {
  onToolResult?: (block: ToolResultBlock) => void;
}

const HELPER = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";
const BWRAP = "bwrap: Can't mount proc on /newroot/proc: Operation not permitted";

function makeStubCcRunner(onDispatch: (events: CapturedEvents) => void) {
  return {
    dispatch: vi.fn(async (a: { events: CapturedEvents }) => {
      await Promise.resolve();
      onDispatch(a.events);
      return { queryReused: false };
    }),
    hasActiveQuery: () => false,
    activeQueriesSize: () => 0,
    reapIdle: () => 0,
    closeConversation: () => {},
    respondToToolUse: () => false,
    notifyAwaitingUser: () => {},
    // biome-ignore lint/suspicious/noExplicitAny: minimal stub
  } as any;
}

async function dispatch(): Promise<{ events: CapturedEvents; sendToClient: ReturnType<typeof vi.fn> }> {
  let captured: CapturedEvents | undefined;
  __setCcRunnerForTests(makeStubCcRunner((e) => (captured = e)));
  const sendToClient = vi.fn().mockReturnValue(true);
  await dispatchSoleurGo({
    persona: "command_center",
    userId: "u-notice",
    conversationId: "conv-notice",
    userMessage: "run a command",
    currentRouting: { kind: "soleur_go_pending" },
    sendToClient,
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
  });
  await flushMicrotasks();
  expect(captured?.onToolResult).toBeTypeOf("function");
  return { events: captured!, sendToClient };
}

const outputFrames = (sendToClient: ReturnType<typeof vi.fn>) =>
  sendToClient.mock.calls
    .map(([, msg]) => msg as { type?: string; phase?: string; output?: string })
    .filter((m) => m?.type === "command_stream" && m.phase === "output");
const phases = (sendToClient: ReturnType<typeof vi.fn>) =>
  sendToClient.mock.calls
    .map(([, msg]) => msg as { type?: string; phase?: string })
    .filter((m) => m?.type === "command_stream")
    .map((m) => m.phase);
const sandboxMirrors = () =>
  mockReportSilentFallback.mock.calls.filter(([, ctx]) => ctx?.op === "bash-tool-result");

describe("dispatchSoleurGo onToolResult — the platform notice wire (#10455 c, A6b)", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    mockReportSilentFallback.mockClear();
    mockFetchUserWorkspacePath.mockReset();
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/claude-XXXX/workspace");
    mockMessagesInsert.mockClear();
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockClear();
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
    autonomous.value = true;
  });

  it("an isError tool_result carrying a lone pre-exec denial streams the notice, never the raw line", async () => {
    const { events, sendToClient } = await dispatch();
    for (const [i, raw] of [HELPER, BWRAP].entries()) {
      sendToClient.mockClear();
      events.onToolResult!({ toolUseId: `tu-err-${i}`, command: "ls", output: raw, isError: true });
      const frames = outputFrames(sendToClient);
      expect(frames, raw).toHaveLength(1);
      expect(frames[0].output).toBe(BASH_UNAVAILABLE_NOTICE);
      expect(JSON.stringify(sendToClient.mock.calls)).not.toContain("apply-seccomp");
      expect(JSON.stringify(sendToClient.mock.calls)).not.toContain("bwrap:");
      expect(phases(sendToClient)).toEqual(["output", "end"]);
    }
  });

  it("control: the same bytes with isError false stream byte for byte (a forged line from a command that ran)", async () => {
    const { events, sendToClient } = await dispatch();
    events.onToolResult!({ toolUseId: "tu-ok", command: "echo", output: HELPER, isError: false });
    const frames = outputFrames(sendToClient);
    expect(frames).toHaveLength(1);
    expect(frames[0].output).toBe(HELPER);
    expect(frames[0].output).not.toBe(BASH_UNAVAILABLE_NOTICE);
    // ...and an absent flag is not an error either.
    sendToClient.mockClear();
    events.onToolResult!({ toolUseId: "tu-undef", command: "echo", output: HELPER });
    expect(outputFrames(sendToClient)[0].output).toBe(HELPER);
  });

  it("mixed or multi-line error output is streamed unchanged", async () => {
    const { events, sendToClient } = await dispatch();
    events.onToolResult!({ toolUseId: "tu-mixed", command: "x", output: `hello\n${HELPER}`, isError: true });
    expect(outputFrames(sendToClient)[0].output).toBe(`hello\n${HELPER}`);
  });

  it("the Sentry mirror reads the RAW output: the page fires with the real code while the user sees only the notice", async () => {
    const { events, sendToClient } = await dispatch();
    events.onToolResult!({ toolUseId: "tu-mirror", command: "ls", output: HELPER, isError: true });
    const mirrors = sandboxMirrors();
    expect(mirrors).toHaveLength(1);
    expect(mirrors[0][1].extra.sandboxErrorCode).toBe("helper_userns_eperm");
    expect(mirrors[0][1].extra.sandboxStderr).toBe(HELPER);
    expect(outputFrames(sendToClient)[0].output).toBe(BASH_UNAVAILABLE_NOTICE);
  });

  it("a post-command waitpid line is mirrored (it pages) but never rewritten", async () => {
    const { events, sendToClient } = await dispatch();
    const waitpid = "apply-seccomp: waitpid: Operation not permitted";
    events.onToolResult!({ toolUseId: "tu-wait", command: "x", output: waitpid, isError: true });
    expect(sandboxMirrors()).toHaveLength(1);
    expect(outputFrames(sendToClient)[0].output).toBe(waitpid);
  });

  it("outside the autonomous posture nothing is streamed, but the Sentry mirror still fires (posture-independent)", async () => {
    autonomous.value = false;
    const { events, sendToClient } = await dispatch();
    events.onToolResult!({ toolUseId: "tu-nonauto", command: "ls", output: HELPER, isError: true });
    expect(phases(sendToClient)).toEqual([]);
    expect(sandboxMirrors()).toHaveLength(1);
  });

  it("A2: a tenant line that merely contains the word bwrap is streamed as is, not replaced by the notice", async () => {
    const { events, sendToClient } = await dispatch();
    const line = "rm: cannot remove 'bwrap': Operation not permitted";
    events.onToolResult!({ toolUseId: "tu-rm", command: "rm bwrap", output: line, isError: true });
    expect(outputFrames(sendToClient)[0].output).toBe(line);
  });
});
