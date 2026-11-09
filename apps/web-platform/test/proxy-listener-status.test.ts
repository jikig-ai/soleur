import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { createServer as createNetServer, type Server as NetServer } from "node:net";
import type { Server as HttpsServer } from "node:https";
import { connect as tlsConnect } from "node:tls";
import { tmpdir } from "node:os";
import { join } from "node:path";

// #12167 — the relay reports its OWN bind. Real sockets, real EADDRNOTAVAIL /
// EADDRINUSE: a mocked server would prove nothing about what the kernel does with
// `listen(port, host)`. Only the logger and the Sentry mirror are mocked, so the
// emitted level and line text can be asserted.

const { mockWarn, mockInfo, mockError, mockReportSilentFallback, mockWarnSilentFallback } = vi.hoisted(() => ({
  mockWarn: vi.fn(),
  mockInfo: vi.fn(),
  mockError: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => {
  const child = () => ({ info: mockInfo, warn: mockWarn, error: mockError, debug: vi.fn() });
  return { default: child(), createChildLogger: child };
});
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
  infoSilentFallback: vi.fn(),
}));

import { createProxyServer } from "@/server/session-proxy";
import { __resetProxyHelloKeyForTests } from "@/server/proxy-tls";
import {
  PROXY_REPORT_INTERVAL_MS,
  __resetProxyListenerStatusForTests,
  emitProxyListenerStatusOnce,
  getProxyStatus,
  recordProxyServer,
  startProxyListenerReporter,
} from "@/server/proxy-listener-status";
import { buildReadinessResponse, isWorkspacesPopulated } from "@/server/readiness";

// Every line the reporter may emit must match this and nothing else.
const GRAMMAR =
  /^relay_probe proxy_state=(listening|disabled|no_bind|no_allowlist|error) addr=([0-9a-fA-F:.]+|none) port=\d{1,5} workspaces_populated=[01]$/;

// cq-test-fixtures-synthesized-only: a throwaway self-signed cert minted per run.
let tlsDir: string;
let KEY: string;
let CERT: string;
const PEER = "10.0.1.9";
// Test-only seam (an explicit createProxyServer param, never an env var): production
// requires an IPv4 under 10.0.1.; loopback / TEST-NET binds need the prefix lifted.
// net.isIPv4 is still enforced with it.
const TEST_BIND_ANY = { privateBindPrefix: "" } as const;
const collapse = (pem: string) => pem.trim().replace(/\r?\n/g, "\\n");

const opened: HttpsServer[] = [];
const blockers: NetServer[] = [];
const onProxiedSession = vi.fn();

function warnLines(): string[] {
  return mockWarn.mock.calls.map((c) => String(c[1]));
}

function whenListeningOrError(s: HttpsServer): Promise<"listening" | "error"> {
  return new Promise((resolve) => {
    s.once("listening", () => resolve("listening"));
    // The production handler is already attached; this just observes the event.
    s.once("error", () => resolve("error"));
  });
}

function track(s: HttpsServer | null): HttpsServer {
  if (!s) throw new Error("createProxyServer returned null");
  opened.push(s);
  return s;
}

beforeEach(() => {
  tlsDir = mkdtempSync(join(tmpdir(), "relay-probe-"));
  execFileSync(
    "openssl",
    ["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
     "-keyout", join(tlsDir, "k.pem"), "-out", join(tlsDir, "c.pem"), "-days", "1", "-subj", "/CN=relay-probe-test", "-addext", "subjectAltName=IP:127.0.0.1"],
    { stdio: "ignore" },
  );
  KEY = readFileSync(join(tlsDir, "k.pem"), "utf8");
  CERT = readFileSync(join(tlsDir, "c.pem"), "utf8");
  vi.clearAllMocks();
  vi.unstubAllEnvs();
  vi.stubEnv("PROXY_TLS_KEY", KEY);
  vi.stubEnv("PROXY_TLS_CERT", CERT);
  vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", PEER);
  vi.stubEnv("SOLEUR_PROXY_BIND", "");
  // #12289: the relay refuses to start without a hello key (the check sits after tls/bind/allowlist, so the
  // disabled / no_bind / no_allowlist assertions below keep their meaning).
  vi.stubEnv("PROXY_HELLO_HMAC_KEY", "a".repeat(64));
  __resetProxyHelloKeyForTests();
  __resetProxyListenerStatusForTests();
});

