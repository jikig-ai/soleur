// #5715 — warm-dispatch re-clone must be AWAITED before the agent runs.
//
// The cold Concierge dispatch path awaits the workspace re-clone before it
// constructs the sandbox / SDK query(); the warm path historically fired
// `reprovisionWorkspaceOnDispatch(userId)` fire-and-forget and immediately
// pushed the turn into the already-running SDK iterator. After a mid-session
// reclaim (`.git` wiped) the next warm turn's per-tool bwrap sandbox chdirs
// into a `.git`-less workspace BEFORE the (slow, 120s-timeout) re-clone
// finishes → `fatal: not a git repository` and an honest-stop.
//
// This suite pins the warm gate in `dispatchSoleurGo`:
//   - warm + reclone pending  → `runner.dispatch` is NOT called until it resolves
//   - warm + reclone "failed"  → honest reclaim message + NO dispatch
//   - warm + reclone throws    → fail-safe: mirror + fall through to dispatch
//   - cold                     → unchanged fire-and-forget
//
// Seam (test-design review): force the warm branch deterministically via
// `__setCcRunnerForTests({ hasActiveQuery: () => true, ... })` and module-mock
// the awaited `reprovisionWorkspaceOnDispatch` (NOT its internal
// `ensureWorkspaceRepoCloned`). The genuine unmocked `existsSync` `.git`
// short-circuit (Part A) is covered in `cc-reprovision-git-discriminator.test.ts`.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const {
  mockReportSilentFallback,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
  mockMirrorP0Deduped,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockMirrorP0Deduped: vi.fn(),
}));

