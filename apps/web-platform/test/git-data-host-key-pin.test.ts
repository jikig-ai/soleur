// #7226 / #5914 — Guard 5 (the app's git-data transport is always pinned; an absent or
// malformed pin refuses, whatever the store flag says) and Guard 3 (pin shape), app side.
// Plans: knowledge-base/project/plans/2026-09-21-security-pin-web-1-and-git-data-ssh-host-keys-plan.md
// and 2026-09-28-feat-git-data-delete-unpinned-fallback-arm-5914-plan.md (host-key step 6).
//
// Every test re-imports the module under vi.resetModules() + vi.unstubAllEnvs(), so no
// test can inherit another's module state.
// Keys are generated per run (helpers/ssh-host-key-fixture.ts) — never a real host key.

import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { BAD_PIN_SHAPES, expectedFingerprint, makeEd25519Pin } from "./helpers/ssh-host-key-fixture";

const gitTransport = vi.fn();
const sshTransport = vi.fn();
const reportSilentFallback = vi.fn();
const logWarn = vi.fn();
const logInfo = vi.fn();
const rpcMock = vi.fn();
const execFileSyncMock = vi.fn((..._args: unknown[]) => Buffer.from(""));

vi.mock("../server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...args: unknown[]) => gitTransport(...args),
  sshWithPrivateKeyAuth: (...args: unknown[]) => sshTransport(...args),
}));
vi.mock("../server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/observability")>()),
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));
vi.mock("../server/logger", () => {
  const child = () => ({
    warn: (...a: unknown[]) => logWarn(...a),
    info: (...a: unknown[]) => logInfo(...a),
    error: vi.fn(),
    debug: vi.fn(),
    child,
  });
  return { createChildLogger: child, default: child() };
});
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: rpcMock })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("child_process")>()),
  execFileSync: (...args: unknown[]) => execFileSyncMock(...args),
}));

const WS = "ws-uuid-123";
const WT = "55555555-5555-5555-5555-555555555555";
const USER = "44444444-4444-4444-4444-444444444444";

async function load() {
  vi.resetModules();
  const repl = await import("../server/git-data-replication");
  const client = await import("../server/git-data-client");
  return { ...repl, fetchFromGitData: client.fetchFromGitData };
}

const sshErr = (code: number, stderr: string) =>
  Object.assign(new Error(`Command failed with exit code ${code}`), { code, stderr });

const pinReports = () =>
  reportSilentFallback.mock.calls.filter(
    (c) => (c[1] as { feature?: string }).feature === "git_data_host_key_pin",
  );

let PIN: string;

beforeEach(() => {
  vi.unstubAllEnvs();
  PIN = makeEd25519Pin();
  gitTransport.mockReset().mockResolvedValue(Buffer.from(""));
  sshTransport.mockReset().mockResolvedValue(Buffer.from(""));
  reportSilentFallback.mockReset();
  logWarn.mockReset();
  logInfo.mockReset();
  rpcMock.mockReset().mockResolvedValue({ data: true, error: null });
  execFileSyncMock.mockReset().mockReturnValue(Buffer.from(""));
  vi.stubEnv("GIT_DATA_STORE_ENABLED", "");
  vi.stubEnv("GIT_DATA_SSH_HOST_KEY", "");
  vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "remove-key");
  vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "provision-key");
  vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "transport-key");
  // Pinned so the shell's own value never leaks into the arming predicate (AC5b).
  vi.stubEnv("GIT_DATA_SSH_HOST", "");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("resolveGitDataHostKeyPin — Guard 3 shape + D4 absent semantics", () => {
  it("returns a valid ED25519 pin", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { resolveGitDataHostKeyPin } = await load();
    expect(resolveGitDataHostKeyPin()).toBe(PIN);
  });

  it("must-PASS: surrounding whitespace (incl. a trailing newline) is trimmed and accepted", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", `  ${PIN}\n`);
    const { resolveGitDataHostKeyPin } = await load();
    expect(resolveGitDataHostKeyPin()).toBe(PIN);
  });

  it.each(BAD_PIN_SHAPES)("wrong shape (%s) THROWS — and never echoes the raw value", async (_n, mk) => {
    const bad = mk(PIN);
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", bad);
    const { resolveGitDataHostKeyPin } = await load();
    let msg = "";
    try {
      resolveGitDataHostKeyPin();
    } catch (e) {
      msg = (e as Error).message;
    }
    expect(msg).toMatch(/GIT_DATA_SSH_HOST_KEY/);
    expect(msg).not.toContain(PIN.split(" ")[1].slice(0, 30));
  });

  it("absent + store ENABLED throws (mutation 2: returning null is RED)", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    const { resolveGitDataHostKeyPin } = await load();
    expect(() => resolveGitDataHostKeyPin()).toThrow(/GIT_DATA_SSH_HOST_KEY/);
    expect(pinReports()).toHaveLength(0);
  });

  it("absent + store ENABLED names the flag state `=true`", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    const { resolveGitDataHostKeyPin } = await load();
    expect(() => resolveGitDataHostKeyPin()).toThrow(/GIT_DATA_STORE_ENABLED=true/);
  });

  it("absent + store disabled THROWS too (#5914: no unpinned fallback), naming the flag state, with no report", async () => {
    const { resolveGitDataHostKeyPin } = await load();
    expect(() => resolveGitDataHostKeyPin()).toThrow(/GIT_DATA_SSH_HOST_KEY is unset/);
    expect(() => resolveGitDataHostKeyPin()).toThrow(/GIT_DATA_STORE_ENABLED is not true/);
    expect(pinReports()).toHaveLength(0);
  });
});

