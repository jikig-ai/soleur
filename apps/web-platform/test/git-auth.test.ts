// Tests for the GIT_ASKPASS-based authenticated git invocation helper
// (server/git-auth.ts). Closes the "could not read Username" class of
// production failures caused by the old `credential.helper=!<path>` pattern.
//
// Set env BEFORE any imports — the helper reads HOME at module load.
process.env.HOME = process.env.HOME || "/tmp";

import { describe, test, expect, afterEach, beforeEach, vi } from "vitest";
import {
  existsSync,
  statSync,
  readFileSync,
  openSync,
  fstatSync,
  closeSync,
} from "fs";
import { randomUUID } from "crypto";
import { makeEd25519Pin, TOFU_OPT } from "./helpers/ssh-host-key-fixture";

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

describe("writeAskpassScriptTo (item 1b — in-sandbox askpass under workspacePath)", () => {
  test("writes a 0o700 script under the given dir, byte-identical body, no token", async () => {
    const { writeAskpassScriptTo, writeAskpassScript, cleanupAskpassScript } =
      await import("../server/git-auth");
    const dir = process.env.HOME!;
    const scriptPath = writeAskpassScriptTo(dir);
    // A reference body produced by the existing $HOME writer — proves the
    // body is single-sourced (drift-free) between the two writers.
    const refPath = writeAskpassScript();
    // Open the written file ONCE and stat+read the same file DESCRIPTOR (not
    // the path). A path-based check→use pair — existsSync(path) or
    // statSync(path) followed by readFileSync(path) — is a CodeQL
    // js/file-system-race (TOCTOU) alert, because the path could be swapped
    // between the two syscalls. fd-based fstatSync + readFileSync(fd) cannot
    // re-resolve the path, so there is no race window.
    let fd: number | undefined;
    try {
      expect(scriptPath.startsWith(dir)).toBe(true);
      // dot-prefixed so it is unobtrusive in a working tree.
      expect(scriptPath).toMatch(/\.askpass-.*\.sh$/);
      fd = openSync(scriptPath, "r");
      expect(fstatSync(fd).mode & 0o777).toBe(0o700);
      const body = readFileSync(fd, "utf8");
      // Body byte-identical to the canonical writer (proves delegation /
      // single-source). refPath is read with a single fs op (no prior check),
      // so it is not a TOCTOU pair.
      expect(body).toBe(readFileSync(refPath, "utf8"));
      // Real drift guard (RED-capable): assert the load-bearing askpass lines
      // literally, so a future edit to the printf logic actually fails rather
      // than passing a same-constant tautology.
      expect(body).toContain("#!/bin/sh");
      expect(body).toMatch(/Username\*\).*GIT_USERNAME:-x-access-token/);
      expect(body).toMatch(/Password\*\).*GIT_INSTALLATION_TOKEN/);
      // The token is read from env at runtime — NEVER interpolated into the
      // file (brand-survival: no token in the helper body).
      expect(body).not.toMatch(/ghs_/);
    } finally {
      if (fd !== undefined) closeSync(fd);
      cleanupAskpassScript(scriptPath);
      cleanupAskpassScript(refPath);
    }
  });

  test("two invocations write distinct paths (randomUUID suffix) with identical bodies", async () => {
    const { writeAskpassScriptTo, cleanupAskpassScript } = await import(
      "../server/git-auth"
    );
    const dir = process.env.HOME!;
    const p1 = writeAskpassScriptTo(dir);
    const p2 = writeAskpassScriptTo(dir);
    try {
      expect(p1).not.toBe(p2);
      expect(readFileSync(p1, "utf8")).toBe(readFileSync(p2, "utf8"));
    } finally {
      cleanupAskpassScript(p1);
      cleanupAskpassScript(p2);
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

describe("gitWithPrivateKeyAuth (git-data private-net SSH transport, #5274 Phase 2)", () => {
  const KEY =
    "-----BEGIN OPENSSH PRIVATE KEY-----\nc3ludGhldGljLXRlc3Qta2V5\n-----END OPENSSH PRIVATE KEY-----";

  test("delivers the key via GIT_SSH_COMMAND -i (NEVER argv) with the Phase-2 TOFU options; cleans up after", async () => {
    const capturedCalls: ExecFileMockArgs[] = [];
    let keyPathDuringCall = "";
    let keyModeDuringCall = 0;
    let keyContentDuringCall = "";
    // Inspect the on-disk key file WHILE git is "running" (before finally unlinks it).
    mockExecFile(capturedCalls, (call) => {
      const sshCmd = call.opts?.env?.GIT_SSH_COMMAND ?? "";
      const m = sshCmd.match(/ -i (\S+) /);
      if (m) {
        keyPathDuringCall = m[1];
        // Open ONCE and stat+read the same descriptor (not the path) — a
        // statSync(path)+readFileSync(path) pair is a CodeQL js/file-system-race
        // (TOCTOU) alert. Mirrors the $HOME askpass fd pattern above.
        const fd = openSync(keyPathDuringCall, "r");
        try {
          keyModeDuringCall = fstatSync(fd).mode & 0o777;
          keyContentDuringCall = readFileSync(fd, "utf8");
        } finally {
          closeSync(fd);
        }
      }
      call.cb(null, { stdout: Buffer.from("ok"), stderr: Buffer.from("") });
    });

    const { gitWithPrivateKeyAuth } = await import("../server/git-auth");
    const out = await gitWithPrivateKeyAuth(
      ["push", "git-data", "--push-option=lease-gen=3"],
      KEY,
      null,
      { cwd: "/tmp/ws", timeout: 60_000 },
    );
    expect(out.toString()).toBe("ok");

    const env = capturedCalls[0].opts?.env ?? ({} as NodeJS.ProcessEnv);
    const sshCommand = env.GIT_SSH_COMMAND ?? "";
    // null pin → the transitional TOFU fallback arm (#5914 deletes it).
    expect(sshCommand).toMatch(/^ssh -i \S+ /);
    expect(sshCommand).toContain("IdentitiesOnly=yes");
    expect(sshCommand).toContain(TOFU_OPT);
    expect(sshCommand).not.toContain("HostKeyAlias=");
    expect(sshCommand).toContain("UserKnownHostsFile=");
    expect(sshCommand).toContain("BatchMode=yes");
    // Prompt-free + no system/global gitconfig leak (mirror the askpass path).
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
    expect(env.GIT_CONFIG_NOSYSTEM).toBe("1");
    expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null");
    // HELPER_RESET is prepended.
    expect(capturedCalls[0].args.slice(0, 2)).toEqual(["-c", "credential.helper="]);

    // The key material is on disk 0600 during the call, with the real key bytes,
    // and is removed afterward.
    expect(keyModeDuringCall).toBe(0o600);
    expect(keyContentDuringCall).toContain("BEGIN OPENSSH PRIVATE KEY");
    expect(existsSync(keyPathDuringCall)).toBe(false); // cleaned up in finally

    // The key NEVER appears in argv (only via the env-referenced file).
    const argvJoined = capturedCalls[0].args.join(" ");
    expect(argvJoined).not.toContain("BEGIN OPENSSH PRIVATE KEY");
    expect(argvJoined).not.toContain(keyPathDuringCall);
  });

  test("cleans up the key file even when git fails, and does not leak key material in the throw", async () => {
    const capturedCalls: ExecFileMockArgs[] = [];
    let keyPathDuringCall = "";
    mockExecFile(capturedCalls, (call) => {
      const m = (call.opts?.env?.GIT_SSH_COMMAND ?? "").match(/ -i (\S+) /);
      if (m) keyPathDuringCall = m[1];
      call.cb(
        Object.assign(new Error("fatal: Permission denied (publickey)"), {
          code: 128,
        }),
        { stdout: Buffer.from(""), stderr: Buffer.from("publickey") },
      );
    });

    const { gitWithPrivateKeyAuth } = await import("../server/git-auth");
    await expect(
      gitWithPrivateKeyAuth(["ls-remote", "git-data"], KEY, null),
    ).rejects.toThrow(/Permission denied|publickey/);
    expect(keyPathDuringCall).not.toBe("");
    expect(existsSync(keyPathDuringCall)).toBe(false); // finally still ran
  });
});

describe("sshWithPrivateKeyAuth (git-data provision forced-command, #5817)", () => {
  const KEY =
    "-----BEGIN OPENSSH PRIVATE KEY-----\nc3ludGhldGljLXByb3Zpc2lvbg==\n-----END OPENSSH PRIVATE KEY-----";

  test("invokes ssh with -i keyfile (0600, real bytes, cleaned up), TOFU opts, and the workspace_id as the sole opaque remote arg", async () => {
    const capturedCalls: ExecFileMockArgs[] = [];
    let keyPathDuringCall = "";
    let keyModeDuringCall = 0;
    let keyContentDuringCall = "";
    mockExecFile(capturedCalls, (call) => {
      const iIdx = call.args.indexOf("-i");
      if (iIdx >= 0) {
        keyPathDuringCall = call.args[iIdx + 1];
        const fd = openSync(keyPathDuringCall, "r");
        try {
          keyModeDuringCall = fstatSync(fd).mode & 0o777;
          keyContentDuringCall = readFileSync(fd, "utf8");
        } finally {
          closeSync(fd);
        }
      }
      call.cb(null, { stdout: Buffer.from("ok"), stderr: Buffer.from("") });
    });

    const { sshWithPrivateKeyAuth } = await import("../server/git-auth");
    const out = await sshWithPrivateKeyAuth("10.0.1.20", "ws-uuid-123", KEY, null, {
      timeout: 30_000,
    });
    expect(out.toString()).toBe("ok");

    const args = capturedCalls[0].args;
    expect(capturedCalls[0].cmd).toBe("ssh");
    // TOFU / batch options.
    expect(args).toContain("IdentitiesOnly=yes");
    expect(args).toContain(TOFU_OPT);
    expect(args.some((a) => a.startsWith("HostKeyAlias="))).toBe(false);
    expect(args.some((a) => a.startsWith("UserKnownHostsFile="))).toBe(true);
    expect(args).toContain("BatchMode=yes");
    // The destination + the SINGLE opaque remote arg (→ SSH_ORIGINAL_COMMAND).
    expect(args).toContain("git@10.0.1.20");
    expect(args[args.length - 1]).toBe("ws-uuid-123");

    // Key material on disk 0600 during the call; never in argv; removed after.
    expect(keyModeDuringCall).toBe(0o600);
    expect(keyContentDuringCall).toContain("BEGIN OPENSSH PRIVATE KEY");
    expect(existsSync(keyPathDuringCall)).toBe(false);
    expect(args.join(" ")).not.toContain("BEGIN OPENSSH PRIVATE KEY");
  });

  test("cleans up the key file even when ssh fails", async () => {
    const capturedCalls: ExecFileMockArgs[] = [];
    let keyPathDuringCall = "";
    mockExecFile(capturedCalls, (call) => {
      const iIdx = call.args.indexOf("-i");
      if (iIdx >= 0) keyPathDuringCall = call.args[iIdx + 1];
      call.cb(
        Object.assign(new Error("ssh: connect to host failed"), { code: 255 }),
        { stdout: Buffer.from(""), stderr: Buffer.from("") },
      );
    });

    const { sshWithPrivateKeyAuth } = await import("../server/git-auth");
    await expect(
      sshWithPrivateKeyAuth("10.0.1.20", "ws-uuid-123", KEY, null),
    ).rejects.toThrow(/connect to host failed/);
    expect(keyPathDuringCall).not.toBe("");
    expect(existsSync(keyPathDuringCall)).toBe(false);
  });
});

// ---------------------------------------------------------------------------------
// #7226 / #5914 Guard 5 — the app transport is PINNED whenever a pin exists.
//
// known_hosts is read INSIDE the mocked execFile: the helper unlinks it in `finally`,
// so reading it afterwards proves nothing (and would pass with any content).
// ---------------------------------------------------------------------------------
describe("git-data host-key pinning (Guard 5, #7226)", () => {
  const KEY =
    "-----BEGIN OPENSSH PRIVATE KEY-----\nc3ludGhldGljLXBpbm5pbmc=\n-----END OPENSSH PRIVATE KEY-----";

  const PINNED_OPTS = [
    "StrictHostKeyChecking=yes",
    "HostKeyAlias=git-data",
    "HostKeyAlgorithms=ssh-ed25519",
    "UpdateHostKeys=no",
    "GlobalKnownHostsFile=/dev/null",
    "BatchMode=yes",
    "IdentitiesOnly=yes",
  ];

  function readKnownHosts(path: string): { content: string; mode: number } {
    const fd = openSync(path, "r");
    try {
      return { mode: fstatSync(fd).mode & 0o777, content: readFileSync(fd, "utf8") };
    } finally {
      closeSync(fd);
    }
  }

  test("sshWithPrivateKeyAuth: pinned argv + known_hosts is exactly `git-data <pin>\\n` (0600) during the call", async () => {
    const pin = makeEd25519Pin();
    const capturedCalls: ExecFileMockArgs[] = [];
    let kh = { content: "", mode: 0 };
    let khPath = "";
    mockExecFile(capturedCalls, (call) => {
      const opt = call.args.find((a) => a.startsWith("UserKnownHostsFile="));
      khPath = opt ? opt.slice("UserKnownHostsFile=".length) : "";
      kh = readKnownHosts(khPath);
      call.cb(null, { stdout: Buffer.from("ok"), stderr: Buffer.from("") });
    });

    const { sshWithPrivateKeyAuth } = await import("../server/git-auth");
    await sshWithPrivateKeyAuth("10.0.1.20", "ws-uuid-123", KEY, pin, { timeout: 30_000 });

    const args = capturedCalls[0].args;
    expect(kh.content).toBe(`git-data ${pin}\n`);
    expect(kh.mode).toBe(0o600);
    // -F /dev/null: no user/system ssh_config can add a trust source or reroute.
    const fIdx = args.indexOf("-F");
    expect(fIdx).toBeGreaterThanOrEqual(0);
    expect(args[fIdx + 1]).toBe("/dev/null");
    for (const o of PINNED_OPTS) expect(args).toContain(o);
    expect(args).not.toContain(TOFU_OPT);
    expect(args.some((a) => /UserKnownHostsFile=\/dev\/null/.test(a))).toBe(false);
    // Options precede the destination; the opaque arg stays last.
    // LogLevel=ERROR would hide ssh's "no matching host key type found" (reason=alg).
    expect(args.some((a) => /^LogLevel=/i.test(a))).toBe(false);
    expect(args.indexOf("git@10.0.1.20")).toBeGreaterThan(
      args.indexOf("GlobalKnownHostsFile=/dev/null"),
    );
    expect(args[args.length - 1]).toBe("ws-uuid-123");
    expect(existsSync(khPath)).toBe(false); // cleaned up
  });

  test("gitWithPrivateKeyAuth: the SAME pinned arm (mutation 3 — pinned in one helper only is RED)", async () => {
    const pin = makeEd25519Pin();
    const capturedCalls: ExecFileMockArgs[] = [];
    let kh = { content: "", mode: 0 };
    let khPath = "";
    mockExecFile(capturedCalls, (call) => {
      const sshCmd = call.opts?.env?.GIT_SSH_COMMAND ?? "";
      const m = sshCmd.match(/UserKnownHostsFile=(\S+)/);
      khPath = m ? m[1] : "";
      kh = readKnownHosts(khPath);
      call.cb(null, { stdout: Buffer.from("ok"), stderr: Buffer.from("") });
    });

    const { gitWithPrivateKeyAuth } = await import("../server/git-auth");
    await gitWithPrivateKeyAuth(["fetch", "ssh://git@10.0.1.20/repositories/x.git"], KEY, pin);

    const sshCommand = capturedCalls[0].opts?.env?.GIT_SSH_COMMAND ?? "";
    expect(kh.content).toBe(`git-data ${pin}\n`);
    expect(kh.mode).toBe(0o600);
    expect(sshCommand).toMatch(/(^| )-F \/dev\/null( |$)/);
    for (const o of PINNED_OPTS) expect(sshCommand).toContain(o);
    expect(sshCommand).not.toContain(TOFU_OPT);
    // The pin itself never rides the command line — only the file.
    expect(sshCommand).not.toContain(pin.split(" ")[1]);
    expect(existsSync(khPath)).toBe(false);
  });

  test("known_hosts is keyed by the alias, never by the address (mutation 4)", async () => {
    const pin = makeEd25519Pin();
    const capturedCalls: ExecFileMockArgs[] = [];
    let content = "";
    mockExecFile(capturedCalls, (call) => {
      const opt = call.args.find((a) => a.startsWith("UserKnownHostsFile="))!;
      content = readKnownHosts(opt.slice("UserKnownHostsFile=".length)).content;
      call.cb(null, { stdout: Buffer.from(""), stderr: Buffer.from("") });
    });
    const { sshWithPrivateKeyAuth } = await import("../server/git-auth");
    await sshWithPrivateKeyAuth("10.0.1.20", "ws", KEY, pin);
    expect(content.startsWith("git-data ")).toBe(true);
    expect(content).not.toContain("10.0.1.20");
  });

  test("null pin: the fallback arm writes an EMPTY known_hosts and carries no alias", async () => {
    const capturedCalls: ExecFileMockArgs[] = [];
    let content = "unset";
    mockExecFile(capturedCalls, (call) => {
      const opt = call.args.find((a) => a.startsWith("UserKnownHostsFile="))!;
      content = readKnownHosts(opt.slice("UserKnownHostsFile=".length)).content;
      call.cb(null, { stdout: Buffer.from(""), stderr: Buffer.from("") });
    });
    const { sshWithPrivateKeyAuth } = await import("../server/git-auth");
    await sshWithPrivateKeyAuth("10.0.1.20", "ws", KEY, null);
    expect(content).toBe("");
    expect(capturedCalls[0].args).toContain(TOFU_OPT);
    expect(capturedCalls[0].args).not.toContain("StrictHostKeyChecking=yes");
  });

  test("a pin carrying a newline is refused before any exec (known_hosts line injection)", async () => {
    const pin = makeEd25519Pin();
    const capturedCalls: ExecFileMockArgs[] = [];
    mockExecFile(capturedCalls);
    const { sshWithPrivateKeyAuth, gitWithPrivateKeyAuth } = await import("../server/git-auth");
    const evil = `${pin}\n@cert-authority * ssh-ed25519 AAAA`;
    await expect(sshWithPrivateKeyAuth("10.0.1.20", "ws", KEY, evil)).rejects.toThrow(/host-key pin/i);
    await expect(gitWithPrivateKeyAuth(["fetch", "x"], KEY, evil)).rejects.toThrow(/host-key pin/i);
    expect(capturedCalls).toHaveLength(0);
  });

  test("git-auth.ts carries the unpinned TOFU literal exactly once (Guard 1 allow-list count)", () => {
    const src = readFileSync(new URL("../server/git-auth.ts", import.meta.url), "utf8");
    const needle = "accept" + "-new";
    expect(src.split(needle).length - 1).toBe(1);
    expect(src).toMatch(new RegExp(`const TOFU_FALLBACK_OPTS[^\\n]*\\n?[^\\n]*${needle}`));
  });
});
