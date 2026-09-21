// #7226 / #5914 — Guard 5 (the app's git-data transport is pinned whenever a pin exists)
// and Guard 3 (pin shape), app side. Plan:
// knowledge-base/project/plans/2026-09-21-security-pin-web-1-and-git-data-ssh-host-keys-plan.md
//
// Every test re-imports the module under vi.resetModules() + vi.unstubAllEnvs(): the
// once-per-process `pin_absent_store_disabled` report is MODULE state, so a shared import
// would let one test's report satisfy (or break) another's "exactly once" assertion.
// Keys are generated per run (helpers/ssh-host-key-fixture.ts) — never a real host key.

import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { expectedFingerprint, makeEd25519Pin } from "./helpers/ssh-host-key-fixture";

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

  it.each([
    ["embedded newline + a second `* ssh-rsa` line", (p: string) => `${p}\n* ssh-rsa AAAAB3NzaC1yc2E`],
    ["trailing comment", (p: string) => `${p} host@x`],
    ["host pattern prefix", (p: string) => `git-data ${p}`],
    ["@cert-authority marker", (p: string) => `@cert-authority * ${p}`],
    ["an ssh-rsa key", () => "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7"],
    ["a truncated ED25519 key", (p: string) => p.slice(0, -1)],
    ["an ED25519 key with padding appended", (p: string) => `${p}=`],
    ["two key lines", (p: string) => `${p}\n${p}`],
  ])("wrong shape (%s) THROWS — and never echoes the raw value", async (_n, mk) => {
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

  it("absent + store disabled returns null and reports pin_absent_store_disabled ONCE per process", async () => {
    const { resolveGitDataHostKeyPin } = await load();
    expect(resolveGitDataHostKeyPin()).toBeNull();
    expect(resolveGitDataHostKeyPin()).toBeNull();
    expect(pinReports()).toHaveLength(1);
    expect(pinReports()[0][1]).toMatchObject({
      feature: "git_data_host_key_pin",
      op: "pin_absent_store_disabled",
    });
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
    expect(outcome.detail).toMatch(/^pin_absent_store_enabled: /);
    expect(sshTransport).not.toHaveBeenCalled();
  });

  it("store disabled + no pin, run twice: ssh uses the fallback (null) and Sentry gets exactly ONE pin_absent_store_disabled", async () => {
    const { removeGitDataRepo } = await load();
    await removeGitDataRepo(WS);
    await removeGitDataRepo(WS);
    expect(sshTransport).toHaveBeenCalledTimes(2);
    expect(sshTransport.mock.calls[0][3]).toBeNull();
    expect(sshTransport.mock.calls[1][3]).toBeNull();
    expect(pinReports()).toHaveLength(1);
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

describe("startup pin line (AC16) — logged once at WARN so Vector ships it", () => {
  const warnMessages = () => logWarn.mock.calls.map((c) => String(c[c.length - 1]));

  it("present: `git_data_pin=present fp=SHA256:<fp>` at warn, never info", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", PIN);
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(logWarn).toHaveBeenCalledTimes(1);
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

  it("absent: `git_data_pin=absent` at warn", async () => {
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(warnMessages()).toEqual(["git_data_pin=absent"]);
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
    expect(pinReports()[0][1]).toEqual({
      feature: "git_data_host_key_pin",
      op: "pin_invalid_at_startup",
    });
    expect(String((pinReports()[0][0] as Error).message)).toBe("git-data host-key pin invalid at startup");
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

  it("does not fire the pin_absent Sentry report (startup evidence is the log line, not an event)", async () => {
    const { logGitDataHostKeyPinAtStartup } = await load();
    logGitDataHostKeyPinAtStartup();
    expect(pinReports()).toHaveLength(0);
  });

  // The boot wiring (server/index.ts calls it once) is bound by importing the boot module
  // itself: test/server-index-boot-pin-line.test.ts. A source regex here matched a
  // commented-out call.
});