describe("removeGitDataRepo — guarded pin resolution + host_key_mismatch (Guard 5)", () => {
  it("a valid pin is handed to the ssh helper (mutation 1)", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { removeGitDataRepo } = await load();
    await expect(removeGitDataRepo(WS)).resolves.toEqual({ status: "erased" });
    expect(sshTransport).toHaveBeenCalledTimes(1);
    expect(sshTransport.mock.calls[0][3]).toBe(PIN);
  });

  it("an invalid pin returns `unconfigured` (NOT unreachable — mutation 6), does not throw, never dials", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", `${PIN} comment`);
    const { removeGitDataRepo } = await load();
    const outcome = await removeGitDataRepo(WS);
    expect(outcome.status).toBe("unconfigured");
    if (outcome.status !== "unconfigured") throw new Error("narrow");
    // Fixed reason word, distinct from `remove_key_absent` — different remedy.
    expect(outcome.detail).toMatch(/^pin_invalid: /);
    expect(outcome.detail).not.toContain(PIN.split(" ")[1].slice(0, 30));
    expect(sshTransport).not.toHaveBeenCalled();
  });

  it("store ENABLED + absent pin returns `unconfigured` and never dials", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    const { removeGitDataRepo } = await load();
    const outcome = await removeGitDataRepo(WS);
    expect(outcome.status).toBe("unconfigured");
    if (outcome.status !== "unconfigured") throw new Error("narrow");
    expect(outcome.detail).toMatch(/^pin_absent: /);
    expect(sshTransport).not.toHaveBeenCalled();
  });

  it("store disabled + no pin, run twice: `unconfigured` `pin_absent:` both times, never dials, no pin report (#5914)", async () => {
    const { removeGitDataRepo } = await load();
    for (let i = 0; i < 2; i++) {
      const outcome = await removeGitDataRepo(WS);
      expect(outcome.status).toBe("unconfigured");
      if (outcome.status !== "unconfigured") throw new Error("narrow");
      expect(outcome.detail).toMatch(/^pin_absent: /);
      expect(outcome.detail).toMatch(/GIT_DATA_STORE_ENABLED is not true/);
    }
    expect(sshTransport).not.toHaveBeenCalled();
    expect(pinReports()).toHaveLength(0);
  });

  it("no remove key and no sibling inputs stays `skipped` without consulting the pin", async () => {
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "");
    vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "");
    vi.stubEnv("GIT_DATA_SSH_HOST", "");
    const { removeGitDataRepo } = await load();
    await expect(removeGitDataRepo(WS)).resolves.toEqual({ status: "skipped" });
    expect(pinReports()).toHaveLength(0);
  });

  it.each([
    ["changed", "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\nHost key verification failed.\n"],
    ["unknown", "No ED25519 host key is known for git-data and you have requested strict checking.\nHost key verification failed.\n"],
    ["verification failed alone", "Host key verification failed.\n"],
    ["alg (mutation 9)", "Unable to negotiate with 10.0.1.20 port 22: no matching host key type found. Their offer: ssh-rsa\n"],
  ])("exit 255 + %s stderr → host_key_mismatch (never unauthorized/unreachable — mutation 5)", async (_n, stderr) => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(sshErr(255, stderr));
    const { removeGitDataRepo } = await load();
    const outcome = await removeGitDataRepo(WS);
    expect(outcome.status).toBe("host_key_mismatch");
    if (outcome.status !== "host_key_mismatch") throw new Error("narrow");
    expect(outcome.detail.length).toBeGreaterThan(0);
  });

  it("a NON-255 exit with a host-key string is NOT host_key_mismatch (the 255 gate is load-bearing)", async () => {
    // A non-255 status is the REMOTE command's own exit: the session was established, so
    // the host key verified. Only ssh's own 255 can mean a host-identity failure.
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(sshErr(3, "Host key verification failed.\n"));
    const { removeGitDataRepo } = await load();
    expect((await removeGitDataRepo(WS)).status).not.toBe("host_key_mismatch");
  });

  it("exit 255 + `Permission denied (publickey)` stays unauthorized", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(sshErr(255, "git@10.0.1.20: Permission denied (publickey).\n"));
    const { removeGitDataRepo } = await load();
    expect((await removeGitDataRepo(WS)).status).toBe("unauthorized");
  });

  it("spawn ENOENT (no ssh binary in the image) is `unconfigured` `ssh_client_absent:`, not `unreachable`", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(
      Object.assign(new Error("spawn ssh ENOENT"), { code: "ENOENT", syscall: "spawn ssh" }),
    );
    const { removeGitDataRepo } = await load();
    const outcome = await removeGitDataRepo(WS);
    expect(outcome.status).toBe("unconfigured");
    if (outcome.status !== "unconfigured") throw new Error("narrow");
    expect(outcome.detail).toMatch(/^ssh_client_absent: /);
  });

  it("a non-spawn ENOENT (no syscall) stays unreachable — only a failed spawn proves the binary is missing", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(Object.assign(new Error("ENOENT"), { code: "ENOENT" }));
    const { removeGitDataRepo } = await load();
    expect((await removeGitDataRepo(WS)).status).toBe("unreachable");
  });

  it("exit 255 + connection refused stays unreachable", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(sshErr(255, "ssh: connect to host 10.0.1.20 port 22: Connection refused\n"));
    const { removeGitDataRepo } = await load();
    expect((await removeGitDataRepo(WS)).status).toBe("unreachable");
  });
});

