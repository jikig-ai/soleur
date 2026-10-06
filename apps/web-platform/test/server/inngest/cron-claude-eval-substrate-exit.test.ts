// #7122 P2-1 / P2-2 — how spawnClaudeEval ENDS a child.
//
// Separate file because it `vi.mock`s node:child_process (the mock hoists file-wide and
// would clobber the real-spawn rows in cron-claude-eval-substrate.test.ts).
//
//   P2-1  the child's whole process group is killed on EVERY exit, not only on the
//         timeout path: a daemonised grandchild that survived a normal exit could poll
//         `.git/config` and read the write token the handler mints AFTER the spawn.
//   P2-2  the spawn resolves on `exit`, but Node can emit `exit` before the stdout
//         pipe has been read to its end. The final `result` line is the community
//         draft; a lost line is a rejected day. The spawn now also waits (bounded) for
//         the stdout readline `close` before resolving.
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const { spawnMock } = vi.hoisted(() => ({ spawnMock: vi.fn() }));
vi.mock("node:child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("node:child_process")>()),
  spawn: spawnMock,
}));
vi.mock("@/server/claude-cost-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/claude-cost-marker")>()),
  emitClaudeCostMarker: vi.fn(),
}));

import { spawnClaudeEval } from "@/server/inngest/functions/_cron-claude-eval-substrate";

const FAKE_PID = 4_242_424;
const TOKEN = "ghs_FAKEtoken0123456789ABCDEFghijklmnop";
const noopLogger = {
  info: () => {},
  error: () => {},
  warn: () => {},
  debug: () => {},
} as unknown as Parameters<typeof spawnClaudeEval>[0]["logger"];

class FakeChild extends EventEmitter {
  pid = FAKE_PID;
  stdout = new PassThrough();
  stderr = new PassThrough();
}

const resultLine = (result: string) =>
  JSON.stringify({ type: "result", subtype: "success", is_error: false, result, permission_denials: [] }) + "\n";

function run(extra: Record<string, unknown> = {}) {
  return spawnClaudeEval({
    spawnCwd: process.cwd(),
    installationToken: TOKEN,
    flags: ["--print"],
    prompt: "ignored",
    maxTurnDurationMs: 30_000,
    cronName: "cron-bug-fixer",
    buildSpawnEnv: () => process.env,
    logger: noopLogger,
    ...extra,
  });
}

describe("spawnClaudeEval — child end (#7122 P2-1, P2-2)", () => {
  const ORIGINAL_CLAUDE_BIN = process.env.CLAUDE_BIN;
  let killSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    spawnMock.mockReset();
    process.env.CLAUDE_BIN = process.execPath; // any existing file: the spawn itself is mocked
    killSpy = vi.spyOn(process, "kill").mockImplementation(() => true);
  });
  afterEach(() => {
    killSpy.mockRestore();
    if (ORIGINAL_CLAUDE_BIN === undefined) delete process.env.CLAUDE_BIN;
    else process.env.CLAUDE_BIN = ORIGINAL_CLAUDE_BIN;
  });

  const groupKills = () => killSpy.mock.calls.filter((c: unknown[]) => c[0] === -FAKE_PID);

  it("P2-1: SIGKILLs the child's process group on a NORMAL exit (not only on timeout)", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run();
    child.stdout.write(resultLine("done"));
    child.emit("exit", 0, null);
    child.stdout.end();
    child.stderr.end();
    const res = await p;
    expect(res.ok).toBe(true);
    expect(res.abortedByTimeout).toBe(false);
    expect(groupKills()).toEqual([[-FAKE_PID, "SIGKILL"]]);
  });

  it("P2-1: the group kill is best-effort — an ESRCH from process.kill never rejects the spawn", async () => {
    killSpy.mockImplementation(() => {
      throw Object.assign(new Error("kill ESRCH"), { code: "ESRCH" });
    });
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run();
    child.emit("exit", 1, null);
    child.stdout.end();
    child.stderr.end();
    await expect(p).resolves.toMatchObject({ ok: false, exitCode: 1 });
  });

  it("P2-1: a child that is killed by a signal is also group-killed", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run();
    child.emit("exit", null, "SIGTERM");
    child.stdout.end();
    child.stderr.end();
    await p;
    expect(groupKills().length).toBe(1);
  });

  it("P2-2: a result line that arrives AFTER `exit` (stdout not yet drained) is not lost", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run({ captureFinalMessage: true });
    child.emit("exit", 0, null);
    // The pipe still holds the final line; it is read after the exit event.
    await new Promise((r) => setTimeout(r, 30));
    child.stdout.write(resultLine('{"periodDays":7}'));
    child.stdout.end();
    child.stderr.end();
    const res = await p;
    expect(res.finalMessage).toBe('{"periodDays":7}');
    expect(res.stdoutTail).toContain('{"periodDays":7}');
  });

  it("P2-2: the wait for stdout close is BOUNDED — a stdout that never closes still resolves", async () => {
    vi.useFakeTimers();
    try {
      const child = new FakeChild();
      spawnMock.mockReturnValue(child);
      const p = run();
      child.emit("exit", 0, null);
      let settled = false;
      void p.then(() => {
        settled = true;
      });
      await vi.advanceTimersByTimeAsync(500);
      expect(settled, "must still be waiting inside the bound").toBe(false);
      await vi.advanceTimersByTimeAsync(2_000);
      expect(settled, "must resolve once the bound elapses").toBe(true);
      await expect(p).resolves.toMatchObject({ exitCode: 0 });
    } finally {
      vi.useRealTimers();
    }
  });

  it("P2-2: a spawn `error` still resolves immediately (no stdout wait for a child that never started)", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run();
    child.emit("error", new Error("spawn ENOENT"));
    await expect(p).resolves.toMatchObject({ ok: false, exitCode: -1 });
  });
});
