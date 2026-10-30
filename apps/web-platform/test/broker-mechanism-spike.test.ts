// #9543 broker-mechanism measurement spike (ADR-311). This file has two halves:
//
//   1. The hermetic "guard" block (always runs, no sandbox): the pure scan/classify functions that
//      every real-sandbox probe calls. The RED rows of the plan's Guard Contract run here against
//      synthetic observations.
//   2. The real-sandbox probes (skipped locally without a usable bubblewrap, failing where
//      C4_BWRAP_REQUIRED is set): added below the guard block.
//
// Nothing here changes production code. Every secret in this file is a decoy generated per run.

import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { createServer as createHttpServer, type IncomingMessage } from "node:http";
import { createServer as createHttpsServer } from "node:https";
import net from "node:net";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { query } from "@anthropic-ai/claude-agent-sdk";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { scrubAmbientCliEnv } from "./helpers/hermetic-cli-env";

import {
  classifyOutcome,
  scanSandboxSurfaces,
  unmeasurable,
  VacuousProbeError,
  type DeclaredSecret,
  type Hit,
  type Observation,
  type ProbeOutcome,
} from "./helpers/broker-spike-scan";

function decoy(label: string): { id: string; value: string } {
  // Per-run randomized name and value (harness row H2): the suite is not keyed to canonical names.
  const rnd = Math.random().toString(36).slice(2, 10);
  return { id: `${label}-${rnd}`, value: `decoy-${label}-${rnd}-${Math.random().toString(36).slice(2, 10)}` };
}

describe("guard: scanSandboxSurfaces and classifyOutcome (hermetic)", () => {
  it("guard row 3a: reports a second unmasked secret after a compliant first", () => {
    const first = decoy("first");
    const second = decoy("second");
    const obs: Observation[] = [
      { surface: "env", text: `PATH=/usr/bin\nTOKEN_A=sentinel-1\nTOKEN_B=${second.value}\n` },
    ];
    const hits = scanSandboxSurfaces(obs, [first, second]);
    expect(hits).toEqual([{ surface: "env", secretId: second.id }]);
  });

  it("guard row 3c: reports every declared secret visible on the SAME surface, not only the first", () => {
    const a = decoy("both-a");
    const b = decoy("both-b");
    const hits = scanSandboxSurfaces([{ surface: "env", text: `${a.value}\n${b.value}\n` }], [a, b]);
    expect(hits.map((h) => h.secretId).sort()).toEqual([a.id, b.id].sort());
  });

  it("guard row 3b: reports a value reachable only through Glob/Grep output", () => {
    const s = decoy("globbed");
    const obs: Observation[] = [
      { surface: "env", text: "PATH=/usr/bin\n" },
      { surface: "grep-output", text: `notes.txt:3: ${s.value}\n` },
    ];
    expect(scanSandboxSurfaces(obs, [s])).toEqual([{ surface: "grep-output", secretId: s.id }]);
  });

  it("guard: finds nothing when no declared secret appears on any surface", () => {
    const s = decoy("absent");
    expect(scanSandboxSurfaces([{ surface: "env", text: "A=1\nB=2\n" }], [s])).toEqual([]);
  });

  it("guard: never echoes a secret value in a hit (ids only)", () => {
    const s = decoy("quiet");
    const hits = scanSandboxSurfaces([{ surface: "env", text: s.value }], [s]);
    expect(JSON.stringify(hits)).not.toContain(s.value);
  });

  it("guard row 2: a probe that observed nothing is a vacuous run, not a pass", () => {
    expect(() =>
      classifyOutcome({ probe: "a", observedEvents: [], scan: [], substitutionObserved: true }),
    ).toThrow(VacuousProbeError);
  });

  it("guard H1: replacing the sandbox probe command with `true` observes nothing and is vacuous", () => {
    // `true` prints nothing: the observation list is empty, so the classifier refuses to conclude.
    const observedEvents: string[] = [];
    expect(() =>
      classifyOutcome({ probe: "a-h1", observedEvents, scan: [], substitutionObserved: false }),
    ).toThrow(/observed nothing|0 observed/i);
  });

  it("guard row 2b: a conclusion without evidence cannot be constructed", () => {
    expect(() => unmeasurable("a", "needs a reason", [])).toThrow(/evidence/i);
    expect(() =>
      classifyOutcome({ probe: "a", observedEvents: ["x"], scan: [], substitutionObserved: true, evidence: [] }),
    ).toThrow(/evidence/i);
  });

  it("guard: a visible secret on a treatment arm is recorded as `leaks` with evidence, not thrown", () => {
    const s = decoy("leaky");
    const scan = scanSandboxSurfaces([{ surface: "env", text: s.value }], [s]);
    const out = classifyOutcome({ probe: "a-treatment", observedEvents: ["bash-ran"], scan, substitutionObserved: true });
    expect(out.outcome).toBe("leaks");
    expect(out.evidence.join(" ")).toContain("env");
    expect(out.evidence.join(" ")).not.toContain(s.value);
  });

  it("guard: substitution observed with a clean scan is `works`; not observed is `does-not-work`", () => {
    const works = classifyOutcome({ probe: "a", observedEvents: ["echo-received"], scan: [], substitutionObserved: true });
    expect(works.outcome).toBe("works");
    expect(works.evidence.length).toBeGreaterThan(0);
    const dnw = classifyOutcome({ probe: "a", observedEvents: ["echo-received"], scan: [], substitutionObserved: false });
    expect(dnw.outcome).toBe("does-not-work");
  });

  it("guard: `unmeasurable` is a valid recorded outcome and carries its reason as evidence", () => {
    const out = unmeasurable("c", "harness fault: socat absent", ["spawn socat ENOENT"]);
    expect(out.outcome).toBe("unmeasurable");
    expect(out.evidence.join(" ")).toContain("socat absent");
  });
});