describe("provisionGitDataRepo / replicateToGitData / fetchFromGitData — pin threading", () => {
  beforeEach(() => vi.stubEnv("GIT_DATA_STORE_ENABLED", "true"));

  it("provisionGitDataRepo passes the pin (mutation 7: passing null while a pin is set is RED)", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { provisionGitDataRepo } = await load();
    await provisionGitDataRepo(WS);
    expect(sshTransport).toHaveBeenCalledTimes(1);
    expect(sshTransport.mock.calls[0][3]).toBe(PIN);
  });

  it("provisionGitDataRepo with store enabled + no pin throws before any ssh", async () => {
    const { provisionGitDataRepo } = await load();
    await expect(provisionGitDataRepo(WS)).rejects.toThrow(/GIT_DATA_SSH_HOST_KEY/);
    expect(sshTransport).not.toHaveBeenCalled();
  });

  it("replicateToGitData pins BOTH the provision ssh and the push", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { replicateToGitData } = await load();
    await replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 2, userId: USER });
    expect(sshTransport.mock.calls[0][3]).toBe(PIN);
    expect(gitTransport).toHaveBeenCalledTimes(1);
    expect(gitTransport.mock.calls[0][2]).toBe(PIN);
  });

  it("replicateToGitData resolves the pin ONCE and hands it to provision (no second env read)", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const repl = await load();
    // process.env rejects accessor descriptors, so count reads through a Proxy instead.
    const realEnv = process.env;
    let pinReads = 0;
    process.env = new Proxy(realEnv, {
      get(t, k) {
        if (k === "GIT_DATA_SSH_HOST_KEY") pinReads++;
        return Reflect.get(t, k);
      },
    });
    try {
      await repl.replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 2, userId: USER });
    } finally {
      process.env = realEnv;
    }
    expect(sshTransport.mock.calls[0][3]).toBe(PIN);
    expect(gitTransport.mock.calls[0][2]).toBe(PIN);
    expect(pinReads).toBe(1);
  });

  it("replicateToGitData with store enabled + no pin: NO exec happens, the failure is reported, and the rejection is catchable (turn not broken)", async () => {
    const { replicateToGitData } = await load();
    const settled = await replicateToGitData({
      workspacePath: "/tmp/ws",
      workspaceId: WS,
      worktreeId: WT,
      leaseGeneration: 2,
      userId: USER,
    }).then(
      () => "resolved",
      (e: Error) => e.message,
    );
    expect(settled).toMatch(/GIT_DATA_SSH_HOST_KEY/);
    expect(sshTransport).not.toHaveBeenCalled();
    expect(gitTransport).not.toHaveBeenCalled();
    expect(
      reportSilentFallback.mock.calls.some(
        (c) => (c[1] as { op?: string }).op === "git_data_replication_push",
      ),
    ).toBe(true);
  });

  it("fetchFromGitData passes the pin", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { fetchFromGitData } = await load();
    await fetchFromGitData({ userId: USER, workspaceId: WS, worktreeId: WT, workspacePath: "/tmp/ws" });
    expect(gitTransport).toHaveBeenCalledTimes(1);
    expect(gitTransport.mock.calls[0][2]).toBe(PIN);
  });

  it("fetchFromGitData with store enabled + an invalid pin throws before any transport", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", "ssh-rsa AAAAB3NzaC1yc2E");
    const { fetchFromGitData } = await load();
    await expect(
      fetchFromGitData({ userId: USER, workspaceId: WS, worktreeId: WT, workspacePath: "/tmp/ws" }),
    ).rejects.toThrow(/GIT_DATA_SSH_HOST_KEY/);
    expect(gitTransport).not.toHaveBeenCalled();
  });
});

