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
import { createServer as createHttpServer, type IncomingMessage, type ServerResponse } from "node:http";
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

  it("guard row 2: a probe that observed nothing is a vacuous run, not a pass", () => {
    expect(() =>
      classifyOutcome({ probe: "a", observedEvents: [], scan: [], substitutionObserved: true }),
    ).toThrow(VacuousProbeError);
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
//
// Every outcome is concluded only after its premises are proven: the sandbox bash completed, the
// sandbox env shows the secret variable (the sentinel on a mask arm, the decoy on the control), and
// a request actually reached the destination. A missing premise records `unmeasurable`, never a
// conclusion. Scanned surfaces here: the sandbox env, readable /proc/*/environ, working-directory
// files, the reflected response body, curl output, and a catch-all over the whole tool result.
// Glob and Grep tool output is exercised only in the hermetic block above.
//
// BROKER_SPIKE_OUT=<path> writes the recorded outcomes as JSON (used to produce the measurements record).
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
  tokenHeader: string | undefined;
  tls: boolean;
}
interface GatewayEvent {
  kind: "connect" | "absolute-uri" | "refused";
  target: string;
  proxyAuth: "ok" | "bad" | "none";
}
interface Arm {
  name: string;
  mask: boolean;
  managed: boolean;
  allowDomains: boolean;
  tls: "none" | "sandbox" | "settings";
}

const OUTCOMES: ProbeOutcome[] = [];
function record(o: ProbeOutcome): void {
  OUTCOMES.push(o);
  const line = `SPIKE_OUTCOME probe=${o.probe} outcome=${o.outcome} evidence=${JSON.stringify(o.evidence)}`;
  console.log(line);
  // A green CI run on `leaks` or `unmeasurable` must not read as a pass (the control arm leaks by design).
  if ((o.outcome === "leaks" || o.outcome === "unmeasurable") && !o.probe.startsWith("control")) {
    console.log(`::warning::${line}`);
  }
}

// Probe (c) runs first: it decides whether the HTTPS arms of probe (a) are meaningful.
const ARMS: Arm[] = [
  { name: "tls-options.sandbox", mask: true, managed: false, allowDomains: true, tls: "sandbox" },
  { name: "tls-options.settings", mask: true, managed: false, allowDomains: true, tls: "settings" },
  { name: "control-no-mask", mask: false, managed: true, allowDomains: false, tls: "none" },
  { name: "mask-managed-domains-on", mask: true, managed: true, allowDomains: true, tls: "none" },
  { name: "mask-managed-domains-off", mask: true, managed: false, allowDomains: true, tls: "none" },
];

/** Facts accumulated across arms for probe (b). */
const SEEN = { virtualEchoed: false, virtualGateway: false, proxyCredHits: 0, plainAtEcho: 0, absoluteUriAtGateway: 0 };

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
  let httpsEcho: { server: net.Server; port: number };
  let gateway: net.Server;
  let gatewayPort = 0;
  let fwd: ChildProcess | undefined;
  let fwdPort = 0;
  const echoLog: EchoRecord[] = [];
  const gwEvents: GatewayEvent[] = [];

  function startEcho(tls: boolean): Promise<{ server: net.Server; port: number }> {
    const handler = (req: IncomingMessage, res: ServerResponse) => {
      const tokenHeader = req.headers["x-spike-token"] as string | undefined;
      echoLog.push({ host: String(req.headers.host ?? ""), tokenHeader, tls });
      res.writeHead(200, { "content-type": "text/plain" });
      res.end((req.url ?? "").startsWith("/reflect") ? `REFLECTED=${tokenHeader ?? ""}\n` : "ok\n");
    };
    const server: net.Server = tls
      ? createHttpsServer({ cert: readFileSync(certPath), key: readFileSync(keyPath) }, handler)
      : createHttpServer(handler);
    return new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", () => resolve({ server, port: (server.address() as net.AddressInfo).port }));
    });
  }

  // Wire a client socket to an upstream loopback port (shared by the CONNECT and absolute-URI paths).
  function tunnel(client: net.Socket, port: number, onUp: (up: net.Socket) => void): void {
    const up = net.connect(port, "127.0.0.1", () => {
      onUp(up);
      client.pipe(up);
      up.pipe(client);
    });
    up.on("error", () => client.destroy());
    client.on("error", () => up.destroy());
  }

  // The stub gateway: loopback only, refuses every target but the echo ports and the API stand-in.
  function startGateway(): Promise<void> {
    const allowedPorts = new Set([httpEcho.port, httpsEcho.port, stub.port]);
    gateway = net.createServer((client) => {
      let buf = Buffer.alloc(0);
      const onData = (chunk: Buffer) => {
        buf = Buffer.concat([buf, chunk]);
        const end = buf.indexOf("\r\n\r\n");
        if (end === -1) return;
        client.off("data", onData);
        const lines = buf.subarray(0, end).toString("latin1").split("\r\n");
        const rest = buf.subarray(end + 4);
        const [method, target] = lines[0].split(" ");
        const authLine = lines.find((l) => /^proxy-authorization:/i.test(l));
        const presented = authLine ? Buffer.from(authLine.split(/\s+/)[2] ?? "", "base64").toString("latin1") : "";
        const proxyAuth: GatewayEvent["proxyAuth"] = !authLine ? "none" : presented === `${FWD_WORKSPACE}:${FWD_TOKEN}` ? "ok" : "bad";
        const refuse = () => {
          gwEvents.push({ kind: "refused", target: target ?? "", proxyAuth });
          client.end("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n");
        };
        if (proxyAuth !== "ok") return refuse();
        if (method === "CONNECT") {
          const [host, portStr] = (target ?? "").split(":");
          const port = Number(portStr);
          if (!allowedPorts.has(port) || !(host.endsWith(".spike.test") || host.endsWith(".broker.test") || host === "127.0.0.1")) {
            return refuse();
          }
          gwEvents.push({ kind: "connect", target: target ?? "", proxyAuth });
          tunnel(client, port, (up) => {
            client.write("HTTP/1.1 200 Connection established\r\n\r\n");
            if (rest.length) up.write(rest);
          });
          return;
        }
        // plain-HTTP absolute-URI request
        try {
          const u = new URL(target ?? "");
          const port = Number(u.port || 80);
          if (!allowedPorts.has(port)) return refuse();
          gwEvents.push({ kind: "absolute-uri", target: `${u.hostname}:${port}`, proxyAuth });
          const head = [`${method} ${u.pathname}${u.search} HTTP/1.1`, ...lines.slice(1).filter((l) => !/^proxy-/i.test(l))];
          tunnel(client, port, (up) => {
            up.write(`${head.join("\r\n")}\r\n\r\n`);
            if (rest.length) up.write(rest);
          });
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

  // Markers are built at runtime so this file's own text (printed by the cwd scan) never contains one.
  function probeScript(): string {
    const hp = httpEcho.port;
    const sp = httpsEcho.port;
    const H = `-H "X-Spike-Token: $${SECRET_VAR}"`;
    return [
      `sec() { printf '\\n<<%s %s>>\\n' SEC "$1"; }`,
      `sec env; env`,
      `sec proc; for p in /proc/[0-9]*; do cat $p/environ 2>/dev/null | tr '\\0' '\\n'; done`,
      `sec cwdfiles; ls -la . 2>&1; grep -rasn . . 2>/dev/null | head -200`,
      `sec http-echo; curl -sS -m 15 -o /dev/null -w 'CODE=%{http_code}\\n' ${H} http://${ECHO_HOST}:${hp}/ 2>&1`,
      `sec http-other; curl -sS -m 15 -o /dev/null -w 'CODE=%{http_code}\\n' ${H} http://${OTHER_HOST}:${hp}/ 2>&1`,
      `sec reflect; curl -sS -m 15 ${H} http://${ECHO_HOST}:${hp}/reflect 2>&1`,
      `sec https-echo; curl -skv -m 20 ${H} -o /dev/null https://${ECHO_HOST}:${sp}/ 2>&1 | grep -E 'issuer:|subject:|HTTP/|curl:|SSL' | sed 's/[[:space:]]\\+/ /g'`,
      `sec virtual; curl -sS -m 15 -o /dev/null -w 'CODE=%{http_code}\\n' http://${VIRTUAL_HOST}:${hp}/ 2>&1`,
      `printf 'SPIKE_%s\\n' DONE`,
    ].join("\n");
  }

  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "brk-spike-")));
    own = join(root, "00000000-0000-0000-0000-000000000009");
    mkdirSync(own);
    home = realpathSync(mkdtempSync(join(tmpdir(), "brk-spike-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "brk-spike-shim-")));
    // Throwaway self-signed key, scoped to the test hostnames, removed in afterAll (and the key file
    // itself right after the echo target has read it). mkdtemp creates it 0700; the sandbox runs as the
    // same uid, so the mode is hygiene, not a sandbox boundary.
    certDir = realpathSync(mkdtempSync(join(tmpdir(), "brk-spike-ca-")));
    certPath = join(certDir, "echo.crt");
    keyPath = join(certDir, "echo.key");
    const gen = spawnSync(
      "openssl",
      ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", keyPath, "-out", certPath, "-days", "1",
        "-subj", `/CN=${ECHO_HOST}`, "-addext", `subjectAltName=DNS:${ECHO_HOST},DNS:${OTHER_HOST},DNS:${VIRTUAL_HOST}`],
      { stdio: "ignore", timeout: 30_000 },
    );
    if (gen.status !== 0) throw new Error(`openssl could not generate the test certificate (status ${gen.status})`);
    writeFileSync(join(shimDir, "bwrap"), `#!/usr/bin/env bash\nexec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`, { mode: 0o755 });
    stub = await startAnthropicStub("sh ./spike-probe.sh");
    scrubAmbientCliEnv();
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
    httpEcho = await startEcho(false);
    httpsEcho = await startEcho(true);
    rmSync(keyPath, { force: true });
    await startGateway();
    await startForwarder();
    writeFileSync(join(own, "spike-probe.sh"), probeScript(), { mode: 0o644 });
  }, 60_000);

  afterAll(async () => {
    vi.unstubAllEnvs();
    fwd?.kill("SIGTERM");
    await Promise.race([new Promise<void>((r) => gateway?.close(() => r())), new Promise<void>((r) => setTimeout(r, 2_000))]);
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

  // The text of the tool results in a stream message (the tool_result block content is a string).
  function resultText(content: unknown): string {
    if (!Array.isArray(content)) return typeof content === "string" ? content : "";
    return content
      .map((b: { type?: string; content?: unknown }) => {
        if (b?.type !== "tool_result") return "";
        if (typeof b.content === "string") return b.content;
        return Array.isArray(b.content) ? b.content.map((c: { text?: string }) => c?.text ?? "").join("") : "";
      })
      .join("");
  }

  async function runArm(arm: Arm) {
    echoLog.length = 0;
    gwEvents.length = 0;
    const standInBefore = stub.requests();
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
    };
    const controller = new AbortController();
    const options: Record<string, unknown> = {
      abortController: controller,
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
      sandbox: sandboxFor(arm),
      canUseTool: async (_n: string, input: unknown) => ({ behavior: "allow", updatedInput: input }),
    };
    if (arm.tls === "settings") options.settings = { sandbox: { network: { tlsTerminate: {} } } };

    let flat = "";
    let queryError: string | undefined;
    try {
      for await (const msg of query({ prompt: "probe", options: options as never })) {
        if (msg.type === "user") flat += resultText((msg as { message?: { content?: unknown } }).message?.content);
      }
    } catch (e) {
      queryError = e instanceof Error ? e.message.slice(0, 200) : "query failed";
    } finally {
      controller.abort();
    }
    const sections: Record<string, string> = {};
    for (const m of flat.matchAll(/<<SEC ([a-z-]+)>>([\s\S]*?)(?=<<SEC |SPIKE_DONE|$)/g)) {
      if (!(m[1] in sections)) sections[m[1]] = m[2];
    }
    const observations: Observation[] = [
      { surface: "env", text: sections["env"] ?? "" },
      { surface: "proc-environ", text: sections["proc"] ?? "" },
      { surface: "cwd-files", text: sections["cwdfiles"] ?? "" },
      { surface: "reflect-output", text: sections["reflect"] ?? "" },
      { surface: "http-output", text: ["http-echo", "http-other", "https-echo", "virtual"].map((k) => sections[k] ?? "").join("") },
      { surface: "tool-result", text: flat },
    ];
    return {
      done: flat.includes("SPIKE_DONE"),
      sections,
      observations,
      queryError,
      standInRequests: stub.requests() - standInBefore,
      echo: [...echoLog],
      gw: [...gwEvents],
    };
  }
  type Run = Awaited<ReturnType<typeof runArm>>;

  const hostOf = (r: EchoRecord): string => r.host.split(":")[0];
  const masked = (s: string): string => s.split(RND).join("<rnd>");

  // What the sandbox env must show before any conclusion: the secret variable, holding the decoy on the
  // control arm and a non-real placeholder (the sentinel) on a mask arm. Returns the failed premise.
  function envPremise(arm: Arm, run: Run): string | undefined {
    const env = run.sections["env"] ?? "";
    if (env.trim() === "") return "the sandbox env section is empty";
    const line = env.split("\n").find((l) => l.startsWith(`${SECRET_VAR}=`));
    if (line === undefined) return "the secret variable is absent from the sandbox env";
    const value = line.slice(SECRET_VAR.length + 1);
    if (arm.mask) {
      if (value === "") return "the masked variable is empty in the sandbox env";
      if (value === SPIKE_SECRET.value) return "the masked variable still holds the real value in the sandbox env";
    } else if (value !== SPIKE_SECRET.value) {
      return "the control variable does not hold the decoy in the sandbox env";
    }
    return undefined;
  }

  function baseEvents(run: Run): string[] {
    const events: string[] = [];
    if (run.done) events.push("sandbox-bash-completed");
    events.push(`api-stand-in-requests=${run.standInRequests}`);
    for (const e of run.echo) {
      const token = e.tokenHeader === SPIKE_SECRET.value ? "REAL" : e.tokenHeader ? "other-value" : "absent";
      events.push(`echo-received host=${masked(hostOf(e))} tls=${e.tls} token=${token}`);
    }
    for (const g of run.gw) events.push(`gateway ${g.kind} ${masked(g.target)} auth=${g.proxyAuth}`);
    if (run.queryError) events.push(`query-error: ${run.queryError}`);
    return events;
  }

  function concludeMask(arm: Arm, run: Run, proto: "http" | "https", scan: Hit[], premise: string | undefined): ProbeOutcome {
    const probe = arm.tls === "none" ? `${arm.name}:${proto}` : `mask-under-${arm.name}:${proto}`;
    const events = baseEvents(run);
    // A visible secret is reported first: a leak in an arm whose requests never landed is still a leak.
    if (scan.length > 0) {
      return classifyOutcome({ probe, observedEvents: events.length ? events : ["sandbox-output-observed"], scan, substitutionObserved: false });
    }
    if (!run.done) return unmeasurable(probe, "the sandboxed probe did not complete", events);
    if (premise) return unmeasurable(probe, `premise failed: ${premise}`, events);
    if (run.echo.length === 0 && run.gw.length === 0) {
      return unmeasurable(probe, "no request reached the gateway or the echo target; the proxy chain was not exercised", events);
    }
    const forProto = run.echo.filter((e) => e.tls === (proto === "https") && hostOf(e) === ECHO_HOST);
    if (forProto.length === 0) {
      const seen = masked(run.sections[proto === "https" ? "https-echo" : "http-echo"] ?? "").replace(/\s+/g, " ").replace(ECHO_HOST, "<echo-host>").slice(0, 200);
      return unmeasurable(probe, `no ${proto} request reached the echo target (client saw: ${seen.trim() || "nothing"})`, events);
    }
    // The real value delivered to a host outside injectHosts is a leak by definition.
    if (run.echo.some((e) => hostOf(e) !== ECHO_HOST && e.tokenHeader === SPIKE_SECRET.value)) {
      return classifyOutcome({
        probe,
        observedEvents: events,
        scan: [{ surface: "destination-host-outside-injectHosts", secretId: SPIKE_SECRET.id }],
        substitutionObserved: false,
      });
    }
    return classifyOutcome({
      probe,
      observedEvents: events,
      scan,
      substitutionObserved: forProto.some((e) => e.tokenHeader === SPIKE_SECRET.value),
    });
  }

  // Probe (c): the oracle is the issuer the sandboxed client saw, not the mask result.
  function concludeTls(arm: Arm, run: Run): ProbeOutcome {
    const probe = `c-${arm.name}`;
    const issuer = /issuer:[^\n]*/.exec(run.sections["https-echo"] ?? "")?.[0]?.trim();
    const events = [...(run.done ? ["sandbox-bash-completed"] : []), `issuer-seen=${issuer ? JSON.stringify(masked(issuer).slice(0, 100)) : "none"}`];
    if (!run.done || !issuer) return unmeasurable(probe, "no certificate issuer was observed from the sandbox", events);
    return classifyOutcome({ probe, observedEvents: events, scan: [], substitutionObserved: issuer.includes("sandbox-runtime") });
  }

  it("harness: SDK version is the pinned 0.3.284 the ADR names, and every server binds loopback", () => {
    expect(SDK_PKG.dependencies?.["@anthropic-ai/claude-agent-sdk"]).toBe("0.3.284");
    for (const s of [httpEcho.server, httpsEcho.server, gateway]) {
      expect((s.address() as net.AddressInfo).address).toBe("127.0.0.1");
    }
  });

  for (const arm of ARMS) {
    it(`arm ${arm.name}`, async () => {
      const run = await runArm(arm);
      const scan = scanSandboxSurfaces(run.observations, DECLARED);
      // A real token visible in the sandbox is a hard failure, not a recorded outcome.
      expect(scan.filter((h) => h.secretId.startsWith("ambient:"))).toEqual([]);
      SEEN.proxyCredHits += scan.filter((h) => h.secretId.startsWith("forwarder-")).length;
      const virtualHere = run.echo.some((e) => hostOf(e) === VIRTUAL_HOST);
      SEEN.virtualEchoed ||= virtualHere;
      // The runtime multiplexes sequential plain-HTTP requests over one forwarder connection, so the
      // gateway cannot attribute a single request: an authenticated gateway connection in the same arm
      // as the virtual-host request is the strongest signal observable, and the counts below say so.
      SEEN.virtualGateway ||= virtualHere && run.gw.some((g) => g.proxyAuth === "ok");
      SEEN.plainAtEcho += run.echo.filter((e) => !e.tls).length;
      SEEN.absoluteUriAtGateway += run.gw.filter((g) => g.kind === "absolute-uri").length;
      const premise = envPremise(arm, run);
      record(concludeMask(arm, run, "http", scan, premise));
      if (arm.mask) record(concludeMask(arm, run, "https", scan, premise));
      if (arm.tls !== "none") record(concludeTls(arm, run));
    }, 180_000);
  }

  it("probe (b): a virtual-host request reaches its destination through the forwarder and gateway, and the sandbox cannot see the proxy-hop credential", () => {
    const evidence = [
      "the forwarder derives tenant and token from its own environment and requires a matching inbound token (infra/egress-forwarder.mjs); the virtual host is an ordinary allowed hostname on the egress path, not a broker endpoint",
      `proxy-hop credential visible to the sandbox: ${SEEN.proxyCredHits > 0 ? "YES" : "no"}`,
      `gateway attribution is per connection, not per request: ${SEEN.plainAtEcho} plain-HTTP requests reached the echo target over ${SEEN.absoluteUriAtGateway} gateway absolute-URI connections`,
    ];
    if (!SEEN.virtualEchoed) {
      record(unmeasurable("b-virtual-host", "no arm's virtual-host request reached its destination", evidence));
      return;
    }
    record(
      classifyOutcome({
        probe: "b-virtual-host",
        observedEvents: [
          "virtual-host request reached its destination through the forwarder and gateway",
          `gateway authenticated the forwarder credential on a connection in the arm that carried the virtual-host request: ${SEEN.virtualGateway}`,
        ],
        scan: SEEN.proxyCredHits > 0 ? [{ surface: "sandbox", secretId: "forwarder-credential" }] : [],
        substitutionObserved: SEEN.virtualGateway,
        evidence,
      }),
    );
  });

  it("outcome floor: every arm produced an outcome, the control leaked on the env surface, and the mask and TLS arms reached conclusions", () => {
    for (const arm of ARMS) {
      expect(OUTCOMES.some((o) => o.probe.includes(arm.name)), `arm ${arm.name} produced no outcome`).toBe(true);
    }
    const control = OUTCOMES.find((o) => o.probe === "control-no-mask:http");
    expect(control?.outcome, "the control arm must leak (the scan can find a secret)").toBe("leaks");
    expect(control?.evidence.join(" ")).toContain("secret spike-token visible on surface env");
    const maskConcluded = OUTCOMES.filter((o) => o.probe.includes("mask") && !o.probe.startsWith("control") && o.outcome !== "unmeasurable");
    expect(maskConcluded.length, "at least one mask arm must reach a conclusion").toBeGreaterThan(0);
    const tls = OUTCOMES.find((o) => o.probe === "c-tls-options.sandbox");
    expect(tls?.outcome, "the TLS-termination oracle arm must reach a conclusion").not.toBe("unmeasurable");
  });
});
