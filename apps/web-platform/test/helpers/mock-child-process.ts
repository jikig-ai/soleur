// Test seam for the reap: `deleteWorkspace` uses ASYNC `execFile` (it must not block the event
// loop) while the provision path uses `execFileSync`. One handler drives BOTH, so a fixture
// that makes `rm` fail fails it on either path.
//
// handler(cmd, args): throw to make the command FAIL, return "skip" to make it "succeed"
// without running, return a function to run it AFTER the real command, or return nothing to
// pass through to the real command.
import { vi } from "vitest";

export type CpAction = void | "skip" | (() => void);

/** The module factory itself, for a hoisted `vi.mock("child_process", ...)`. */
export async function mockChildProcessFactory(handler: (cmd: string, args: string[]) => CpAction) {
  const actual = await vi.importActual<typeof import("child_process")>("child_process");
  const pre = (cmd: string, args: string[]) => {
    const a = handler(cmd, args);
    return { skip: a === "skip", post: typeof a === "function" ? a : undefined };
  };
  return {
    ...actual,
    execFileSync: (cmd: string, args: string[], ...rest: unknown[]) => {
      const p = pre(cmd, args);
      const out = p.skip ? Buffer.alloc(0) : (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, ...rest);
      p.post?.();
      return out;
    },
    execFile: (cmd: string, args: string[], opts: unknown, cb: (...a: unknown[]) => void) => {
      let p: ReturnType<typeof pre>;
      try {
        p = pre(cmd, args);
      } catch (e) {
        setImmediate(() => cb(e));
        return undefined;
      }
      if (p.skip) {
        setImmediate(() => cb(null, "", ""));
        return undefined;
      }
      return (actual.execFile as (...x: unknown[]) => unknown)(cmd, args, opts, (...r: unknown[]) => {
        cb(...r);
        p.post?.();
      });
    },
  };
}

export function mockChildProcess(handler: (cmd: string, args: string[]) => CpAction): void {
  vi.doMock("child_process", () => mockChildProcessFactory(handler));
}