afterEach(async () => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  for (const s of opened.splice(0)) await new Promise<void>((r) => s.close(() => r()));
  for (const b of blockers.splice(0)) await new Promise<void>((r) => b.close(() => r()));
  rmSync(tlsDir, { recursive: true, force: true });
});

describe("relay bind is reported from the live server", () => {
  it("a real socket on 127.0.0.1 port 0 reports listening with the ACTUAL addr and port", async () => {
    const server = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 }));
    expect(await whenListeningOrError(server)).toBe("listening");
    const a = server.address();
    if (!a || typeof a === "string") throw new Error("no address");

    emitProxyListenerStatusOnce({ readWorkspacesPopulated: () => true });

    expect(warnLines()).toEqual([`relay_probe proxy_state=listening addr=127.0.0.1 port=${a.port} workspaces_populated=1`]);
    expect(a.port).toBeGreaterThan(0);
  });

  it("binds the given private address and NOT the wildcard (listen(port, bindAddress, cb))", async () => {
    const server = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 }));
    await whenListeningOrError(server);
    const a = server.address();
    if (!a || typeof a === "string") throw new Error("no address");
    expect(a.address).toBe("127.0.0.1");
    expect(a.family).toBe("IPv4");
    expect(a.address).not.toBe("::");
    expect(a.address).not.toBe("0.0.0.0");
    expect(getProxyStatus().addr).toBe("127.0.0.1");
  });

  it("EADDRNOTAVAIL does not throw, is mirrored, and yields proxy_state=error", async () => {
    // 192.0.2.0/24 (TEST-NET-1) is never assigned to a local interface.
    let server!: HttpsServer;
    expect(() => {
      server = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "192.0.2.1", port: 0 }));
    }).not.toThrow();
    expect(await whenListeningOrError(server)).toBe("error");

    expect(getProxyStatus().state).toBe("error");
    emitProxyListenerStatusOnce({ readWorkspacesPopulated: () => true });
    expect(warnLines()).toEqual(["relay_probe proxy_state=error addr=none port=0 workspaces_populated=1"]);
    const mirrored = mockReportSilentFallback.mock.calls.find((c) => c[1]?.op === "createProxyServer.listen-error");
    expect(mirrored).toBeDefined();
    expect(mirrored![1].extra).toMatchObject({ code: "EADDRNOTAVAIL" });
  });

  it("EADDRINUSE does not throw and yields proxy_state=error", async () => {
    const blocker = createNetServer();
    blockers.push(blocker);
    await new Promise<void>((r) => blocker.listen(0, "127.0.0.1", () => r()));
    const busy = (blocker.address() as { port: number }).port;

    const server = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: busy }));
    expect(await whenListeningOrError(server)).toBe("error");

    expect(getProxyStatus().state).toBe("error");
    expect(
      mockReportSilentFallback.mock.calls.some((c) => c[1]?.op === "createProxyServer.listen-error" && c[1]?.extra?.code === "EADDRINUSE"),
    ).toBe(true);
  });
});

describe("the non-listening states", () => {
  it("no PROXY_TLS material -> disabled (and createProxyServer returns null)", () => {
    vi.stubEnv("PROXY_TLS_KEY", "");
    vi.stubEnv("PROXY_TLS_CERT", "");
    expect(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 })).toBeNull();
    expect(getProxyStatus()).toEqual({ state: "disabled", addr: "none", port: 0 });
  });

  it("TLS but no bind address -> no_bind", () => {
    expect(createProxyServer({ onProxiedSession, port: 0 })).toBeNull();
    expect(getProxyStatus()).toEqual({ state: "no_bind", addr: "none", port: 0 });
  });

  it("TLS and bind but empty peer allowlist -> no_allowlist", () => {
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", " , ");
    expect(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 })).toBeNull();
    expect(getProxyStatus()).toEqual({ state: "no_allowlist", addr: "none", port: 0 });
  });

  it("createProxyServer never called -> disabled", () => {
    expect(getProxyStatus().state).toBe("disabled");
  });

  it("a later non-enabled call replaces an earlier recorded server", async () => {
    const server = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 }));
    await whenListeningOrError(server);
    expect(getProxyStatus().state).toBe("listening");
    createProxyServer({ onProxiedSession, port: 0 });
    expect(getProxyStatus().state).toBe("no_bind");
  });
});

