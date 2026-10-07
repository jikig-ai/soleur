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
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { loadavg, tmpdir } from "node:os";
import { basename, join } from "node:path";
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
const { reportFallbackMock } = vi.hoisted(() => ({ reportFallbackMock: vi.fn() }));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: reportFallbackMock,
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
    reportFallbackMock.mockReset();
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

  // ---- independent stream drains (test-design P2-2) ------------------------------------
  // `exit` can fire before EITHER pipe is drained. Each stream's wait is its own guard: the
  // old rows closed both in the same tick, so deleting either wait left them green.

  it("P2-2: stdout drains INDEPENDENTLY — stderr closed BEFORE exit, the final stdout line arrives after", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run({ captureFinalMessage: true });
    child.stderr.end();
    await new Promise((r) => setTimeout(r, 20)); // stderr's readline has closed
    child.emit("exit", 0, null);
    await new Promise((r) => setTimeout(r, 30));
    child.stdout.write(resultLine('{"late":"stdout"}'));
    child.stdout.end();
    const res = await p;
    expect(res.finalMessage).toBe('{"late":"stdout"}');
  });

  it("P2-2: stderr drains INDEPENDENTLY — stdout closed BEFORE exit, the failure diagnostic on stderr arrives after", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run();
    child.stdout.end();
    await new Promise((r) => setTimeout(r, 20)); // stdout's readline has closed
    child.emit("exit", 1, null);
    await new Promise((r) => setTimeout(r, 30));
    child.stderr.write("late diagnostic line\n");
    child.stderr.end();
    const res = await p;
    expect(res.stderrTail).toContain("late diagnostic line");
  });

  it("P2-2: the spawn resolves PROMPTLY once both streams close — it does not sit out the 2 s bound", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const t0 = Date.now();
    const p = run();
    child.emit("exit", 0, null);
    child.stdout.end();
    child.stderr.end();
    await p;
    expect(Date.now() - t0).toBeLessThan(1_000);
  });

  it("P2-2: ...and under fake timers it is settled well inside the bound, with no timer left pending", async () => {
    vi.useFakeTimers();
    try {
      const child = new FakeChild();
      spawnMock.mockReturnValue(child);
      const p = run();
      let settled = false;
      void p.then(() => {
        settled = true;
      });
      child.emit("exit", 0, null);
      child.stdout.end();
      child.stderr.end();
      await vi.advanceTimersByTimeAsync(100);
      expect(settled, "both streams closed: must not wait for the 2 s bound").toBe(true);
      // The bound's timer was cleared (a live 2 s timer per spawn is a leak).
      const pendingBound = vi.getTimerCount();
      expect(pendingBound, "timers still pending after the spawn settled").toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });

  // ---- the real spawn options and a real process group (test-design P2-3) ---------------

  it("P2-3: the child is spawned `detached: true` with piped stdout/stderr (so `-pid` is its own process group)", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run();
    child.emit("exit", 0, null);
    child.stdout.end();
    child.stderr.end();
    await p;
    expect(spawnMock).toHaveBeenCalledTimes(1);
    const opts = spawnMock.mock.calls[0][2] as { detached?: boolean; stdio?: unknown };
    expect(opts.detached).toBe(true);
    expect(opts.stdio).toEqual(["ignore", "pipe", "pipe"]);
  });

  // ---- ordering: exit, then error --------------------------------------------------------

  it("exit-then-error: the exit's verdict wins and a late `error` is neither reported as a spawn failure nor allowed to re-settle the run", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run();
    child.emit("exit", 0, null);
    child.emit("error", new Error("EPIPE after exit"));
    child.stdout.end();
    child.stderr.end();
    await expect(p).resolves.toMatchObject({ ok: true, exitCode: 0 });
    expect(
      reportFallbackMock.mock.calls.filter((c) => (c[1] as { message?: string })?.message === "claude-code spawn failed"),
      "a post-exit error must not be reported as 'spawn failed'",
    ).toEqual([]);
  });

  it("error-before-exit still reports the spawn failure (control for the row above)", async () => {
    const child = new FakeChild();
    spawnMock.mockReturnValue(child);
    const p = run();
    child.emit("error", new Error("spawn ENOENT"));
    await expect(p).resolves.toMatchObject({ ok: false, exitCode: -1 });
    const failures = reportFallbackMock.mock.calls.filter((c) => (c[1] as { message?: string })?.message === "claude-code spawn failed");
    expect(failures).toHaveLength(1);
  });

  // ---- the timeout verdict is taken at exit (perf P3-1) ---------------------------------

  it("P3-1: a timeout that fires inside the stdio-drain window does not re-label a clean exit, and does not signal the dead group", async () => {
    vi.useFakeTimers();
    try {
      const child = new FakeChild();
      spawnMock.mockReturnValue(child);
      const p = run({ maxTurnDurationMs: 1_000 });
      child.emit("exit", 0, null); // the clean exit; stdout/stderr are still open (drain pending)
      killSpy.mockClear();
      await vi.advanceTimersByTimeAsync(1_000); // MAX_TURN timer fires INSIDE the 2 s drain window
      expect(killSpy.mock.calls.filter((c: unknown[]) => c[1] === "SIGTERM"), "the abort listener must stand down after exit").toEqual([]);
      await vi.advanceTimersByTimeAsync(2_000); // the drain bound elapses
      const res = await p;
      expect(res.abortedByTimeout, "a clean exit must not be reported as a timeout").toBe(false);
      expect(res.ok).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  it("P3-1: control — a timeout BEFORE exit is still reported as a timeout", async () => {
    vi.useFakeTimers();
    try {
      const child = new FakeChild();
      spawnMock.mockReturnValue(child);
      const p = run({ maxTurnDurationMs: 1_000 });
      await vi.advanceTimersByTimeAsync(1_000);
      expect(killSpy.mock.calls.some((c: unknown[]) => c[0] === -FAKE_PID && c[1] === "SIGTERM")).toBe(true);
      child.emit("exit", null, "SIGTERM");
      child.stdout.end();
      child.stderr.end();
      await vi.advanceTimersByTimeAsync(100);
      await expect(p).resolves.toMatchObject({ abortedByTimeout: true });
    } finally {
      vi.useRealTimers();
    }
  });
});

// A REAL process group (no mocked `process.kill`): the fake `claude` backgrounds a
// SIGTERM-ignoring sleeper in its own group, prints a result line and exits 0. The group
// kill on exit is the only thing that ends the sleeper; with `detached` removed `-pid` is
// ESRCH (the child is not a group leader), the sleeper survives, and the row goes red.
// This row bounds only that the group is EVENTUALLY dead; that the group kill was ISSUED by
// the time the spawn resolves is owned by the mocked P2-1 rows above.
describe("spawnClaudeEval — a real grandchild in the child's process group is reaped on exit (#7122 P2-1, test-design P2-3)", () => {
  const ORIGINAL_CLAUDE_BIN = process.env.CLAUDE_BIN;
  const dirs: string[] = [];
  let sleeperPid: number | null = null;
  // The last observed state, quoted in the failure message so a recurrence is classifiable
  // without reproducing it (a state still `S` after the full wait most likely means the kill
  // was never sent, i.e. the product; a `D` state or a high loadavg points at a stall).
  let lastProbe = "not probed";
  const errCode = (e: unknown) => (e as NodeJS.ErrnoException).code;

  beforeEach(() => {
    spawnMock.mockReset();
    lastProbe = "not probed";
  });
  afterEach(() => {
    // Reaper: once the sleeper's pid is known, never leave it behind, whatever the assertion said.
    if (sleeperPid) {
      try {
        process.kill(sleeperPid, "SIGKILL");
      } catch {
        /* already gone */
      }
      sleeperPid = null;
    }
    for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
    if (ORIGINAL_CLAUDE_BIN === undefined) delete process.env.CLAUDE_BIN;
    else process.env.CLAUDE_BIN = ORIGINAL_CLAUDE_BIN;
  });

  // /proc is only trusted to say "gone" when it demonstrably shows THIS pid namespace
  // (a bind-mounted foreign /proc can still resolve /proc/self).
  const procIsOurs = (): boolean => {
    try {
      return readFileSync("/proc/self/stat", "utf8").startsWith(`${process.pid} `);
    } catch {
      return false;
    }
  };

  const isAlive = (pid: number): boolean => {
    try {
      process.kill(pid, 0);
    } catch (e) {
      // EPERM = exists but not ours = alive; only ESRCH means gone.
      lastProbe = `kill(0) ${errCode(e)}`;
      return errCode(e) === "EPERM";
    }
    let stat: string;
    try {
      stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    } catch (e) {
      // The pid can vanish between kill(0) and this read (ENOENT, or ESRCH once open succeeded):
      // dead, provided /proc itself is readable. Any other failure (EACCES under hidepid, no
      // /proc off Linux) leaves kill(0) as the only signal: alive.
      const vanished = (errCode(e) === "ENOENT" || errCode(e) === "ESRCH") && procIsOurs();
      lastProbe = `stat read ${errCode(e)}`;
      return !vanished;
    }
    // comm may hold spaces and parens, so the state char is the one after the LAST ")".
    const close = stat.lastIndexOf(")");
    const state = close < 0 ? "" : stat.slice(close + 1).trim().charAt(0);
    lastProbe = `state ${state || "?"}`;
    // A zombie (killed, not yet reaped by init) is dead for this purpose.
    return state !== "Z" && state !== "X";
  };

  it("kills a SIGTERM-ignoring grandchild that shares the child's group once the child has exited", async () => {
    const actual = await vi.importActual<typeof import("node:child_process")>("node:child_process");
    spawnMock.mockImplementation(actual.spawn);
    const dir = mkdtempSync(join(tmpdir(), "claude-eval-group-"));
    dirs.push(dir);
    const pidFile = join(dir, "sleeper.pid");
    const bin = join(dir, "claude");
    writeFileSync(
      bin,
      [
        "#!/bin/sh",
        // Same process group as this script; ignores TERM/HUP; detached from the stdio pipes.
        `(trap '' TERM HUP; exec sleep 120) >/dev/null 2>&1 </dev/null &`,
        `echo $! > "${pidFile}"`,
        `printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","permission_denials":[]}'`,
        "exit 0",
        "",
      ].join("\n"),
      "utf-8",
    );
    chmodSync(bin, 0o755);
    process.env.CLAUDE_BIN = bin;
    const cwd = join(dir, "repo");
    mkdirSync(cwd);

    const res = await spawnClaudeEval({
      spawnCwd: cwd,
      installationToken: TOKEN,
      flags: ["--print"],
      prompt: "ignored",
      maxTurnDurationMs: 30_000,
      cronName: "cron-bug-fixer",
      buildSpawnEnv: () => process.env,
      logger: noopLogger,
    });
    expect(res.ok).toBe(true);
    expect(existsSync(pidFile), "the fixture must have started its sleeper").toBe(true);
    const pid = Number(readFileSync(pidFile, "utf8").trim());
    expect(Number.isInteger(pid) && pid > 1).toBe(true);
    sleeperPid = pid;
    // The SIGKILL is sent before the spawn resolves but lands asynchronously (measured under
    // load: the first post-exit probe usually still sees the sleeper alive), so poll. The 15s
    // bound is deliberately above the repo's 10s contended-CI waitFor floor (#5796).
    const t0 = Date.now();
    try {
      await vi.waitFor(
        () => {
          if (isAlive(pid)) throw new Error("grandchild still alive");
        },
        { timeout: 15_000, interval: 25 },
      );
    } catch (e) {
      // vi.waitFor rethrows the callback's last error on timeout; anything else is a probe bug.
      if (!(e instanceof Error) || e.message !== "grandchild still alive") throw e;
      expect.fail(
        `the grandchild survived the child's exit: the group kill did not reach it ` +
          `(pid ${pid}; last probe: ${lastProbe}; waited ${Date.now() - t0}ms; ` +
          `loadavg ${loadavg().map((n) => n.toFixed(1)).join("/")}; ${e instanceof Error ? e.message : String(e)}). ` +
          `If this recurs, paste this line on #9670 rather than opening a new issue.`,
      );
    }
    // Observed dead: do not let the reaper signal a pid the kernel may since have recycled.
    sleeperPid = null;
  }, 40_000);

  // Probe self-test, not the product: negative controls for `isAlive`. The row above only ever
  // watches it answer "gone", so an always-false oracle, an `S`-is-dead oracle or a Z-blind
  // oracle would pass it with the product kill removed; a first-paren parser would misread any
  // comm containing ")", which only the second row below exercises. A live, unkilled process
  // must read alive (the second name carries a ")" and a fake zombie state), the same pid must
  // read dead once killed, and a zombie that is NOT reaped must read dead while kill(0) still
  // succeeds.
  describe("isAlive oracle controls", () => {
    const SLEEP_BIN = ["/bin/sleep", "/usr/bin/sleep"].find((c) => existsSync(c));
    // Only a standalone sleep binary can be copied under another name (a multicall binary
    // such as busybox would reject the unknown applet name).
    const hasProc = existsSync("/proc/self/stat");
    const canCopySleep = SLEEP_BIN !== undefined && basename(realpathSync(SLEEP_BIN)) === "sleep" && hasProc;
    const spawnReal = async (...args: Parameters<typeof import("node:child_process").spawn>) => {
      const actual = await vi.importActual<typeof import("node:child_process")>("node:child_process");
      const child = actual.spawn(...args);
      child.on("error", () => {}); // a failed exec must surface as the pid assertion, not an uncaught error
      return child;
    };

    for (const name of ["sleep", "x) Z y"]) {
      it.skipIf(!canCopySleep)(
        `a live process reads alive and a killed one dead (comm "${name}")`,
        async () => {
          const dir = mkdtempSync(join(tmpdir(), "claude-eval-probe-"));
          dirs.push(dir);
          const exe = join(dir, name);
          copyFileSync(SLEEP_BIN as string, exe);
          chmodSync(exe, 0o755);
          const child = await spawnReal(exe, ["120"], { stdio: "ignore" });
          try {
            const pid = child.pid as number;
            expect(Number.isInteger(pid) && pid > 1).toBe(true);
            // comm is the copy's name only once exec has replaced the forked parent.
            await vi.waitFor(() => expect(readFileSync(`/proc/${pid}/stat`, "utf8")).toContain(`(${name})`), {
              timeout: 5_000,
              interval: 10,
            });
            // Right after exec the state can be transiently D or R; wait for it to settle to sleeping.
            await vi.waitFor(
              () => {
                expect(isAlive(pid), `a live process must read alive (last probe: ${lastProbe})`).toBe(true);
                expect(lastProbe).toBe("state S");
              },
              { timeout: 5_000, interval: 10 },
            );
            child.kill("SIGKILL");
            await vi.waitFor(
              () => expect(isAlive(pid), `a killed process must read dead (last probe: ${lastProbe})`).toBe(false),
              { timeout: 5_000, interval: 10 },
            );
          } finally {
            child.kill("SIGKILL");
          }
        },
        30_000,
      );
    }

    // The /proc half of the probe: a killed grandchild whose parent never waits stays a zombie, for
    // which kill(0) still succeeds (containers without a reaping init look like this).
    it.skipIf(!hasProc)(
      "an unreaped zombie reads dead while kill(0) still succeeds",
      async () => {
        // The child must exit only AFTER the shell has exec'd into `sleep` (whose comm then reads
        // "sleep"); a child that exits earlier is reaped by the shell itself and no zombie forms.
        // The wait uses builtins only, so it forks nothing while it spins.
        const script = 'p=$$; ( until { read -r c < /proc/$p/comm; [ "$c" = sleep ]; }; do :; done ) & echo $!; exec sleep 120';
        const parent = await spawnReal("sh", ["-c", script], {
          stdio: ["ignore", "pipe", "ignore"],
        });
        try {
          let out = "";
          parent.stdout?.on("data", (d: Buffer) => (out += d.toString()));
          await vi.waitFor(() => expect(out).toMatch(/^\d+\n/), { timeout: 5_000, interval: 10 });
          const zpid = Number(out.trim());
          expect(Number.isInteger(zpid) && zpid > 1).toBe(true);
          await vi.waitFor(() => expect(readFileSync(`/proc/${zpid}/stat`, "utf8")).toMatch(/\) Z /), {
            timeout: 5_000,
            interval: 10,
          });
          expect(() => process.kill(zpid, 0), "a zombie still answers kill(0)").not.toThrow();
          expect(isAlive(zpid), `a zombie must read dead (last probe: ${lastProbe})`).toBe(false);
          expect(lastProbe).toBe("state Z");
        } finally {
          parent.kill("SIGKILL");
        }
      },
      30_000,
    );
  });
});
