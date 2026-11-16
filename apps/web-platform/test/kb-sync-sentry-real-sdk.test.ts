// The KB sync's Sentry emits on the REAL path (#12600, CTO ruling D8). The logger, `reportSilentFallback`,
// `mirrorWithDebounce` and `syncPush` are real; only the Sentry SDK functions are spies (precedent:
// test/agent-auth-failure-sentry-path.test.ts) and `publishKbOnly` is the seam that returns the outcome. Proves, for each
// emit this PR rewrote (`kb-sync.protected-fallback-failed` in both branches, the `syncPush` outer catch): ONE tagged
// message-path capture arrives with its closed tags, and NO `pino-mirror` exception capture beside it (#8629: an Error
// argument makes the logger's mirror capture first and the tagged capture is then deduplicated, so the paging alert on
// `op` could never fire). Also: the fallback-failed capture is debounced per workspace and reason. Synthesized data only.
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
import { stripHostGitBlock } from "./helpers/host-git-block";

vi.hoisted(() => {
  process.env.LOG_LEVEL = "info";
});
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

const sentry = vi.hoisted(() => ({
  captureMessage: vi.fn(),
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
}));
vi.mock("@sentry/nextjs", async (orig) => {
  const real = await orig<typeof import("@sentry/nextjs")>();
  return {
    ...real,
    init: real.init,
    getIsolationScope: real.getIsolationScope,
    getCurrentScope: real.getCurrentScope,
    withIsolationScope: real.withIsolationScope,
    ...sentry,
  };
});

const { publishSpy } = vi.hoisted(() => ({ publishSpy: vi.fn() }));

// execFileSync (connected-repo wrapper): a remote exists, one local commit, a clean status (no auto-commit).
vi.mock("child_process", () => ({
  execFileSync: vi.fn((_cmd: string, rawArgs: string[]) => {
    const args = stripHostGitBlock(rawArgs);
    if (args[0] === "remote") return Buffer.from("origin\tgit@github.com:acme/widgets.git (fetch)\n");
    if (args[0] === "rev-list") return Buffer.from("1\n");
    return Buffer.from("");
  }),
}));
vi.mock("fs", async (orig) => ({
  ...(await orig<typeof import("fs")>()),
  readdirSync: vi.fn(() => []),
  lstatSync: vi.fn(() => {
    throw Object.assign(new Error("ENOENT"), { code: "ENOENT" }); // no .git, no MERGE_HEAD
  }),
}));
vi.mock("@supabase/supabase-js", () => ({ createClient: vi.fn() }));
vi.mock("@/lib/supabase/tenant", () => {
  class FakeRuntimeAuthError extends Error {}
  const chain: Record<string, unknown> = {};
  chain.eq = () => chain;
  chain.maybeSingle = async () => ({ data: { id: "user-1" }, error: null });
  return {
    getFreshTenantClient: vi.fn(async () => ({ from: () => ({ select: () => chain }), rpc: async () => ({ error: null }) })),
    RuntimeAuthError: FakeRuntimeAuthError,
  };
});
vi.mock("../server/git-auth", () => ({ gitWithInstallationAuth: vi.fn() }));
vi.mock("../server/resolve-installation-id", () => ({ resolveInstallationId: async () => 42 }));
vi.mock("../server/workspace-repo-mirror", () => ({ writeRepoColsToWorkspace: vi.fn(async () => undefined) }));
vi.mock("../server/approval/workspace-head", async (orig) => ({
  ...(await orig<typeof import("../server/approval/workspace-head")>()),
  readWorkspaceHeadRef: () => ({ sha: "a".repeat(40), refName: "refs/heads/main" }),
}));
vi.mock("../server/kb-sync-publish", async (orig) => ({
  ...(await orig<typeof import("../server/kb-sync-publish")>()),
  publishKbOnly: publishSpy,
}));

import { syncPush } from "@/server/session-sync";
import { __resetMirrorDebounceForTests } from "@/server/observability";
import { KbSyncError } from "../server/kb-sync-publish";