describe("line grammar and level", () => {
  it("every emitted line, over every state, matches the closed grammar", async () => {
    const lines: string[] = [];
    const collect = () => {
      mockWarn.mockClear();
      emitProxyListenerStatusOnce({ readWorkspacesPopulated: () => true });
      lines.push(...warnLines());
    };
    collect(); // disabled
    createProxyServer({ onProxiedSession, port: 0 });
    collect(); // no_bind
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "");
    createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 });
    collect(); // no_allowlist
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", PEER);
    const bad = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "192.0.2.1", port: 0 }));
    await whenListeningOrError(bad);
    collect(); // error
    const good = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 }));
    await whenListeningOrError(good);
    collect(); // listening
    emitProxyListenerStatusOnce({ readWorkspacesPopulated: () => { throw new Error("boom"); } });
    lines.push(...warnLines().slice(-1)); // populated read failure still emits a valid line

    expect(lines.map((l) => l.split(" ")[1])).toEqual([
      "proxy_state=disabled", "proxy_state=no_bind", "proxy_state=no_allowlist",
      "proxy_state=error", "proxy_state=listening", "proxy_state=listening",
    ]);
    for (const l of lines) expect(l).toMatch(GRAMMAR);
    expect(lines.at(-1)).toMatch(/workspaces_populated=0$/);
  });

  it("the grammar regex rejects drift (free text, a stray field, a bad state)", () => {
    for (const bad of [
      "relay_probe proxy_state=listening addr=10.0.1.5 port=8443 workspaces_populated=1 err=EADDRINUSE",
      "relay_probe proxy_state=up addr=10.0.1.5 port=8443 workspaces_populated=1",
      "relay_probe proxy_state=error addr=none port=0 workspaces_populated=2",
      "relay_probe proxy_state=error addr=Error: x port=0 workspaces_populated=0",
    ]) expect(bad).not.toMatch(GRAMMAR);
  });

  it("is emitted at WARN level, never info", () => {
    emitProxyListenerStatusOnce({ readWorkspacesPopulated: () => false });
    expect(mockWarn).toHaveBeenCalledTimes(1);
    expect(mockInfo.mock.calls.some((c) => String(c[1] ?? c[0]).includes("relay_probe"))).toBe(false);
    expect(mockError.mock.calls.some((c) => String(c[1] ?? c[0]).includes("relay_probe"))).toBe(false);
  });
});

describe("the reporter reads the state at EMIT time, not at start", () => {
  it("a server recorded and listening AFTER start shows up in the next tick; a later close shows error", () => {
    vi.useFakeTimers();
    const timer = startProxyListenerReporter({ readWorkspacesPopulated: () => true });

    vi.advanceTimersByTime(1_000); // initial emit: nothing recorded yet
    expect(warnLines().at(-1)).toBe("relay_probe proxy_state=disabled addr=none port=0 workspaces_populated=1");

    const fake = { listening: true, address: () => ({ address: "10.0.1.5", family: "IPv4", port: 8443 }) };
    recordProxyServer(fake as unknown as HttpsServer);
    vi.advanceTimersByTime(PROXY_REPORT_INTERVAL_MS);
    expect(warnLines().at(-1)).toBe("relay_probe proxy_state=listening addr=10.0.1.5 port=8443 workspaces_populated=1");

    fake.listening = false;
    vi.advanceTimersByTime(PROXY_REPORT_INTERVAL_MS);
    expect(warnLines().at(-1)).toBe("relay_probe proxy_state=error addr=none port=0 workspaces_populated=1");

    clearInterval(timer);
  });

  it("emits every 60 s, and a throwing populated reader cannot crash a tick", () => {
    vi.useFakeTimers();
    const timer = startProxyListenerReporter({
      readWorkspacesPopulated: () => { throw new Error("fs gone"); },
    });
    expect(() => vi.advanceTimersByTime(PROXY_REPORT_INTERVAL_MS * 3)).not.toThrow();
    expect(mockWarn.mock.calls.length).toBeGreaterThanOrEqual(3);
    expect(mockWarnSilentFallback).toHaveBeenCalled();
    clearInterval(timer);
  });
});