// #8572: a push that fails on the pin reports ONCE on the message path with the `pin_fault`
// tag the pin-fault rule pages on; any other push failure keeps its Error-path report.
describe("replicateToGitData — push pin faults (#8572)", () => {
  beforeEach(() => vi.stubEnv("GIT_DATA_STORE_ENABLED", "true"));

  const pushReports = () =>
    reportSilentFallback.mock.calls.filter(
      (c) => (c[1] as { op?: string }).op === "git_data_replication_push",
    );
  /** A transport rejection shaped the way execFileAsync builds one: a real Error with fields. */
  const rejection = (fields: { code?: unknown; stderr?: unknown; syscall?: unknown }) =>
    Object.assign(new Error("Command failed: ssh -o … git@10.0.0.9"), fields);
  const HOST_KEY = "Host key verification failed.";

  async function push() {
    const { replicateToGitData } = await load();
    return replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 2, userId: USER }).then(
      () => "resolved" as const,
      (e: unknown) => e,
    );
  }

  async function expectPinFault(reason: string, via: "ssh" | "git") {
    const { hashUserId } = await import("../server/observability");
    const settled = await push();
    expect(settled).toBeInstanceOf(Error); // re-thrown, still catchable by the caller
    expect(pushReports()).toHaveLength(1);
    const [err, opts] = pushReports()[0] as [unknown, Record<string, unknown>];
    expect(err).toBeNull();
    expect(opts).toMatchObject({
      feature: "worktree_lease",
      op: "git_data_replication_push",
      message: `git-data replication push pin fault (${reason}): the workspace's objects were NOT replicated to the shared store`,
      tags: { pin_fault: reason },
      extra: { via, pinFault: reason, leaseGeneration: 2, userIdHash: hashUserId(USER) },
    });
    // The raw id never rides the report: the pin-fault extra refuses a bare userId.
    expect(JSON.stringify(opts)).not.toContain(USER);
    // Neither stderr nor the error message rides the event.
    expect(JSON.stringify(pushReports())).not.toMatch(/Command failed|verification failed|10\.0\.0\.9/);
  }

  async function expectErrorPath() {
    const settled = await push();
    expect(settled).toBeInstanceOf(Error);
    expect(pushReports()).toHaveLength(1);
    const [err, opts] = pushReports()[0] as [unknown, Record<string, unknown>];
    expect(err).toBeInstanceOf(Error);
    expect(opts).not.toHaveProperty("tags");
    return opts;
  }

  it("absent pin → pin_absent, via ssh, nothing dialed", async () => {
    await expectPinFault("pin_absent", "ssh");
    expect(sshTransport).not.toHaveBeenCalled();
    expect(gitTransport).not.toHaveBeenCalled();
  });

  it("invalid pin → pin_invalid, via ssh", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", "ssh-rsa AAAAB3NzaC1yc2E");
    await expectPinFault("pin_invalid", "ssh");
  });

  it("provision `spawn ssh` ENOENT → ssh_client_absent", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(rejection({ code: "ENOENT", syscall: "spawn ssh" }));
    await expectPinFault("ssh_client_absent", "ssh");
  });

  it("provision ssh 255 + host-key text → host_key_mismatch, via ssh", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(rejection({ code: 255, stderr: HOST_KEY }));
    await expectPinFault("host_key_mismatch", "ssh");
  });

  it("provision ssh 128 + host-key text is the REMOTE command's status → Error path, not a pin fault", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    sshTransport.mockRejectedValueOnce(rejection({ code: 128, stderr: HOST_KEY }));
    await expectErrorPath();
  });

  it("git push 128 + host-key text → Error path: the push is never read for host identity", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    gitTransport.mockRejectedValueOnce(
      rejection({ code: 128, stderr: `${HOST_KEY}\nfatal: Could not read from remote repository.` }),
    );
    await expectErrorPath();
  });

  it("git push 255 + host-key text → Error path: 255 is ssh's status, and the push is not ssh", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    gitTransport.mockRejectedValueOnce(rejection({ code: 255, stderr: HOST_KEY }));
    await expectErrorPath();
  });

  it("tenant-written .git/packed-refs echoing host-key text cannot forge a page", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    // git 2.55 echoes a malformed packed-refs line in a fatal, before any dial, exit 128.
    gitTransport.mockRejectedValueOnce(
      rejection({ code: 128, stderr: "fatal: unexpected line in .git/packed-refs: Host key verification failed" }),
    );
    await expectErrorPath();
  });

  it("git push `spawn git` ENOENT → Error path, not a pin fault", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    gitTransport.mockRejectedValueOnce(rejection({ code: "ENOENT", syscall: "spawn git" }));
    await expectErrorPath();
  });

  it("fence reject → the existing Error-path report, unchanged", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    gitTransport.mockRejectedValueOnce(rejection({ code: 1, stderr: "remote: fence: stale lease-gen" }));
    const opts = await expectErrorPath();
    const { hashUserId } = await import("../server/observability");
    expect(opts).toEqual({
      feature: "worktree_lease",
      op: "git_data_replication_push",
      extra: {
        workspaceIdHash: hashUserId(WS),
        worktreeIdHash: hashUserId(WT),
        leaseGeneration: 2,
        userId: USER,
      },
      message:
        "git-data replication push failed — a fence reject (stale lease-gen) or " +
        "transport error; the workspace's objects were NOT replicated to the shared store",
    });
  });
});