vi.mock("@/server/conversation-writer", async () => {
  const { conversationWriterFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return conversationWriterFactory({ mockUpdateConversationFor });
});

vi.mock("@/server/observability", async () => {
  const { observabilityFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return observabilityFactory({
    mockReportSilentFallback,
    mockMirrorP0Deduped,
    withTtlDedupWrapper: true,
  });
});

vi.mock("@/server/cost-writer", async () => {
  const { costWriterFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return costWriterFactory();
});

vi.mock("@/server/kb-document-resolver", async () => {
  const { kbDocumentResolverFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return kbDocumentResolverFactory({ mockFetchUserWorkspacePath });
});

vi.mock("@/lib/supabase/tenant", async () => {
  const { supabaseTenantFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return supabaseTenantFactory({
    mockMessagesInsert,
    mockConversationWorkspaceId: "ws-A",
  });
});

vi.mock("@/lib/supabase/service", async () => {
  const { supabaseServiceFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return supabaseServiceFactory({
    mockMessagesInsert,
    mockConversationWorkspaceId: "ws-A",
  });
});

// The awaited warm gate calls this; module-mock it so the suite drives the
// outcome (pending / "ok" / "failed" / throw) deterministically.
vi.mock("@/server/cc-reprovision", () => ({
  reprovisionWorkspaceOnDispatch: vi.fn().mockResolvedValue("ok"),
}));

import {
  dispatchSoleurGo,
  __setCcRunnerForTests,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
import { reprovisionWorkspaceOnDispatch } from "@/server/cc-reprovision";
import {
  WORKSPACE_RECLAIMED_MESSAGE,
  WORKFLOW_END_USER_MESSAGES,
} from "@/server/cc-workflow-end-messages";
import { __resetMirrorP0DedupForTests } from "@/server/observability";
import type { WSMessage } from "@/lib/types";

// A controllable deferred so the test can hold the awaited reclone pending and
// then resolve it on demand.
function deferred<T>() {
  let resolve!: (v: T) => void;
  let reject!: (e: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

// Macrotask flush: lets every pending microtask AND any fire-and-forget
// `.then` chain settle. On `origin/main` (fire-and-forget) `runner.dispatch`
// fires within this window even while the reclone is pending — which is exactly
// what scenario 1 asserts must NOT happen after the fix.
function flushAll(): Promise<void> {
  return new Promise((r) => setTimeout(r, 0));
}

const tmpDirs: string[] = [];
function gitPresentDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "warm-reclone-present-"));
  mkdirSync(join(dir, ".git"));
  tmpDirs.push(dir);
  return dir;
}
function reclaimedDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "warm-reclone-reclaimed-"));
  tmpDirs.push(dir);
  return dir;
}

// Extract the `message` of every `{ type: "error" }` frame the dispatcher
// emitted (WSMessage is a union; narrow via the runtime `type` discriminant).
function errorMessages(sendToClient: ReturnType<typeof vi.fn>): string[] {
  return (sendToClient.mock.calls as [string, WSMessage][])
    .map(([, msg]) => msg)
    .filter((msg): msg is Extract<WSMessage, { type: "error" }> => msg?.type === "error")
    .map((msg) => msg.message);
}

function makeStubRunner(opts: { hasActiveQuery: boolean }) {
  return {
    dispatch: vi.fn(async () => {}),
    hasActiveQuery: () => opts.hasActiveQuery,
    activeQueriesSize: () => 0,
    reapIdle: () => 0,
    closeConversation: () => {},
    respondToToolUse: () => false,
    notifyAwaitingUser: () => {},
    // biome-ignore lint/suspicious/noExplicitAny: minimal stub
  } as any;
}

const BASE_ARGS = {
  userId: "u1",
  conversationId: "conv-warm",
  userMessage: "resume",
  currentRouting: { kind: "soleur_go_pending" as const },
  persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
};

describe("dispatchSoleurGo — warm-dispatch reclone await (#5715)", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    __resetMirrorP0DedupForTests();
    mockReportSilentFallback.mockClear();
    mockFetchUserWorkspacePath.mockReset();
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/claude-XXXX/workspace");
    mockMessagesInsert.mockClear();
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockClear();
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
    vi.mocked(reprovisionWorkspaceOnDispatch).mockReset();
    vi.mocked(reprovisionWorkspaceOnDispatch).mockResolvedValue("ok");
  });

  afterEach(() => {
    while (tmpDirs.length) {
      const dir = tmpDirs.pop();
      if (dir) rmSync(dir, { recursive: true, force: true });
    }
  });

  // S1 (AC1 — load-bearing RED on main): warm + `.git` absent → `runner.dispatch`
  // is gated on the reclone RESOLVING. Pending deferred → not called after a
  // full flush; resolve → called exactly once. On fire-and-forget main this
  // FAILS (dispatch already fired while the reclone was pending).
  it("S1: warm turn does NOT dispatch until the awaited reclone resolves", async () => {
    const reclaimed = reclaimedDir();
    const stubRunner = makeStubRunner({ hasActiveQuery: true });
    __setCcRunnerForTests(stubRunner);

    const gate = deferred<"ok" | "failed">();
    vi.mocked(reprovisionWorkspaceOnDispatch).mockReturnValueOnce(gate.promise);

    const sendToClient = vi.fn().mockReturnValue(true);
    const p = dispatchSoleurGo({
      ...BASE_ARGS,
      conversationId: "conv-warm-s1",
      sendToClient,
      workspacePath: reclaimed,
    });

    await flushAll();
    // The fix: the turn cannot reach the sandbox until the reclone resolves.
    expect(stubRunner.dispatch).not.toHaveBeenCalled();

    gate.resolve("ok");
    await p;
    // Non-vacuity: dispatch DID fire after the reclone resolved (not merely
    // "never"), AND the awaited reclone ran.
    expect(reprovisionWorkspaceOnDispatch).toHaveBeenCalledTimes(1);
    expect(stubRunner.dispatch).toHaveBeenCalledTimes(1);
  });

  // S2 (AC2/AC4 at the dispatch level): warm + reclone returns "ok" fast (the
  // `.git`-present self-short-circuit) → dispatch proceeds. The genuine unmocked
  // existsSync short-circuit + no-reclone-on-present-.git is in
  // cc-reprovision-git-discriminator.test.ts.
  it("S2: warm + reclone resolves 'ok' (git present short-circuit) → dispatch proceeds", async () => {
    const present = gitPresentDir();
    const stubRunner = makeStubRunner({ hasActiveQuery: true });
    __setCcRunnerForTests(stubRunner);
    vi.mocked(reprovisionWorkspaceOnDispatch).mockResolvedValueOnce("ok");

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      ...BASE_ARGS,
      conversationId: "conv-warm-s2",
      sendToClient,
      workspacePath: present,
    });

    expect(reprovisionWorkspaceOnDispatch).toHaveBeenCalledTimes(1);
    expect(stubRunner.dispatch).toHaveBeenCalledTimes(1);
  });

  // S3 (AC3): cold turn → the dispatch-level gate stays fire-and-forget; the
  // factory owns the await. Dispatch is not blocked on the reclone.
  it("S3: cold turn keeps the fire-and-forget reclone (gate inert)", async () => {
    const stubRunner = makeStubRunner({ hasActiveQuery: false });
    __setCcRunnerForTests(stubRunner);

    const gate = deferred<"ok" | "failed">();
    vi.mocked(reprovisionWorkspaceOnDispatch).mockReturnValueOnce(gate.promise);

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      ...BASE_ARGS,
      conversationId: "conv-cold-s3",
      sendToClient,
    });

    // Cold path never awaits the reclone — dispatch ran even though the
    // reclone is still pending.
    expect(stubRunner.dispatch).toHaveBeenCalledTimes(1);
    gate.resolve("ok");
  });

  // S4 (AC9): warm gate is self-contained — an awaited reclone THROW is mirrored
  // (op: reprovision-on-dispatch-await) and falls through to dispatch (fail-safe,
  // never rejects out of dispatch).
  it("S4: warm + reclone throws → mirror + fall through to dispatch", async () => {
    const reclaimed = reclaimedDir();
    const stubRunner = makeStubRunner({ hasActiveQuery: true });
    __setCcRunnerForTests(stubRunner);
    vi.mocked(reprovisionWorkspaceOnDispatch).mockRejectedValueOnce(
      new Error("reclone boom"),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      ...BASE_ARGS,
      conversationId: "conv-warm-s4",
      sendToClient,
      workspacePath: reclaimed,
    });

    expect(stubRunner.dispatch).toHaveBeenCalledTimes(1);
    const awaitMirror = mockReportSilentFallback.mock.calls.find(
      ([, ctx]) =>
        (ctx as { op?: string })?.op === "reprovision-on-dispatch-await",
    );
    expect(awaitMirror).toBeDefined();
  });

  // S5 (AC10): warm + reclone "failed" → honest reclaim message + NO dispatch
  // (the agent is never spawned into a known-`.git`-less workspace). Counter:
  // "ok" → dispatch IS called.
  it("S5: warm + reclone 'failed' → honest reclaim message, NO dispatch", async () => {
    const reclaimed = reclaimedDir();
    const stubRunner = makeStubRunner({ hasActiveQuery: true });
    __setCcRunnerForTests(stubRunner);
    vi.mocked(reprovisionWorkspaceOnDispatch).mockResolvedValueOnce("failed");

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      ...BASE_ARGS,
      conversationId: "conv-warm-s5",
      sendToClient,
      workspacePath: reclaimed,
    });

    expect(stubRunner.dispatch).not.toHaveBeenCalled();
    expect(errorMessages(sendToClient)).toContain(WORKSPACE_RECLAIMED_MESSAGE);
  });

  it("S5b: warm + reclone 'ok' → dispatch IS called, no reclaim message", async () => {
    const stubRunner = makeStubRunner({ hasActiveQuery: true });
    __setCcRunnerForTests(stubRunner);
    vi.mocked(reprovisionWorkspaceOnDispatch).mockResolvedValueOnce("ok");

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      ...BASE_ARGS,
      conversationId: "conv-warm-s5b",
      sendToClient,
    });

    expect(stubRunner.dispatch).toHaveBeenCalledTimes(1);
    const msgs = errorMessages(sendToClient);
    expect(msgs).not.toContain(WORKSPACE_RECLAIMED_MESSAGE);
    expect(msgs).not.toContain(WORKFLOW_END_USER_MESSAGES.worktree_enter_failed);
  });
});