describe("/internal/readyz: the proxy block is NON-GATING", () => {
  let root: string;
  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "relay-probe-ws-"));
    vi.stubEnv("WORKSPACES_ROOT", root);
  });
  afterEach(() => rmSync(root, { recursive: true, force: true }));

  it("ready is unchanged when the relay is disabled (web-1: no relay bind or TLS)", () => {
    mkdirSync(join(root, "ws-1"));
    vi.stubEnv("PROXY_TLS_KEY", "");
    vi.stubEnv("PROXY_TLS_CERT", "");
    createProxyServer({ onProxiedSession, port: 0 });

    const r = buildReadinessResponse();
    expect(r.ready).toBe(true);
    expect(r.proxy).toEqual({ state: "disabled", addr: "none", port: 0 });
    expect(r.checks).toEqual({ workspaces_writable: true, workspaces_populated: true });
  });

  it("ready stays false on an unpopulated host even if the relay is listening, and true on a populated host whose relay errored", async () => {
    const server = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 }));
    await whenListeningOrError(server);
    expect(buildReadinessResponse().ready).toBe(false); // empty root
    expect(buildReadinessResponse().proxy.state).toBe("listening");

    mkdirSync(join(root, "ws-1"));
    __resetProxyListenerStatusForTests();
    createProxyServer({ onProxiedSession, port: 0 }); // no_bind
    const r = buildReadinessResponse();
    expect(r.ready).toBe(true);
    expect(r.proxy.state).toBe("no_bind");
  });

  it("isWorkspacesPopulated is read-only: it writes nothing under the root", () => {
    mkdirSync(join(root, "ws-1"));
    const before = JSON.stringify(readdirSync(root).sort());
    expect(isWorkspacesPopulated()).toBe(true);
    expect(JSON.stringify(readdirSync(root).sort())).toBe(before);
  });
});

// ---------------------------------------------------------------------------
// PEM as the container actually receives it. ci-deploy.sh loads Doppler prd with
// `doppler secrets download --format docker` + `docker --env-file`, which collapses a
// multi-line PEM to ONE line of literal backslash-n pairs; https.createServer throws
// ERR_OSSL_PEM_NO_START_LINE on that. Real loaders, real https server, real handshake.
// ---------------------------------------------------------------------------
describe("collapsed (docker env-file) PEM reaches a working listener", () => {
  function pinnedHandshake(port: number, ca: string): Promise<boolean> {
    return new Promise((resolve) => {
      const sock = tlsConnect({ host: "127.0.0.1", port, ca, rejectUnauthorized: true }, () => {
        const ok = sock.authorized;
        sock.end();
        resolve(ok);
      });
      sock.on("error", () => resolve(false));
    });
  }

  it("collapsed key + cert + client CA: listener binds and a client pinning the collapsed CA completes the handshake", async () => {
    vi.stubEnv("PROXY_TLS_KEY", collapse(KEY));
    vi.stubEnv("PROXY_TLS_CERT", collapse(CERT));
    // The handshake client connects from loopback: since #12288 a non-allowlisted source is reset
    // before the handshake, so this case allowlists the address it dials from.
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
    expect(process.env.PROXY_TLS_KEY).not.toContain("\n");
    const { loadProxyTlsClientCa } = await import("@/server/proxy-tls");
    const server = track(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 }));
    expect(await whenListeningOrError(server)).toBe("listening");
    const a = server.address();
    if (!a || typeof a === "string") throw new Error("no address");
    expect(getProxyStatus().state).toBe("listening");
    expect(await pinnedHandshake(a.port, loadProxyTlsClientCa()!)).toBe(true);
  });

  it("garbage PEM does not throw: proxy_state=error, null, mirrored without PEM bytes", () => {
    const marker = "GARBAGE-PEM-MARKER-123";
    vi.stubEnv("PROXY_TLS_KEY", `${marker}\\nmore`);
    let result: unknown;
    expect(() => {
      result = createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 });
    }).not.toThrow();
    expect(result).toBeNull();
    expect(getProxyStatus()).toEqual({ state: "error", addr: "none", port: 0 });
    emitProxyListenerStatusOnce({ readWorkspacesPopulated: () => true });
    expect(warnLines()).toEqual(["relay_probe proxy_state=error addr=none port=0 workspaces_populated=1"]);
    const mirrored = mockReportSilentFallback.mock.calls.find((c) => c[1]?.op === "createProxyServer.tls-setup");
    expect(mirrored).toBeDefined();
    const dump = JSON.stringify(mockReportSilentFallback.mock.calls.map((c) => [String(c[0]?.message), c[1]]));
    expect(dump).not.toContain(marker);
    expect(dump).not.toContain("BEGIN");
    expect(dump).not.toContain("PEM routines");
  });

  it("a valid cert with a mismatched key also fails closed (error, no throw)", () => {
    execFileSync(
      "openssl",
      ["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
       "-keyout", join(tlsDir, "k2.pem"), "-out", join(tlsDir, "c2.pem"), "-days", "1", "-subj", "/CN=other"],
      { stdio: "ignore" },
    );
    vi.stubEnv("PROXY_TLS_KEY", collapse(readFileSync(join(tlsDir, "k2.pem"), "utf8")));
    expect(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 })).toBeNull();
    expect(getProxyStatus().state).toBe("error");
  });
});