// Probed at collection time with the REAL execFileSync: this file's vi.mock replaces
// child_process.execFileSync, so a static import would hit the mock and always "succeed".
const { execFileSync: realExecFileSync } =
  await vi.importActual<typeof import("child_process")>("child_process");
let sshKeygenAvailable = false;
try {
  realExecFileSync("ssh-keygen", ["-l", "-f", "/dev/null"], { stdio: "ignore" });
  sshKeygenAvailable = true;
} catch (e) {
  // ssh-keygen exists but rejects /dev/null (non-zero exit) → available; ENOENT → absent.
  sshKeygenAvailable = (e as NodeJS.ErrnoException).code !== "ENOENT";
}

// A PATH holding an executable `ssh`, and one holding none — the startup ssh-client check
// walks PATH (no spawn at boot), so each test pins PATH instead of trusting the host's.
const sshBinDir = mkdtempSync(join(tmpdir(), "ssh-bin-"));
writeFileSync(join(sshBinDir, "ssh"), "#!/bin/sh\nexit 0\n", { mode: 0o755 });
const noSshDir = mkdtempSync(join(tmpdir(), "no-ssh-"));
const ORIGINAL_PATH = process.env.PATH ?? "";
const PATH_WITH_SSH = `${sshBinDir}:${ORIGINAL_PATH}`;

