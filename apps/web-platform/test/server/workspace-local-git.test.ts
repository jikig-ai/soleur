// #12600 (CTO ruling D21): the token-free workspace runner is the ONE local-git runner for the workspace self-heal and
// the session-start overlay (server/ensure-workspace-repo.ts used to carry a twin). A timed-out git is killed with
// SIGKILL, so a planted filter that traps SIGTERM cannot outlive the bound. Synthesized data only.
import { beforeEach, describe, expect, test, vi } from "vitest";

const { execFileMock } = vi.hoisted(() => ({ execFileMock: vi.fn() }));

vi.mock("node:child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("node:child_process")>()),
  execFile: execFileMock,
}));

import { runWorkspaceLocalGit } from "@/server/workspace-local-git";
import { ALLOW_PROTOCOL_NONE } from "@/server/host-git";

beforeEach(() => {
  execFileMock.mockReset();
  // promisify(execFile) on a plain function resolves the callback's value argument
  execFileMock.mockImplementation((_file: string, _args: string[], _opts: unknown, cb: (e: null, v: unknown) => void) =>
    cb(null, { stdout: Buffer.from("ok\n"), stderr: Buffer.from("") }),
  );
});

describe("runWorkspaceLocalGit", () => {
  test("runs host git with the scrubbed env, the caller's bound, SIGKILL on timeout and buffer output", async () => {
    const out = await runWorkspaceLocalGit(["rev-parse", "HEAD"], { cwd: "/tmp/ws-local-git", timeout: 1234 });
    expect(out.toString()).toBe("ok\n");
    expect(execFileMock).toHaveBeenCalledTimes(1);
    const [file, args, opts] = execFileMock.mock.calls[0] as [string, string[], Record<string, unknown>];
    expect(file).toBe("git");
    expect(args.slice(-2)).toEqual(["rev-parse", "HEAD"]);
    expect(opts).toEqual(expect.objectContaining({ cwd: "/tmp/ws-local-git", timeout: 1234, killSignal: "SIGKILL", encoding: "buffer" }));
    const env = opts.env as Record<string, string>;
    expect(env.GIT_ALLOW_PROTOCOL).toBe(ALLOW_PROTOCOL_NONE);
    expect(Object.keys(env).filter((k) => /TOKEN|ASKPASS/i.test(k))).toEqual([]);
  });
});