// ---------------------------------------------------------------------------------------------
// Real-sandbox probes (ADR-311). Skipped locally without a usable bubblewrap + socat + curl +
// openssl, failing where C4_BWRAP_REQUIRED is set (same convention as the W1 runtime test).
//
// Topology (measured, ADR-278): sandboxed curl -> SDK sandbox-runtime proxy -> (env proxy URL) the
// REAL, UNMODIFIED infra/egress-forwarder.mjs -> a stub gateway in this file that performs the
// CONNECT/absolute-URI tunnelling to local echo targets. The test hostnames are non-loopback names
// (the production NO_PROXY would send loopback straight to the sandbox's own empty loopback).
// ---------------------------------------------------------------------------------------------

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BWRAP_SHIM = join(APP_ROOT, "infra", "bwrap-shim", "bwrap");
const BWRAP_BPF = join(APP_ROOT, "infra", "bwrap-userns-clone3-deny.bpf");
const FORWARDER = join(APP_ROOT, "infra", "egress-forwarder.mjs");
const SDK_PKG = JSON.parse(readFileSync(join(APP_ROOT, "package.json"), "utf8")) as {
  dependencies?: Record<string, string>;
};
const savedPath = process.env.PATH;

const AMBIENT_SECRET_NAMES = /^(GITHUB_TOKEN|GH_TOKEN|DOPPLER_[A-Z_]*|ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN)$/;
// Captured BEFORE any scrub: a CI runner's real tokens become declared secrets, so the scan fails
// loudly if a real credential were ever visible inside the sandbox.
const AMBIENT_SECRETS: DeclaredSecret[] = Object.entries(process.env)
  .filter(([k, v]) => AMBIENT_SECRET_NAMES.test(k) && typeof v === "string" && v.length >= 8)
  .map(([k, v]) => ({ id: `ambient:${k}`, value: v as string }));

const BWRAP_OK =
  process.platform === "linux" &&
  spawnSync("bwrap", ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--", "true"], {
    stdio: "ignore",
    timeout: 15_000,
  }).status === 0;
const TOOLS_OK = ["socat", "curl", "openssl"].every(
  (t) => spawnSync("sh", ["-c", `command -v ${t}`], { stdio: "ignore" }).status === 0,
);
const SANDBOX_OK = BWRAP_OK && TOOLS_OK;
if (process.platform !== "linux" || !SANDBOX_OK) {
  console.warn(
    `broker-mechanism-spike: real-sandbox probes SKIPPED (linux: ${process.platform === "linux"}, bwrap usable: ${BWRAP_OK}, socat/curl/openssl on PATH: ${TOOLS_OK}); the hermetic guard block still runs.`,
  );
}
if (process.platform === "linux" && !SANDBOX_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error(
    `C4_BWRAP_REQUIRED is set but the spike cannot run here (bwrap usable: ${BWRAP_OK}, socat/curl/openssl on PATH: ${TOOLS_OK}).`,
  );
}