describe("startup pin line (AC16) — logged once at WARN so Vector ships it", () => {
  // The pin line only: the ssh-client line (below) is a separate warn line.
  const warnMessages = () =>
    logWarn.mock.calls.map((c) => String(c[c.length - 1])).filter((m) => m.startsWith("git_data_pin="));
  beforeEach(() => vi.stubEnv("PATH", PATH_WITH_SSH));

  it("present: `git_data_pin=present fp=SHA256:<fp>` at warn, never info", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(warnMessages()).toHaveLength(1);
    const msg = warnMessages()[0];
    expect(msg).toMatch(/^git_data_pin=present fp=SHA256:[A-Za-z0-9+/]{43}$/);
    expect(msg).toBe(`git_data_pin=present fp=${expectedFingerprint(PIN)}`);
    // The raw key never reaches the log.
    expect(JSON.stringify(logWarn.mock.calls)).not.toContain(PIN.split(" ")[1]);
    expect(logInfo.mock.calls.some((c) => String(c[c.length - 1]).includes("git_data_pin="))).toBe(false);
  });

  it.skipIf(!sshKeygenAvailable)("the fingerprint matches `ssh-keygen -lf`", async () => {
    let keygen = "";
    const dir = mkdtempSync(join(tmpdir(), "pin-fp-"));
    try {
      const f = join(dir, "k.pub");
      writeFileSync(f, `${PIN}\n`);
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      // No catch: with ssh-keygen present, a failure here is a real failure, not a skip.
      keygen = actual.execFileSync("ssh-keygen", ["-lf", f], { encoding: "utf8" });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    const fp = warnMessages()[0].split("fp=")[1];
    expect(keygen.split(" ")[1]).toBe(fp);
  });

  it("absent: `git_data_pin=absent` at warn (armed by beforeEach's remove/provision keys, so it also emits the startup event)", async () => {
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(warnMessages()).toEqual(["git_data_pin=absent"]);
    expect(pinReports()).toHaveLength(1);
  });

  it("invalid: `git_data_pin=invalid` at warn, and NEVER throws (startup must not crash)", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", `${PIN}\n* ssh-rsa AAAA`);
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    const { logGitDataHostKeyPinAtStartup } = await load();
    expect(() => logGitDataHostKeyPinAtStartup()).not.toThrow();
    expect(warnMessages()).toEqual(["git_data_pin=invalid"]);
    expect(JSON.stringify(logWarn.mock.calls)).not.toContain("ssh-rsa");
    // An invalid pin is also a Sentry event at boot (it fails every git-data call closed),
    // and the event never carries the value.
    expect(pinReports()).toHaveLength(1);
    // Message path (err === null): an Error-path report loses its feature/op tags to the
    // pino mirror's pre-capture (#8629).
    expect(pinReports()[0][0]).toBeNull();
    expect(pinReports()[0][1]).toEqual({
      feature: "git_data_host_key_pin",
      op: "pin_invalid_at_startup",
      message: "git-data host-key pin invalid at startup",
      // #8572: the tag the pin-fault rule pages on, and its copy for the pino line.
      tags: { pin_fault: "pin_invalid" },
      extra: { pinFault: "pin_invalid" },
    });
    expect(JSON.stringify(reportSilentFallback.mock.calls)).not.toContain(PIN.split(" ")[1].slice(0, 30));
  });

  it("present: no Sentry event at startup (the log line is the evidence)", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(pinReports()).toHaveLength(0);
  });

  it("a throw inside the startup log is swallowed but leaves a console.warn trace", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    logWarn.mockImplementationOnce(() => {
      throw new Error("logger down");
    });
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    try {
      const { logGitDataHostKeyPinAtStartup } = await load();
      expect(() => logGitDataHostKeyPinAtStartup()).not.toThrow();
      expect(warn).toHaveBeenCalledTimes(1);
      expect(String(warn.mock.calls[0][0])).toMatch(/pin inspection failed/);
    } finally {
      warn.mockRestore();
    }
  });

  // P7 (#5914): an absent pin now refuses every git-data dial, so a container armed for
  // git-data that boots without one is an event at boot, before any erasure is refused.
  // "Armed" = any of the three sibling inputs removeGitDataRepo reads, non-empty after trim.
  const ARM_INPUTS = ["GIT_REMOVE_SSH_PRIVATE_KEY", "GIT_PROVISION_SSH_PRIVATE_KEY", "GIT_DATA_SSH_HOST"] as const;
  const SYNTH: Record<(typeof ARM_INPUTS)[number], string> = {
    GIT_REMOVE_SSH_PRIVATE_KEY: "synthetic-remove-key-7f3a",
    GIT_PROVISION_SSH_PRIVATE_KEY: "synthetic-provision-key-9c1d",
    GIT_DATA_SSH_HOST: "10.99.0.77",
  };

  it("absent + UNARMED (transport key still set): logs the line, emits no event", async () => {
    for (const k of ARM_INPUTS) vi.stubEnv(k, "");
    vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "synthetic-transport-key-2b8e");
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(warnMessages()).toEqual(["git_data_pin=absent"]);
    expect(pinReports()).toHaveLength(0);
  });

  it("absent + arming inputs whitespace-only: no event", async () => {
    for (const k of ARM_INPUTS) vi.stubEnv(k, "   ");
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(pinReports()).toHaveLength(0);
  });

  it.each(ARM_INPUTS)("absent + armed by %s ALONE: exactly one pin_absent_at_startup on the message path, no key material", async (only) => {
    for (const k of ARM_INPUTS) vi.stubEnv(k, k === only ? SYNTH[k] : "");
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(warnMessages()).toEqual(["git_data_pin=absent"]);
    expect(pinReports()).toHaveLength(1);
    expect(pinReports()[0][0]).toBeNull();
    expect(pinReports()[0][1]).toEqual({
      feature: "git_data_host_key_pin",
      op: "pin_absent_at_startup",
      message: "git-data host-key pin absent at startup",
      // #8572: the tag the pin-fault rule pages on, and its copy for the pino line.
      tags: { pin_fault: "pin_absent" },
      extra: { pinFault: "pin_absent" },
    });
    const all = JSON.stringify(reportSilentFallback.mock.calls);
    for (const v of Object.values(SYNTH)) expect(all).not.toContain(v);
  });

  // The boot wiring (server/index.ts calls it once) is bound by importing the boot module
  // itself: test/server-index-boot-pin-line.test.ts. A source regex here matched a
  // commented-out call.
});

