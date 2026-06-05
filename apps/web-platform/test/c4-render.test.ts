import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { EventEmitter } from "node:events";

// Mock child_process.spawn so we drive the CLI lifecycle deterministically.
const spawnMock = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({ spawn: spawnMock }));

import { renderC4Model } from "@/server/c4-render";

type FakeChild = EventEmitter & {
  stderr: EventEmitter;
  kill: ReturnType<typeof vi.fn>;
};

function makeChild(): FakeChild {
  const child = new EventEmitter() as FakeChild;
  child.stderr = new EventEmitter();
  child.kill = vi.fn();
  return child;
}

/** Capture the most recent spawn call's (cmd, args, opts). */
function lastSpawn() {
  const calls = spawnMock.mock.calls;
  return calls[calls.length - 1] as [string, string[], Record<string, unknown>];
}

beforeEach(() => {
  spawnMock.mockReset();
  vi.useRealTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

const WS = "/workspaces/ws-1";
const EXPECTED_CWD = "/workspaces/ws-1/knowledge-base/engineering/architecture/diagrams";

describe("renderC4Model", () => {
  it("spawns the likec4 CLI with fixed argv in the scope-guarded diagrams dir", async () => {
    const child = makeChild();
    spawnMock.mockImplementation(() => child);
    const p = renderC4Model(WS);
    // exit success
    queueMicrotask(() => child.emit("close", 0, null));
    const res = await p;
    expect(res.ok).toBe(true);

    const [bin, args, opts] = lastSpawn();
    expect(typeof bin).toBe("string");
    expect(bin.length).toBeGreaterThan(0);
    // Fixed argv — NO user-controlled tokens.
    expect(args).toEqual(["export", "json", "-o", "model.likec4.json", "."]);
    // cwd is the constant-derived diagrams dir, never a user filename.
    expect(opts.cwd).toBe(EXPECTED_CWD);
    // scoped env: the allow-list keys are present (HOME is load-bearing for
    // npm-global bin resolution) and no secret leaks through.
    const env = opts.env as Record<string, string>;
    expect(Object.keys(env)).toEqual(
      expect.arrayContaining(["PATH", "HOME"]),
    );
    // Only allow-list keys — nothing outside PATH/LANG/LC_ALL/HOME/TMPDIR.
    const ALLOWED = new Set(["PATH", "LANG", "LC_ALL", "HOME", "TMPDIR"]);
    expect(Object.keys(env).every((k) => ALLOWED.has(k))).toBe(true);
    expect(env).not.toHaveProperty("SUPABASE_SERVICE_ROLE_KEY");
  });

  it("returns non_zero_exit with sanitized, truncated stderr", async () => {
    const child = makeChild();
    spawnMock.mockImplementation(() => child);
    const p = renderC4Model(WS);
    queueMicrotask(() => {
      child.stderr.emit("data", Buffer.from("parse error\x1b[2J\n"));
      child.emit("close", 1, null);
    });
    const res = await p;
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.reason).toBe("non_zero_exit");
      expect(res.detail).toContain("exit=1");
      // control chars sanitized
      expect(res.detail).not.toContain("\x1b");
    }
  });

  it("returns spawn_error when the CLI binary is missing (ENOENT)", async () => {
    const child = makeChild();
    spawnMock.mockImplementation(() => child);
    const p = renderC4Model(WS);
    queueMicrotask(() =>
      child.emit("error", Object.assign(new Error("spawn likec4 ENOENT"), { code: "ENOENT" })),
    );
    const res = await p;
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.reason).toBe("spawn_error");
  });

  it("does NOT kill a healthy render before the 25s budget, then SIGKILLs past it", async () => {
    vi.useFakeTimers();
    const child = makeChild();
    spawnMock.mockImplementation(() => child);
    const p = renderC4Model(WS);
    // Just under the budget: the timer must NOT have fired — a healthy cold
    // render that finishes at 24.9s must not be killed.
    await vi.advanceTimersByTimeAsync(24_999);
    expect(child.kill).not.toHaveBeenCalled();
    // Cross the boundary: SIGKILL fires and the result is a timeout.
    await vi.advanceTimersByTimeAsync(2);
    const res = await p;
    expect(child.kill).toHaveBeenCalledWith("SIGKILL");
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.reason).toBe("timeout");
  });
});