// Per-run randomized names and values (harness row H2): nothing here is keyed to a canonical name.
const RND = Math.random().toString(36).slice(2, 8);
const SECRET_VAR = `SPIKE_TOKEN_${RND.toUpperCase()}`;
const ECHO_HOST = `echo-${RND}.spike.test`;
const OTHER_HOST = `other-${RND}.spike.test`;
const VIRTUAL_HOST = `virtual-${RND}.broker.test`;
const SPIKE_SECRET: DeclaredSecret = { id: "spike-token", value: `decoy-spike-${RND}-${Math.random().toString(36).slice(2, 10)}` };
const FWD_TOKEN = `fwd-${RND}-${Math.random().toString(36).slice(2, 10)}`;
const FWD_WORKSPACE = `ws-${RND}`;
const FWD_BASIC = Buffer.from(`${FWD_WORKSPACE}:${FWD_TOKEN}`).toString("base64");
const DECLARED: DeclaredSecret[] = [
  SPIKE_SECRET,
  { id: "forwarder-token", value: FWD_TOKEN },
  { id: "forwarder-basic", value: FWD_BASIC },
  ...AMBIENT_SECRETS,
];

interface EchoRecord {
  host: string;
  path: string;
  tokenHeader: string | undefined;
  tls: boolean;
}
interface GatewayEvent {
  kind: "connect" | "absolute-uri" | "refused";
  target: string;
  proxyAuth: "ok" | "bad" | "none";
}

const OUTCOMES: ProbeOutcome[] = [];
function record(o: ProbeOutcome): void {
  OUTCOMES.push(o);
  const line = `SPIKE_OUTCOME probe=${o.probe} outcome=${o.outcome} evidence=${JSON.stringify(o.evidence)}`;
  console.log(line);
  // A green CI run on `leaks` or `unmeasurable` must not read as a pass.
  if (o.outcome === "leaks" || o.outcome === "unmeasurable") console.log(`::warning::${line}`);
}