// #5914 (CTO ruling 2026-09-28): node:22-slim + `--no-install-recommends` shipped NO ssh
// client, so every git-data dial failed ENOENT. Startup now says which it is, off-host.
describe("startup ssh-client line — git_data_ssh_client=present|absent", () => {
  const sshLines = () =>
    logWarn.mock.calls.map((c) => String(c[c.length - 1])).filter((m) => m.startsWith("git_data_ssh_client="));
  const sshReports = () =>
    reportSilentFallback.mock.calls.filter(
      (c) => (c[1] as { op?: string }).op === "ssh_client_absent_at_startup",
    );

  it("ssh on PATH: `git_data_ssh_client=present`, no event", async () => {
    vi.stubEnv("PATH", sshBinDir);
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(sshLines()).toEqual(["git_data_ssh_client=present"]);
    expect(sshReports()).toHaveLength(0);
  });

  it("no ssh on PATH + armed: `git_data_ssh_client=absent` and ONE message-path event", async () => {
    vi.stubEnv("PATH", noSshDir);
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(sshLines()).toEqual(["git_data_ssh_client=absent"]);
    expect(sshReports()).toHaveLength(1);
    expect(sshReports()[0][0]).toBeNull();
    expect(sshReports()[0][1]).toEqual({
      feature: "git_data_ssh_client",
      op: "ssh_client_absent_at_startup",
      message: "git-data ssh client absent at startup",
      // #8572: the tag the pin-fault rule pages on, and its copy for the pino line.
      tags: { pin_fault: "ssh_client_absent" },
      extra: { pinFault: "ssh_client_absent" },
    });
  });

  it("no ssh on PATH + UNARMED: logs absent, no event (dev without git-data inputs)", async () => {
    vi.stubEnv("PATH", noSshDir);
    for (const k of ["GIT_REMOVE_SSH_PRIVATE_KEY", "GIT_PROVISION_SSH_PRIVATE_KEY", "GIT_DATA_SSH_HOST"]) vi.stubEnv(k, "");
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(sshLines()).toEqual(["git_data_ssh_client=absent"]);
    expect(sshReports()).toHaveLength(0);
  });

  it("a non-executable `ssh` file on PATH reads absent", async () => {
    const d = mkdtempSync(join(tmpdir(), "ssh-noexec-"));
    writeFileSync(join(d, "ssh"), "not executable\n", { mode: 0o644 });
    vi.stubEnv("PATH", d);
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(sshLines()).toEqual(["git_data_ssh_client=absent"]);
  });
});