type Capture = [string, { level?: string; tags?: Record<string, string>; extra?: Record<string, unknown> }];
const messagesFor = (op: string) => (sentry.captureMessage.mock.calls as Capture[]).filter(([, o]) => o?.tags?.op === op);
const pinoMirror = () =>
  (sentry.captureException.mock.calls as Array<[unknown, { tags?: Record<string, string> }?]>).filter(([, o]) => o?.tags?.feature === "pino-mirror");
const run = (ws = "ws-1") => syncPush("user-1", "/tmp/ws-real-sdk", {} as never, ws);

const consoleSpies = (["log", "info", "warn", "error", "debug"] as const).map((m) => vi.spyOn(console, m).mockImplementation(() => undefined));
afterAll(() => {
  for (const spy of consoleSpies) spy.mockRestore();
});
beforeEach(() => {
  for (const f of Object.values(sentry)) f.mockReset();
  publishSpy.mockReset();
  __resetMirrorDebounceForTests();
});

describe("KB sync Sentry emits on the real SDK path (D8)", () => {
  it("fallback_failed: one tagged error-level message capture, no pino-mirror exception, and a repeat in the window is debounced", async () => {
    publishSpy.mockResolvedValue({ kind: "fallback_failed", fallbackReason: "side_push_rejected", pushErr: new KbSyncError("push_rejected", "protected_branch") });
    await run();
    const caps = messagesFor("kb-sync.protected-fallback-failed");
    expect(caps).toHaveLength(1);
    const [, o] = caps[0];
    expect(o.level).toBe("error");
    expect(o.tags).toEqual(
      expect.objectContaining({
        feature: "session-sync",
        op: "kb-sync.protected-fallback-failed",
        reason: "fallback_failed",
        fallback_reason: "side_push_rejected",
        push_class: "protected_branch",
      }),
    );
    expect(pinoMirror()).toEqual([]);
    expect(sentry.captureException).not.toHaveBeenCalled();
    // same workspace, same reason: debounced; another reason still emits
    await run();
    expect(messagesFor("kb-sync.protected-fallback-failed")).toHaveLength(1);
    publishSpy.mockResolvedValue({ kind: "fallback_failed", fallbackReason: "pr_failed", pushErr: new KbSyncError("push_rejected", "protected_branch") });
    await run();
    expect(messagesFor("kb-sync.protected-fallback-failed")).toHaveLength(2);
  });

  it("persistent_other: one tagged capture with reason persistent_other, no pino-mirror exception", async () => {
    publishSpy.mockRejectedValue(new KbSyncError("push_rejected", "persistent_other"));
    await run();
    const caps = messagesFor("kb-sync.protected-fallback-failed");
    expect(caps).toHaveLength(1);
    expect(caps[0][1].tags).toEqual(expect.objectContaining({ reason: "persistent_other", push_class: "persistent_other" }));
    expect(pinoMirror()).toEqual([]);
    expect(sentry.captureException).not.toHaveBeenCalled();
  });

  it("outer catch: op syncPush with the closed reason and push class tags; a non-KbSyncError carries errName, never its argv message", async () => {
    publishSpy.mockRejectedValue(new KbSyncError("ls_remote_failed"));
    await run();
    let caps = messagesFor("syncPush");
    expect(caps).toHaveLength(1);
    expect(caps[0][1].tags).toEqual(expect.objectContaining({ reason: "ls_remote_failed", push_class: "none" }));
    expect(pinoMirror()).toEqual([]);

    sentry.captureMessage.mockReset();
    publishSpy.mockRejectedValue(Object.assign(new Error("Command failed: git push https://github.com/acme/widgets.git " + "c".repeat(40)), { name: "GitChildError" }));
    await run();
    caps = messagesFor("syncPush");
    expect(caps).toHaveLength(1);
    expect(caps[0][1].tags).toEqual(expect.objectContaining({ reason: "unclassified", push_class: "none" }));
    expect(caps[0][1].extra).toEqual(expect.objectContaining({ errName: "GitChildError" }));
    expect(JSON.stringify(sentry.captureMessage.mock.calls)).not.toMatch(/github\.com|Command failed|c{40}/);
    expect(pinoMirror()).toEqual([]);
  });
});