describe.skipIf(!SANDBOX_OK)("broker mechanism spike: real sandbox probes (#9543, ADR-311)", () => {
  let root: string;
  let own: string;
  let home: string;
  let shimDir: string;
  let certDir: string;
  let certPath = "";
  let keyPath = "";
  let stub: AnthropicStub;
  let httpEcho: { server: net.Server; port: number };
  let httpsEcho: { server: net.Server; port: number } | undefined;
  let gateway: net.Server;
  let gatewayPort = 0;
  let fwd: ChildProcess | undefined;
  let fwdPort = 0;
  const echoLog: EchoRecord[] = [];
  const gwEvents: GatewayEvent[] = [];
  const nonLoopbackSockets: string[] = [];

  function startEcho(tls: boolean): Promise<{ server: net.Server; port: number }> {
    const handler = (req: IncomingMessage, res: import("node:http").ServerResponse) => {
      const tokenHeader = req.headers["x-spike-token"] as string | undefined;
      echoLog.push({ host: String(req.headers.host ?? ""), path: req.url ?? "", tokenHeader, tls });
      if ((req.url ?? "").startsWith("/reflect")) {
        res.writeHead(200, { "content-type": "text/plain" });
        res.end(`REFLECTED=${tokenHeader ?? ""}\n`);
      } else {
        res.writeHead(200, { "content-type": "text/plain" });
        res.end("ok\n");
      }
    };
    const server: net.Server = tls
      ? createHttpsServer({ cert: readFileSync(certPath), key: readFileSync(keyPath) }, handler)
      : createHttpServer(handler);
    return new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", () => resolve({ server, port: (server.address() as net.AddressInfo).port }));
    });
  }

  // The stub gateway: loopback only, refuses every target but the echo ports and the API stand-in.
  function startGateway(): Promise<void> {
    const allowedPorts = (): Set<number> =>
      new Set([httpEcho.port, ...(httpsEcho ? [httpsEcho.port] : []), stub.port]);
    gateway = net.createServer((client) => {
      if (client.remoteAddress && !["127.0.0.1", "::ffff:127.0.0.1"].includes(client.remoteAddress)) {
        nonLoopbackSockets.push(client.remoteAddress);
      }
      let buf = Buffer.alloc(0);
      const onData = (chunk: Buffer) => {
        buf = Buffer.concat([buf, chunk]);
        const end = buf.indexOf("\r\n\r\n");
        if (end === -1) return;
        client.off("data", onData);
        const head = buf.subarray(0, end).toString("latin1");
        const rest = buf.subarray(end + 4);
        const lines = head.split("\r\n");
        const [method, target] = lines[0].split(" ");
        const authLine = lines.find((l) => /^proxy-authorization:/i.test(l));
        const presented = authLine ? Buffer.from(authLine.split(/\s+/)[2] ?? "", "base64").toString("latin1") : "";
        const proxyAuth: GatewayEvent["proxyAuth"] = !authLine
          ? "none"
          : presented === `${FWD_WORKSPACE}:${FWD_TOKEN}`
            ? "ok"
            : "bad";
        const refuse = () => {
          gwEvents.push({ kind: "refused", target: target ?? "", proxyAuth });
          client.end("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n");
        };
        if (proxyAuth !== "ok") return refuse();
        if (method === "CONNECT") {
          const [host, portStr] = (target ?? "").split(":");
          const port = Number(portStr);
          if (!allowedPorts().has(port) || !(host.endsWith(".spike.test") || host.endsWith(".broker.test") || host === "127.0.0.1")) return refuse();
          gwEvents.push({ kind: "connect", target: target ?? "", proxyAuth });
          const up = net.connect(port, "127.0.0.1", () => {
            client.write("HTTP/1.1 200 Connection established\r\n\r\n");
            if (rest.length) up.write(rest);
            client.pipe(up);
            up.pipe(client);
          });
          up.on("error", () => client.destroy());
          client.on("error", () => up.destroy());
          return;
        }
        // plain-HTTP absolute-URI request
        try {
          const u = new URL(target ?? "");
          const port = Number(u.port || 80);
          if (!allowedPorts().has(port)) return refuse();
          gwEvents.push({ kind: "absolute-uri", target: `${u.hostname}:${port}`, proxyAuth });
          const headLines = [`${method} ${u.pathname}${u.search} HTTP/1.1`, ...lines.slice(1).filter((l) => !/^proxy-/i.test(l))];
          const up = net.connect(port, "127.0.0.1", () => {
            up.write(`${headLines.join("\r\n")}\r\n\r\n`);
            if (rest.length) up.write(rest);
            client.pipe(up);
            up.pipe(client);
          });
          up.on("error", () => client.destroy());
          client.on("error", () => up.destroy());
        } catch {
          refuse();
        }
      };
      client.on("data", onData);
    });
    return new Promise((resolve, reject) => {
      gateway.once("error", reject);
      gateway.listen(0, "127.0.0.1", () => {
        gatewayPort = (gateway.address() as net.AddressInfo).port;
        resolve();
      });
    });
  }

  function startForwarder(): Promise<void> {
    return new Promise((resolve, reject) => {
      const child = spawn("node", [FORWARDER], {
        env: {
          NODE_ENV: "test",
          PATH: savedPath ?? "/usr/bin:/bin",
          EGRESS_GW_HOST: "127.0.0.1",
          EGRESS_GW_PORT: String(gatewayPort),
          EGRESS_SESSION_TOKEN: FWD_TOKEN,
          EGRESS_WORKSPACE_ID: FWD_WORKSPACE,
        },
      });
      fwd = child;
      let out = "";
      const t = setTimeout(() => reject(new Error("forwarder did not report a port")), 10_000);
      child.stdout.on("data", (d: Buffer) => {
        out += d.toString();
        const m = /egress-forwarder-listening (\d+)/.exec(out);
        if (m) {
          clearTimeout(t);
          fwdPort = Number(m[1]);
          resolve();
        }
      });
      child.once("error", reject);
    });
  }

  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "brk-spike-")));
    own = join(root, "00000000-0000-0000-0000-000000000009");
    mkdirSync(own);
    home = realpathSync(mkdtempSync(join(tmpdir(), "brk-spike-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "brk-spike-shim-")));
    certDir = realpathSync(mkdtempSync(join(tmpdir(), "brk-spike-ca-")));
    // 0700, outside every sandbox mount, removed in afterAll; trusted only through `curl --cacert`/-k.
    spawnSync("chmod", ["700", certDir]);
    certPath = join(certDir, "echo.crt");
    keyPath = join(certDir, "echo.key");
    const gen = spawnSync(
      "openssl",
      ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", keyPath, "-out", certPath, "-days", "1",
        "-subj", `/CN=${ECHO_HOST}`, "-addext", `subjectAltName=DNS:${ECHO_HOST},DNS:${OTHER_HOST},DNS:${VIRTUAL_HOST}`],
      { stdio: "ignore", timeout: 30_000 },
    );
    writeFileSync(join(shimDir, "bwrap"), `#!/usr/bin/env bash\nexec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`, { mode: 0o755 });
    stub = await startAnthropicStub("sh ./spike-probe.sh");
    scrubAmbientCliEnv();
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
    httpEcho = await startEcho(false);
    if (gen.status === 0) httpsEcho = await startEcho(true);
    await startGateway();
    await startForwarder();
  }, 60_000);

  afterAll(async () => {
    vi.unstubAllEnvs();
    fwd?.kill("SIGTERM");
    await new Promise<void>((r) => gateway?.close(() => r()));
    httpEcho?.server.close();
    httpsEcho?.server.close();
    await stub?.close();
    for (const dir of [root, root && `${root}-c4-staging`, home, shimDir, certDir]) {
      if (!dir) continue;
      try {
        rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
      } catch {
        /* scratch */
      }
    }
    if (process.env.BROKER_SPIKE_OUT) writeFileSync(process.env.BROKER_SPIKE_OUT, JSON.stringify(OUTCOMES, null, 2));
  });

  interface Arm {
    name: string;
    mask: boolean;
    managed: boolean;
    allowDomains: boolean;
    tls: "none" | "sandbox" | "settings" | "cli";
    /** Trust the echo target's certificate on the host side of the proxy (the runtime's UPSTREAM TLS leg only). */
    trustEchoUpstream?: boolean;
  }

  function sandboxFor(arm: Arm): unknown {
    const base = buildAgentSandboxConfig(own, { allowWebEgress: true }) as unknown as {
      network: Record<string, unknown>;
      credentials: { envVars: unknown[] };
    };
    const network: Record<string, unknown> = {
      ...base.network,
      allowManagedDomainsOnly: arm.managed,
      allowedDomains: arm.allowDomains ? [ECHO_HOST, OTHER_HOST, VIRTUAL_HOST] : [],
      ...(arm.tls === "sandbox" ? { tlsTerminate: {} } : {}),
    };
    const envVars = arm.mask
      ? [...base.credentials.envVars, { name: SECRET_VAR, mode: "mask", injectHosts: [ECHO_HOST] }]
      : base.credentials.envVars;
    return { ...base, network, credentials: { ...base.credentials, envVars } };
  }

  function probeScript(_arm: Arm): string {
    const hp = httpEcho.port;
    const sp = httpsEcho?.port ?? 0;
    const H = `-H "X-Spike-Token: $${SECRET_VAR}"`;
    // Markers are built at runtime so this file's own text (printed by the cwd scan) never contains one.
    return [
      `sec() { printf '\\n<<%s %s>>\\n' SEC "$1"; }`,
      `sec env; env`,
      `sec proc; for p in /proc/[0-9]*; do cat $p/environ 2>/dev/null | tr '\\0' '\\n'; done`,
      `sec cwdfiles; ls -la . 2>&1; grep -rIs . . 2>/dev/null | head -50`,
      `sec http-echo; curl -sS -m 15 -o /dev/null -w 'CODE=%{http_code}\\n' ${H} http://${ECHO_HOST}:${hp}/ 2>&1`,
      `sec http-other; curl -sS -m 15 -o /dev/null -w 'CODE=%{http_code}\\n' ${H} http://${OTHER_HOST}:${hp}/ 2>&1`,
      `sec reflect; curl -sS -m 15 ${H} http://${ECHO_HOST}:${hp}/reflect 2>&1`,
      `sec https-echo; ${sp ? `curl -skv -m 20 ${H} -o /dev/null https://${ECHO_HOST}:${sp}/ 2>&1 | grep -E 'issuer:|subject:|HTTP/|curl:|SSL' | sed 's/[[:space:]]\\+/ /g'` : "echo NO_TLS_TARGET"}`,
      `sec virtual; curl -sS -m 15 -o /dev/null -w 'CODE=%{http_code}\\n' http://${VIRTUAL_HOST}:${hp}/ 2>&1`,
      `printf 'SPIKE_%s\\n' DONE`,
    ].join("\n");
  }

  interface ArmResult {
    done: boolean;
    sections: Record<string, string>;
    observations: Observation[];
    queryError?: string;
  }

  async function runArm(arm: Arm): Promise<{ result: ArmResult; echo: EchoRecord[]; gw: GatewayEvent[] }> {
    echoLog.length = 0;
    gwEvents.length = 0;
    writeFileSync(join(own, "spike-probe.sh"), probeScript(arm), { mode: 0o644 });
    const proxyUrl = `http://${FWD_WORKSPACE}:${FWD_TOKEN}@127.0.0.1:${fwdPort}`;
    const childEnv: Record<string, string> = {
      PATH: `${shimDir}:${savedPath ?? "/usr/bin:/bin"}`,
      HOME: home,
      LANG: "C.UTF-8",
      ANTHROPIC_BASE_URL: `http://127.0.0.1:${stub.port}`,
      ANTHROPIC_API_KEY: "decoy-api-key-spike",
      NO_PROXY: "127.0.0.1,localhost",
      no_proxy: "127.0.0.1,localhost",
      HTTP_PROXY: proxyUrl,
      HTTPS_PROXY: proxyUrl,
      http_proxy: proxyUrl,
      https_proxy: proxyUrl,
      DISABLE_TELEMETRY: "1",
      DISABLE_AUTOUPDATER: "1",
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
      WORKSPACES_ROOT: root,
      C4_RENDER_STAGING_ROOT: `${root}-c4-staging`,
      SOLEUR_BWRAP_REAL: "/usr/bin/bwrap",
      SOLEUR_BWRAP_SECCOMP_BPF: BWRAP_BPF,
      [SECRET_VAR]: SPIKE_SECRET.value,
      // Public certificate only, scoped to this one arm's CLI child: lets the runtime's upstream TLS leg
      // accept the echo target. Never the system store, never a private key.
      ...(arm.trustEchoUpstream ? { NODE_EXTRA_CA_CERTS: certPath } : {}),
    };
    const sandbox = sandboxFor(arm);
    const options: Record<string, unknown> = {
      abortController: new AbortController(),
      // Haiku 4.5 on purpose (same ground as sandbox-credential-deny-runtime.test.ts): this drives the
      // REAL Agent SDK query(), whose bundled CLI is the pinned @anthropic-ai/claude-agent-sdk 0.3.284
      // and does not know claude-haiku-5-5; plugins/soleur/test/model-launch-review.test.ts expires it.
      model: "claude-haiku-4-5-20251001",
      maxTurns: 3,
      permissionMode: "default",
      cwd: own,
      allowedTools: ["Bash"],
      settingSources: [],
      env: childEnv,
      sandbox,
      canUseTool: async (_n: string, input: unknown) => ({ behavior: "allow", updatedInput: input }),
    };
    if (arm.tls === "settings") options.settings = { sandbox: { network: { tlsTerminate: {} } } };
    if (arm.tls === "cli") options.extraArgs = { settings: JSON.stringify({ sandbox: { network: { tlsTerminate: {} } } }) };

    let text = "";
    let queryError: string | undefined;
    const controller = options.abortController as AbortController;
    try {
      const q = query({ prompt: "probe", options: options as never });
      for await (const msg of q) {
        if (msg.type === "user") {
          text += JSON.stringify((msg as { message?: { content?: unknown } }).message?.content ?? "");
        }
      }
    } catch (e) {
      queryError = e instanceof Error ? e.message.slice(0, 200) : "query failed";
    } finally {
      controller.abort();
    }
    // The tool result is JSON-escaped inside the message content; undo the escaping once.
    const flat = text.replace(/\\n/g, "\n").replace(/\\t/g, "\t").replace(/\\"/g, '"');
    const sections: Record<string, string> = {};
    for (const m of flat.matchAll(/<<SEC ([a-z-]+)>>([\s\S]*?)(?=<<SEC |SPIKE_DONE|$)/g)) {
      if (!(m[1] in sections)) sections[m[1]] = m[2];
    }
    if (process.env.BROKER_SPIKE_DEBUG) {
      console.log(`SPIKE_DEBUG arm=${arm.name} flatLen=${flat.length} rawLen=${text.length} keys=${JSON.stringify(Object.entries(sections).map(([k, v]) => [k, v.length]))} decoyInFlat=${flat.includes(SPIKE_SECRET.value)} decoyInRaw=${text.includes(SPIKE_SECRET.value)} head=${JSON.stringify(text.slice(0, 160))}`);
    }
    const observations: Observation[] = [
      { surface: "env", text: sections["env"] ?? "" },
      { surface: "proc-environ", text: sections["proc"] ?? "" },
      { surface: "cwd-files", text: sections["cwdfiles"] ?? "" },
      { surface: "reflect-output", text: sections["reflect"] ?? "" },
      { surface: "http-output", text: `${sections["http-echo"] ?? ""}${sections["http-other"] ?? ""}${sections["https-echo"] ?? ""}${sections["virtual"] ?? ""}` },
    ];
    return {
      result: { done: flat.includes("SPIKE_DONE"), sections, observations, queryError },
      echo: [...echoLog],
      gw: [...gwEvents],
    };
  }

  function hostOf(r: EchoRecord): string {
    return r.host.split(":")[0];
  }

  let virtualReached = false;

  function concludeMask(arm: Arm, run: Awaited<ReturnType<typeof runArm>>, proto: "http" | "https"): ProbeOutcome {
    const probe = arm.tls === "none" ? `${arm.name}:${proto}` : `a-mask-under-${arm.name}:${proto}`;
    const { result, echo, gw } = run;
    const events: string[] = [];
    if (result.done) events.push("sandbox-bash-completed");
    for (const e of echo) events.push(`echo-received host=${hostOf(e).replace(RND, "<rnd>")} tls=${e.tls} token=${e.tokenHeader === SPIKE_SECRET.value ? "REAL" : e.tokenHeader ? "other-value" : "absent"}`);
    for (const g of gw) events.push(`gateway ${g.kind} ${g.target.replace(RND, "<rnd>")} auth=${g.proxyAuth}`);
    if (result.queryError) events.push(`query-error: ${result.queryError}`);
    if (echo.some((e) => hostOf(e) === VIRTUAL_HOST)) virtualReached = true;
    if (!result.done) {
      return unmeasurable(probe, "the sandboxed probe did not complete", events.length ? events : ["no events"]);
    }
    if (echo.length === 0 && gw.length === 0) {
      return unmeasurable(probe, "no request reached the gateway or the echo target; the proxy chain was not exercised", events);
    }
    const wantTls = proto === "https";
    const forProto = echo.filter((e) => e.tls === wantTls && hostOf(e) === ECHO_HOST);
    if (forProto.length === 0) {
      const err = (result.sections["https-echo"] ?? result.sections["http-echo"] ?? "").replace(/\s+/g, " ").replace(ECHO_HOST, "<echo-host>").slice(0, 200);
      return unmeasurable(probe, `no ${proto} request reached the echo target (client saw: ${err.trim() || "nothing"})`, events);
    }
    const scan = scanSandboxSurfaces(result.observations, DECLARED);
    const realOnEcho = forProto.some((e) => e.tokenHeader === SPIKE_SECRET.value);
    const evidence = [...events];
    if (echo.some((e) => hostOf(e) !== ECHO_HOST && e.tokenHeader === SPIKE_SECRET.value)) {
      evidence.push("real value delivered to a host outside injectHosts");
    }
    return classifyOutcome({ probe, observedEvents: events, scan, substitutionObserved: realOnEcho, evidence });
  }

  // Probe (c): the oracle is the issuer the sandboxed client saw, not the mask result.
  function concludeTls(arm: Arm, run: Awaited<ReturnType<typeof runArm>>): ProbeOutcome {
    const probe = `c-${arm.name}`;
    const issuer = /issuer:[^\n]*/.exec(run.result.sections["https-echo"] ?? "")?.[0]?.trim();
    const events: string[] = [];
    if (run.result.done) events.push("sandbox-bash-completed");
    events.push(`issuer-seen=${issuer ? JSON.stringify(issuer.replace(ECHO_HOST, "<echo-host>").slice(0, 100)) : "none"}`);
    if (!run.result.done || !issuer) {
      return unmeasurable(probe, "no certificate issuer was observed from the sandbox", events);
    }
    if (arm.tls === "cli") {
      return issuer.includes("sandbox-runtime")
        ? classifyOutcome({ probe, observedEvents: events, scan: [], substitutionObserved: true })
        : unmeasurable(probe, "extraArgs --settings: cannot distinguish 'not forwarded to the CLI' from 'not honored'", events);
    }
    return classifyOutcome({
      probe,
      observedEvents: events,
      scan: [],
      substitutionObserved: issuer.includes("sandbox-runtime"),
    });
  }

  const ARMS: Arm[] = [
    { name: "control-no-mask", mask: false, managed: true, allowDomains: false, tls: "none" },
    { name: "a-mask-prod-config", mask: true, managed: true, allowDomains: true, tls: "none" },
    { name: "a-mask-unmanaged", mask: true, managed: false, allowDomains: true, tls: "none" },
    { name: "tls-options.sandbox", mask: true, managed: false, allowDomains: true, tls: "sandbox" },
    { name: "tls-options.settings", mask: true, managed: false, allowDomains: true, tls: "settings" },
    { name: "tls-cli-settings-control", mask: true, managed: false, allowDomains: true, tls: "cli" },
    { name: "tls-options.sandbox+upstream-trusted", mask: true, managed: false, allowDomains: true, tls: "sandbox", trustEchoUpstream: true },
  ];

  it("harness: SDK version is the pinned 0.3.284 the ADR names", () => {
    expect(SDK_PKG.dependencies?.["@anthropic-ai/claude-agent-sdk"]).toBe("0.3.284");
  });

  // Probe (c) runs first: it decides whether the HTTPS arms of probe (a) are meaningful.
  for (const arm of [ARMS[0], ARMS[3], ARMS[4], ARMS[5], ARMS[1], ARMS[2], ARMS[6]]) {
    it(`arm ${arm.name}`, async () => {
      const run = await runArm(arm);
      const outcome = concludeMask(arm, run, "http");
      record(outcome);
      if (arm.name !== "control-no-mask") record(concludeMask(arm, run, "https"));
      if (arm.tls !== "none" && !arm.trustEchoUpstream) record(concludeTls(arm, run));
      // Probe (b) facts, recorded from every arm that reached the gateway.
      const issuer = /issuer:[^\n]*/.exec(run.result.sections["https-echo"] ?? "")?.[0] ?? "no issuer line";
      console.log(`SPIKE_FACT arm=${arm.name} https-issuer=${JSON.stringify(issuer.slice(0, 120))} gw=${JSON.stringify(run.gw)} echo=${run.echo.length}`);
      if (arm.name === "control-no-mask") {
        // Positive control: the scan must be able to find the decoy (it is plainly in the sandbox env).
        expect(outcome.outcome).toBe("leaks");
        expect(outcome.evidence.join(" ")).toContain("spike-token");
      }
      expect(run.result.observations.length).toBeGreaterThan(0);
    }, 180_000);
  }

  it("harness: no gateway socket came from a non-loopback address", () => {
    expect(nonLoopbackSockets).toEqual([]);
  });

  it("probe (b): records what the forwarder could serve and whether the sandbox saw the proxy-hop credential", () => {
    const issuerOf = (o: ProbeOutcome) => o.evidence.join(" ");
    const proxyCredLeaks = OUTCOMES.filter((o) => issuerOf(o).includes("secret forwarder-"));
    const events = OUTCOMES.flatMap((o) => o.evidence.filter((e) => e.startsWith("gateway ")));
    if (events.length === 0) {
      record(unmeasurable("b-virtual-host", "no request reached the gateway in any arm", ["gateway events: 0"]));
      return;
    }
    record(
      classifyOutcome({
        probe: "b-virtual-host",
        observedEvents: events,
        scan: proxyCredLeaks.length ? [{ surface: "sandbox", secretId: "forwarder-token" }] : [],
        // Reachable means the gateway authenticated the forwarder-injected credential on a request the sandbox made.
        substitutionObserved: events.some((e) => e.includes("auth=ok")),
        evidence: [
          "the forwarder derives tenant and token from its own environment, not from the inbound credential (infra/egress-forwarder.mjs)",
          `virtual-host request ${virtualReached ? "reached" : "did not reach"} its destination through forwarder and gateway`,
          `proxy-hop credential visible to the sandbox: ${proxyCredLeaks.length ? "YES" : "no"}`,
        ],
      }),
    );
  });
});
