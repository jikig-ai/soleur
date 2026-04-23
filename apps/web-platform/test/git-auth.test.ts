// Tests for the GIT_ASKPASS-based authenticated git invocation helper
// (server/git-auth.ts). Closes the "could not read Username" class of
// production failures caused by the old `credential.helper=!<path>` pattern.
//
// Set env BEFORE any imports — the helper reads HOME at module load.
process.env.HOME = process.env.HOME || "/tmp";

import { describe, test, expect, afterEach, beforeEach, vi } from "vitest";
import { existsSync, statSync, readFileSync } from "fs";
import { randomUUID } from "crypto";

type ExecFileCallback = (
  err: Error | null,
  result: { stdout: Buffer; stderr: Buffer },
) => void;

type ExecFileMockArgs = {
  cmd: string;
  args: string[];
  opts: { env?: NodeJS.ProcessEnv; cwd?: string; timeout?: number } | undefined;
  cb: ExecFileCallback;
};

/**
 * Install an execFile mock on node's child_process module. Each call is
 * recorded in `capturedCalls`; `behavior` is invoked after recording so
 * individual tests can customize success/failure.
 */
function mockExecFile(
  capturedCalls: ExecFileMockArgs[],
  behavior: "success" | ((args: ExecFileMockArgs) => void) = "success",
) {
  vi.doMock("child_process", async () => {
    const actual =
      await vi.importActual<typeof import("child_process")>("child_process");
    return {
      ...actual,
      execFile: vi
        .fn()
        .mockImplementation(
          (
            cmd: string,
            args: string[],
            opts:
              | { env?: NodeJS.ProcessEnv; cwd?: string; timeout?: number }
              | undefined,
            cb: ExecFileCallback,
          ) => {
            const call = { cmd, args, opts, cb };
            capturedCalls.push(call);
            if (behavior === "success") {
              cb(null, { stdout: Buffer.from(""), stderr: Buffer.from("") });
            } else {
              behavior(call);
            }
          },
        ),
    };
  });
}

beforeEach(() => {
  vi.resetModules();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.doUnmock("child_process");
  vi.doUnmock("../server/github-app");
});

