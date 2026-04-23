// Tests for the GIT_ASKPASS-based authenticated git invocation helper
// (server/git-auth.ts). Closes the "could not read Username" class of
// production failures caused by the old `credential.helper=!<path>` pattern.
//
// Set env BEFORE any imports — the helper reads HOME at module load.
process.env.HOME = process.env.HOME || "/tmp";

import { describe, test, expect, afterEach, beforeEach, vi } from "vitest";
import { existsSync, statSync, readFileSync, unlinkSync } from "fs";
import { randomUUID } from "crypto";

beforeEach(() => {
  vi.resetModules();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.doUnmock("child_process");
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
  test("sets GIT_ASKPASS, GIT_TERMINAL_PROMPT=0, and GIT_CONFIG_NOSYSTEM=1 in env", async () => {
    const fakeToken = "ghs_faketokenabcdefghijklmnopqrstuvwxyz";
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(fakeToken),
    }));

    const capturedCalls: Array<{ args: string[]; env?: NodeJS.ProcessEnv }> = [];
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>(
        "child_process",
      );
      return {
        ...actual,
        execFileSync: vi.fn().mockImplementation(
          (cmd: string, args: string[], opts?: { env?: NodeJS.ProcessEnv }) => {
            capturedCalls.push({ args, env: opts?.env });
            return Buffer.from("");
          },
        ),
      };
    });

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await gitWithInstallationAuth(["clone", "https://github.com/foo/bar", "/tmp/x"], 12345);

    expect(capturedCalls.length).toBe(1);
    const env = capturedCalls[0].env!;
    expect(env.GIT_ASKPASS).toBeTruthy();
    expect(env.GIT_ASKPASS).toMatch(/askpass-.*\.sh$/);
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
    expect(env.GIT_TERMINAL_PROGRESS).toBe("0");
    expect(env.GIT_CONFIG_NOSYSTEM).toBe("1");
    expect(env.GIT_INSTALLATION_TOKEN).toBe(fakeToken);
    expect(env.GIT_USERNAME).toBe("x-access-token");
  });

  test("prepends -c credential.helper= to reset inherited helpers", async () => {
    const fakeToken = "ghs_faketokenabcdefghijklmnopqrstuvwxyz";
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(fakeToken),
    }));

    const capturedArgs: string[][] = [];
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>(
        "child_process",
      );
      return {
        ...actual,
        execFileSync: vi.fn().mockImplementation((cmd: string, args: string[]) => {
          capturedArgs.push(args);
          return Buffer.from("");
        }),
      };
    });

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await gitWithInstallationAuth(["push", "origin", "main"], 12345);

    expect(capturedArgs.length).toBe(1);
    const args = capturedArgs[0];
    // The FIRST flags must reset credential.helper BEFORE the user's args
    expect(args.slice(0, 4)).toEqual([
      "-c", "credential.helper=",
      "-c", 'credential.helper=""',
    ]);
    // The user's git subcommand follows
    expect(args).toContain("push");
    expect(args).toContain("origin");
    expect(args).toContain("main");
  });

  test("token NEVER appears in execFileSync args array", async () => {
    const fakeToken = "ghs_faketokenabcdefghijklmnopqrstuvwxyz";
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(fakeToken),
    }));

    const capturedArgs: string[][] = [];
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>(
        "child_process",
      );
      return {
        ...actual,
        execFileSync: vi.fn().mockImplementation((cmd: string, args: string[]) => {
          capturedArgs.push(args);
          return Buffer.from("");
        }),
      };
    });

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await gitWithInstallationAuth(["clone", "https://github.com/foo/bar", "/tmp/x"], 12345);

    for (const args of capturedArgs) {
      expect(args.join(" ")).not.toContain(fakeToken);
    }
  });

  test("cleans up askpass script even when git fails", async () => {
    const fakeToken = "ghs_faketokenabcdefghijklmnopqrstuvwxyz";
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue(fakeToken),
    }));

    let capturedAskpassPath: string | undefined;
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>(
        "child_process",
      );
      return {
        ...actual,
        execFileSync: vi.fn().mockImplementation(
          (_cmd: string, _args: string[], opts?: { env?: NodeJS.ProcessEnv }) => {
            capturedAskpassPath = opts?.env?.GIT_ASKPASS;
            const err: Error & { stderr?: Buffer } = new Error("git exited 128");
            err.stderr = Buffer.from("fatal: boom");
            throw err;
          },
        ),
      };
    });

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await expect(
      gitWithInstallationAuth(["clone", "x", "/tmp/x"], 12345),
    ).rejects.toThrow();

    expect(capturedAskpassPath).toBeTruthy();
    expect(existsSync(capturedAskpassPath!)).toBe(false);
  });

  test("permissive token validator accepts ghs_ tokens in the 30-128 char range", async () => {
    // Short token (30 chars post-prefix is the lower bound). The helper must
    // not throw on short-but-plausible tokens — GitHub has not documented
    // the exact format, so a strict check is a latent outage class.
    const validTokens = [
      "ghs_" + "a".repeat(30),
      "ghs_" + "a".repeat(40),
      "ghs_" + "a".repeat(128),
      "ghs_" + "ABCDEF_0123456789-abcdefghij", // 30 chars, charset mix
    ];

    for (const tok of validTokens) {
      vi.doMock("../server/github-app", () => ({
        generateInstallationToken: vi.fn().mockResolvedValue(tok),
      }));
      vi.doMock("child_process", async () => {
        const actual = await vi.importActual<typeof import("child_process")>(
          "child_process",
        );
        return {
          ...actual,
          execFileSync: vi.fn().mockReturnValue(Buffer.from("")),
        };
      });
      const { gitWithInstallationAuth } = await import("../server/git-auth");
      await expect(
        gitWithInstallationAuth(["status"], 12345),
      ).resolves.toBeDefined();
      vi.resetModules();
      vi.doUnmock("../server/github-app");
      vi.doUnmock("child_process");
    }
  });

  test("token-format mismatch logs a warning but does NOT throw", async () => {
    // A malformed token must not convert a GitHub format change into an
    // outage. The helper logs a warning and proceeds — git will fail fast
    // downstream if the token is actually bad.
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue("not-a-ghs-token"),
    }));
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>(
        "child_process",
      );
      return {
        ...actual,
        execFileSync: vi.fn().mockReturnValue(Buffer.from("")),
      };
    });

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

    const capturedOpts: Array<Record<string, unknown>> = [];
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>(
        "child_process",
      );
      return {
        ...actual,
        execFileSync: vi
          .fn()
          .mockImplementation(
            (
              _cmd: string,
              _args: string[],
              opts?: Record<string, unknown>,
            ) => {
              capturedOpts.push(opts ?? {});
              return Buffer.from("");
            },
          ),
      };
    });

    const { gitWithInstallationAuth } = await import("../server/git-auth");
    await gitWithInstallationAuth(["status"], 12345, {
      cwd: "/tmp/x",
      timeout: 42_000,
    });

    expect(capturedOpts[0]).toMatchObject({
      cwd: "/tmp/x",
      timeout: 42_000,
    });
  });
});