describe("bind address validation (fail closed: 0.0.0.0 or IPv4 10.0.1.x only)", () => {
  const refused = ["::", "::1", "localhost", "example.com", "8.8.8.8", "127.0.0.1", "10.0.2.5", "10.0.1", "10.0.1.256", "::ffff:10.0.1.5", "0.0.0.1", "10.0.1.5:8443", "10.0.1.x"];
  for (const addr of refused) {
    it(`refuses ${JSON.stringify(addr)}: null, no_bind, mirrored as bad-bind, never listens`, () => {
      let result: unknown;
      expect(() => {
        result = createProxyServer({ onProxiedSession, bindAddress: addr, port: 0 });
      }).not.toThrow();
      expect(result).toBeNull();
      expect(getProxyStatus()).toEqual({ state: "no_bind", addr: "none", port: 0 });
      expect(mockReportSilentFallback.mock.calls.some((c) => c[1]?.op === "createProxyServer.bad-bind")).toBe(true);
    });
  }

  it("a bad SOLEUR_PROXY_BIND env value is refused too", () => {
    vi.stubEnv("SOLEUR_PROXY_BIND", "::");
    expect(createProxyServer({ onProxiedSession, port: 0 })).toBeNull();
    expect(mockReportSilentFallback.mock.calls.some((c) => c[1]?.op === "createProxyServer.bad-bind")).toBe(true);
  });

  it("0.0.0.0 (container-namespace bind; docker -p applies the private IP) is accepted without any seam", async () => {
    const server = track(createProxyServer({ onProxiedSession, bindAddress: "0.0.0.0", port: 0 }));
    expect(await whenListeningOrError(server)).toBe("listening");
    expect(mockReportSilentFallback.mock.calls.some((c) => c[1]?.op === "createProxyServer.bad-bind")).toBe(false);
  });

  it("a 10.0.1.x address passes validation (it then binds or hits the kernel, never bad-bind)", async () => {
    const server = track(createProxyServer({ onProxiedSession, bindAddress: "10.0.1.5", port: 0 }));
    await whenListeningOrError(server);
    expect(mockReportSilentFallback.mock.calls.some((c) => c[1]?.op === "createProxyServer.bad-bind")).toBe(false);
  });

  it("the test-only seam lifts only the prefix: a non-IPv4 is still refused", () => {
    expect(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "localhost", port: 0 })).toBeNull();
    expect(getProxyStatus().state).toBe("no_bind");
  });

  it("outside the test runner the prefix override is ignored: 127.0.0.1 stays refused", () => {
    const saved = process.env.VITEST;
    delete process.env.VITEST;
    try {
      expect(createProxyServer({ onProxiedSession, ...TEST_BIND_ANY, bindAddress: "127.0.0.1", port: 0 })).toBeNull();
      expect(getProxyStatus().state).toBe("no_bind");
      expect(mockReportSilentFallback.mock.calls.some((c) => c[1]?.op === "createProxyServer.bad-bind")).toBe(true);
    } finally {
      if (saved !== undefined) process.env.VITEST = saved;
    }
  });
});