describe("writeAskpassScript", () => {
  test("writes script to $HOME, not /tmp", async () => {
    const { writeAskpassScript, cleanupAskpassScript } = await import(
      "../server/git-auth"
    );
    const scriptPath = writeAskpassScript();
    try {
      expect(scriptPath.startsWith(process.env.HOME!)).toBe(true);
      expect(scriptPath).not.toMatch(/^\/tmp\//);
      expect(existsSync(scriptPath)).toBe(true);
    } finally {
      cleanupAskpassScript(scriptPath);
    }
  });

  test("writes script with mode 0o700", async () => {
    const { writeAskpassScript, cleanupAskpassScript } = await import(
      "../server/git-auth"
    );
    const scriptPath = writeAskpassScript();
    try {
      const mode = statSync(scriptPath).mode & 0o777;
      expect(mode).toBe(0o700);
    } finally {
      cleanupAskpassScript(scriptPath);
    }
  });

  test("script body is byte-identical across invocations (no interpolation)", async () => {
    const { writeAskpassScript, cleanupAskpassScript } = await import(
      "../server/git-auth"
    );
    const p1 = writeAskpassScript();
    const p2 = writeAskpassScript();
    try {
      const body1 = readFileSync(p1, "utf8");
      const body2 = readFileSync(p2, "utf8");
      expect(body1).toBe(body2);
      // And the body must NOT contain any token-looking string
      expect(body1).not.toMatch(/ghs_/);
    } finally {
      cleanupAskpassScript(p1);
      cleanupAskpassScript(p2);
    }
  });

  test("script reads token from GIT_INSTALLATION_TOKEN env var", async () => {
    const { writeAskpassScript, cleanupAskpassScript } = await import(
      "../server/git-auth"
    );
    const scriptPath = writeAskpassScript();
    try {
      const body = readFileSync(scriptPath, "utf8");
      expect(body).toMatch(/GIT_INSTALLATION_TOKEN/);
      expect(body).toMatch(/GIT_USERNAME/);
      expect(body).toMatch(/Username/);
      expect(body).toMatch(/Password/);
    } finally {
      cleanupAskpassScript(scriptPath);
    }
  });
});

describe("cleanupAskpassScript", () => {
  test("unlinks the file", async () => {
    const { writeAskpassScript, cleanupAskpassScript } = await import(
      "../server/git-auth"
    );
    const scriptPath = writeAskpassScript();
    expect(existsSync(scriptPath)).toBe(true);
    cleanupAskpassScript(scriptPath);
    expect(existsSync(scriptPath)).toBe(false);
  });

  test("swallows ENOENT (best-effort)", async () => {
    const { cleanupAskpassScript } = await import("../server/git-auth");
    expect(() =>
      cleanupAskpassScript(`/tmp/does-not-exist-${randomUUID()}.sh`),
    ).not.toThrow();
  });
});

describe("gitWithInstallationAuth", () => {
  test("sets GIT_ASKPASS, GIT_TERMINAL_PROMPT=0, GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL=/dev/null in env", async () => {
    const fakeToken = "ghs_faketokenabcdefghijklmnopqrstuvwxyz";
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(fakeToken),
    }));

    const capturedCalls: ExecFileMockArgs[] = [];
    mockExecFile(capturedCalls);

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await gitWithInstallationAuth(
      ["clone", "https://github.com/foo/bar", "/tmp/x"],
      12345,
    );

    expect(capturedCalls.length).toBe(1);
    const env = capturedCalls[0].opts?.env!;
    expect(env.GIT_ASKPASS).toBeTruthy();
    expect(env.GIT_ASKPASS).toMatch(/askpass-.*\.sh$/);
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
    expect(env.GIT_TERMINAL_PROGRESS).toBe("0");
    expect(env.GIT_CONFIG_NOSYSTEM).toBe("1");
    expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null");
    expect(env.GIT_INSTALLATION_TOKEN).toBe(fakeToken);
    expect(env.GIT_USERNAME).toBe("x-access-token");
  });

  test("prepends -c credential.helper= to reset inherited helpers", async () => {
    const fakeToken = "ghs_faketokenabcdefghijklmnopqrstuvwxyz";
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(fakeToken),
    }));

    const capturedCalls: ExecFileMockArgs[] = [];
    mockExecFile(capturedCalls);

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await gitWithInstallationAuth(["push", "origin", "main"], 12345);

    expect(capturedCalls.length).toBe(1);
    const args = capturedCalls[0].args;
    // The FIRST flags must reset credential.helper BEFORE the user's args
    expect(args.slice(0, 2)).toEqual(["-c", "credential.helper="]);
    expect(args).toContain("push");
    expect(args).toContain("origin");
    expect(args).toContain("main");
  });

  test("token NEVER appears in execFile args array", async () => {
    const fakeToken = "ghs_faketokenabcdefghijklmnopqrstuvwxyz";
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(fakeToken),
    }));

    const capturedCalls: ExecFileMockArgs[] = [];
    mockExecFile(capturedCalls);

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await gitWithInstallationAuth(
      ["clone", "https://github.com/foo/bar", "/tmp/x"],
      12345,
    );

    for (const call of capturedCalls) {
      expect(call.args.join(" ")).not.toContain(fakeToken);
    }
  });

  test("cleans up askpass script even when git fails", async () => {
    const fakeToken = "ghs_faketokenabcdefghijklmnopqrstuvwxyz";
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(fakeToken),
    }));

    let capturedAskpassPath: string | undefined;
    mockExecFile([], (call) => {
      capturedAskpassPath = call.opts?.env?.GIT_ASKPASS;
      const err: Error & { stderr?: Buffer } = new Error("git exited 128");
      err.stderr = Buffer.from("fatal: boom");
      call.cb(err, { stdout: Buffer.from(""), stderr: err.stderr });
    });

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await expect(
      gitWithInstallationAuth(["clone", "x", "/tmp/x"], 12345),
    ).rejects.toThrow();

    expect(capturedAskpassPath).toBeTruthy();
    expect(existsSync(capturedAskpassPath!)).toBe(false);
  });

  test.each([
    "ghs_" + "a".repeat(30),
    "ghs_" + "a".repeat(40),
    "ghs_" + "a".repeat(128),
    "ghs_" + "ABCDEF_0123456789-abcdefghij",
  ])("permissive token validator accepts %s", async (tok) => {
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(tok),
    }));
    mockExecFile([]);

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await expect(
      gitWithInstallationAuth(["status"], 12345),
    ).resolves.toBeDefined();
  });

  test("token-format mismatch logs a warning but does NOT throw", async () => {
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue("not-a-ghs-token"),
    }));
    mockExecFile([]);

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await expect(
      gitWithInstallationAuth(["status"], 12345),
    ).resolves.toBeDefined();
  });

  test("passes through cwd and timeout options", async () => {
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi
        .fn()
        .mockResolvedValue("ghs_" + "a".repeat(40)),
    }));

    const capturedCalls: ExecFileMockArgs[] = [];
    mockExecFile(capturedCalls);

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await gitWithInstallationAuth(["status"], 12345, {
      cwd: "/tmp/x",
      timeout: 42_000,
    });

    expect(capturedCalls[0].opts).toMatchObject({
      cwd: "/tmp/x",
      timeout: 42_000,
    });
  });
});
