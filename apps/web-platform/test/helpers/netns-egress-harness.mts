// #12585 — child harness for sandbox-network-access-runtime.test.ts. Runs UNDER `unshare -rnm` (user + network + mount
// namespaces), so the only network is a private loopback this script sets up, and a connection that leaves without
// transiting the egress forwarder lands on a recording decoy instead of the internet (CTO T7).
//
//   unshare -rnm node_modules/.bin/tsx --tsconfig tsconfig.json test/helpers/netns-egress-harness.mts <spec.json>
//
// It hosts the real Agent SDK `query()`, the scripted Anthropic stub, the PRODUCTION egress forwarder (started through
// `spawnEgressForwarder`), a recording "gateway" in the squid gateway's place (records each request line and the
// Proxy-Authorization the forwarder injected, then answers 403, never dialling upstream) and decoy listeners on the
// addresses a direct route would reach. vitest cannot sit inside a namespace itself, so every observation is reported
// back as one stdout line per record: `NETNS_STEP0 <json>` and then `NETNS_ARM <json>` per arm. Every other stdout line
// (the server logger writes there) is noise to the parent.
//
// spec.json: { appRoot, scratch, tap: "allow-all" | "production", arms: string[] }
//   tap "allow-all"  : a test-local canUseTool that allows SandboxNetworkAccess (Phase 1a: measures the SDK's routing
//                      after an allow, independent of the arm).
//   tap "production" : the production createCanUseTool, wrapped by a recording tap (Phase 1b).

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import net from "node:net";
import { join } from "node:path";

type Tap = "allow-all" | "production";
interface Spec {
  appRoot: string;
  scratch: string;
  tap: Tap;
  arms: string[];
}
interface TapCall {
  tool: string;
  input: unknown;
  behavior: string;
  message?: string;
  agentID?: string;
}
interface GatewayRecord {
  line: string;
  auth: string;
}
interface DecoyHit {
  addr: string;
  port: number;
}

const spec: Spec = JSON.parse(readFileSync(process.argv[2], "utf8"));
const emit = (kind: "NETNS_STEP0" | "NETNS_ARM", o: unknown) => process.stdout.write(`\n${kind} ${JSON.stringify(o)}\n`);
const sh = (cmd: string, args: string[]) => {
  const r = spawnSync(cmd, args, { encoding: "utf8", timeout: 20_000 });
  return { status: r.status, out: `${r.stdout ?? ""}${r.stderr ?? ""}`.trim().slice(0, 400) };
};

// ---- step 0: the namespace itself (required; a failure here is reported, the parent decides red vs UNVERIFIED) ----
// 198.51.100.1 (TEST-NET-2) is the "open web" decoy: the SDK sets the SANDBOXED command's NO_PROXY to loopback plus every
// RFC 1918 and link-local range (measured on 0.3.321), so a decoy on 10.0.0.1 would only be reached by a command that
// bypasses the proxy, never by the proxy's own direct route. 10.0.0.2 hosts arm D's stub (the CLI's env, not the sandbox's).
const DECOY_IP = "198.51.100.1";
const ALIASES = [`${DECOY_IP}/32`, "10.0.0.2/32", "169.254.169.254/32"];
const step0: Record<string, unknown> = { ok: false };
async function setupNamespace(): Promise<boolean> {
  const lo = sh("ip", ["link", "set", "lo", "up"]);
  step0.loUp = lo.status === 0;
  step0.aliases = ALIASES.map((a) => ({ a, ok: sh("ip", ["addr", "add", a, "dev", "lo"]).status === 0 }));
  // Name resolution inside the namespace: files only, no resolver. A direct route to a DNS name then fails closed, and
  // arm D's hosts entry is authoritative (a host nsswitch can otherwise reach systemd-resolved over a unix socket).
  const etc = join(spec.scratch, "etc");
  mkdirSync(etc, { recursive: true });
  writeFileSync(
    join(etc, "hosts"),
    "127.0.0.1 localhost\n::1 localhost\n10.0.0.2 api.anthropic.com\n169.254.169.254 metadata.test\n",
  );
  writeFileSync(join(etc, "nsswitch.conf"), "passwd: files\ngroup: files\nhosts: files\n");
  writeFileSync(join(etc, "resolv.conf"), "nameserver 127.0.0.9\n");
  step0.mounts = ["hosts", "nsswitch.conf", "resolv.conf"].map((f) => ({
    f,
    ok: sh("mount", ["--bind", join(etc, f), join("/etc", f)]).status === 0,
  }));
  // The nested user namespace the SDK's bwrap needs, with --proc /proc as the production builder emits it.
  const nested = sh("bwrap", [
    "--unshare-user", "--unshare-pid", "--unshare-net", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--", "true",
  ]);
  step0.nestedBwrap = nested.status === 0;
  step0.nestedBwrapOut = nested.out;
  const viaShim = spawnSync(
    join(spec.appRoot, "infra", "bwrap-shim", "bwrap"),
    ["--unshare-user", "--unshare-pid", "--unshare-net", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--", "true"],
    {
      encoding: "utf8",
      timeout: 20_000,
      env: {
        ...process.env,
        SOLEUR_BWRAP_REAL: "/usr/bin/bwrap",
        SOLEUR_BWRAP_SECCOMP_BPF: join(spec.appRoot, "infra", "bwrap-userns-clone3-deny.bpf"),
      },
    },
  );
  step0.shimBwrap = viaShim.status === 0;
  // The child must import the production modules it measures (CTO D6).
  try {
    await import("@/server/permission-callback");
    await import("@/server/egress-forwarder");
    step0.imports = true;
  } catch (e) {
    step0.imports = false;
    step0.importError = String(e).slice(0, 300);
  }
  const allAliases = (step0.aliases as { ok: boolean }[]).every((a) => a.ok);
  const allMounts = (step0.mounts as { ok: boolean }[]).every((m) => m.ok);
  step0.ok = step0.loUp === true && allAliases && allMounts && step0.nestedBwrap === true && step0.shimBwrap === true && step0.imports === true;
  return step0.ok as boolean;
}

// ---- observation points --------------------------------------------------------------------------------------------
const decoyHits: DecoyHit[] = [];
const gatewayRecords: GatewayRecord[] = [];

function listen(server: net.Server, port: number, host: string): Promise<number> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => resolve((server.address() as net.AddressInfo).port));
  });
}

async function startDecoy(addr: string, port: number): Promise<number> {
  const server = net.createServer((sock) => {
    decoyHits.push({ addr, port: (server.address() as net.AddressInfo).port });
    sock.on("error", () => undefined);
    // Answer like an HTTP origin so a client does not hang; the hit is already recorded.
    sock.end("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nDECOY\n");
  });
  return listen(server, port, addr);
}

async function startRecordingGateway(): Promise<number> {
  const server = net.createServer((sock) => {
    let buf = "";
    sock.on("error", () => undefined);
    sock.on("data", (d) => {
      buf += d.toString("latin1");
      const end = buf.indexOf("\r\n\r\n");
      if (end === -1) {
        if (buf.length > 16_384) sock.destroy();
        return;
      }
      const head = buf.slice(0, end).split("\r\n");
      const auth = head.find((l) => /^proxy-authorization:/i.test(l)) ?? "";
      gatewayRecords.push({ line: head[0] ?? "", auth: auth.replace(/^proxy-authorization:\s*/i, "") });
      sock.end("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    });
  });
  return listen(server, 0, "127.0.0.1");
}

async function waitFor(pred: () => boolean | Promise<boolean>, ms: number, step = 250): Promise<boolean> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (await pred()) return true;
    await new Promise((r) => setTimeout(r, step));
  }
  return pred();
}

function canConnect(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const s = net.connect({ host, port, timeout: 1_000 }, () => {
      s.destroy();
      resolve(true);
    });
    s.once("error", () => resolve(false));
    s.once("timeout", () => {
      s.destroy();
      resolve(false);
    });
  });
}

// ---- one scripted turn through the real SDK --------------------------------------------------------------------------
const curl = (label: string, args: string) =>
  `o=$(curl -sS -m 6 -o /dev/null -w '%{http_code}' ${args} 2>&1); echo "R ${label} rc=$? out=$(printf '%s' "$o" | head -c 160 | tr '\\n' ' ')"`;
// The proxy variables the sandboxed command sees, credentials masked.
const ENV_PROBE = `echo "ENV $(env | grep -i '_proxy=' | sed -E 's#//[^@/]*@#//***@#' | sort | tr '\\n' ' ')"`;
// The sandbox's SOCKS bridge rides ftp_proxy (socks5h://...@localhost:<port>); ALL_PROXY points at the HTTP bridge.
const SOCKS = (label: string, target: string) =>
  `P="\${ftp_proxy:-$FTP_PROXY}"; case "$P" in socks5h://*) ${curl(label, `-x "$P" ${target}`)} ;; *) echo "R ${label} skipped=no-socks-proxy" ;; esac`;

interface ArmCtx {
  name: string;
  entitled: boolean;
  command: string;
  stubHost?: string;
  baseUrlHost?: string;
  subagentPrompt?: string;
  /** Further Bash commands, one per later tool turn of the same CLI session (arm F2). */
  followUps?: string[];
  /** Runs once the forwarder is up and before the turn (arm E kills it here). */
  beforeTurn?: (c: { conversationId: string; port: number; pid: number }) => Promise<Record<string, unknown>>;
  /** Runs concurrently with the turn (arm F tears down mid-command). */
  duringTurn?: (c: { conversationId: string; port: number; own: string }) => Promise<Record<string, unknown>>;
}

const WORKSPACE_ID = "00000000-0000-0000-0000-00000000c0de";
const RESULTS_FLOOR: string[] = [];

async function runArm(arm: ArmCtx, shimDir: string, gwPort: number, decoyPorts: Record<string, number>) {
  const t0 = Date.now();
  const { startAnthropicStub } = await import("./anthropic-stub");
  const { buildAgentEnv } = await import("@/server/agent-env");
  const { buildAgentSandboxConfig } = await import("@/server/agent-runner-sandbox-config");
  const fwd = await import("@/server/egress-forwarder");
  const { query } = await import("@anthropic-ai/claude-agent-sdk");

  const own = join(spec.scratch, `ws-${arm.name}`);
  mkdirSync(own, { recursive: true });
  const home = realpathSync(mkdtempSync(join(spec.scratch, `h-${arm.name}-`)));
  const conversationId = `conv-${arm.name}`;
  const gwBefore = gatewayRecords.length;
  const decoyBefore = decoyHits.length;
  const tap: TapCall[] = [];
  const extra: Record<string, unknown> = {};
  let forwarder: { port: number; token: string; pid: number } | undefined;
  const stub = await startAnthropicStub(arm.command, {
    host: arm.stubHost,
    ...(arm.subagentPrompt !== undefined ? { subagentPrompt: arm.subagentPrompt } : {}),
    ...(arm.followUps ? { followUps: arm.followUps } : {}),
  });
  let toolResult: string | null = null;
  let thrown = "";
  try {
    if (arm.entitled) {
      forwarder = await fwd.spawnEgressForwarder(conversationId, WORKSPACE_ID);
      extra.forwarderReady = await waitFor(() => canConnect("127.0.0.1", forwarder!.port), 30_000, 1_000);
    }
    if (arm.beforeTurn && forwarder) Object.assign(extra, await arm.beforeTurn({ conversationId, port: forwarder.port, pid: forwarder.pid }));
    const baseEnv = buildAgentEnv(
      { value: "decoy-api-key-sentinel", scheme: "api_key" },
      {},
      forwarder ? { egressProxy: { workspaceId: WORKSPACE_ID, token: forwarder.token, port: forwarder.port } } : {},
    );
    const env: Record<string, string | undefined> = {
      ...baseEnv,
      HOME: home,
      TMPDIR: spec.scratch,
      PATH: `${shimDir}:${process.env.PATH ?? "/usr/bin:/bin"}`,
      SOLEUR_BWRAP_REAL: "/usr/bin/bwrap",
      SOLEUR_BWRAP_SECCOMP_BPF: join(spec.appRoot, "infra", "bwrap-userns-clone3-deny.bpf"),
      ANTHROPIC_BASE_URL: `http://${arm.baseUrlHost ?? arm.stubHost ?? "127.0.0.1"}:${stub.port}`,
    };
    const sandbox = buildAgentSandboxConfig(own, { allowWebEgress: arm.entitled });

    let canUseTool: (name: string, input: Record<string, unknown>, o: { agentID?: string; signal: AbortSignal }) => Promise<any>;
    if (spec.tap === "production") {
      const { createCanUseTool } = await import("@/server/permission-callback");
      const prod = createCanUseTool({
        userId: "00000000-0000-0000-0000-0000000000a1",
        conversationId,
        leaderId: undefined,
        workspacePath: own,
        platformToolNames: [],
        pluginMcpServerNames: [],
        repoOwner: "",
        repoName: "",
        session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null } as never,
        controllerSignal: new AbortController().signal,
        deps: {
          abortableReviewGate: async () => "Approve",
          sendToClient: () => true,
          notifyOfflineUser: async () => undefined,
          updateConversationStatus: async () => undefined,
        } as never,
        ...(forwarder
          ? {
              sandboxNetworkEgress: { isLive: () => fwd.isEgressForwarderLive(conversationId, forwarder!.token) },
              webEgressGranted: true,
            }
          : {}),
      } as never) as unknown as typeof canUseTool;
      canUseTool = async (name, input, o) => {
        const r = await prod(name, input, o);
        tap.push({ tool: name, input, behavior: r.behavior, message: r.message, agentID: o?.agentID });
        // The production callback never sees Bash approval here (no human); the scripted command is the test's own.
        if (name === "Bash" && r.behavior !== "allow") return { behavior: "allow", updatedInput: input };
        return r;
      };
    } else {
      canUseTool = async (name, input, o) => {
        tap.push({ tool: name, input, behavior: "allow", agentID: o?.agentID });
        return { behavior: "allow", updatedInput: input };
      };
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 200_000);
    const during = arm.duringTurn ? arm.duringTurn({ conversationId, port: forwarder?.port ?? 0, own }) : Promise.resolve({});
    try {
      const q = query({
        prompt: "run the scripted command",
        options: {
          abortController: controller,
          model: "claude-haiku-5-5",
          maxTurns: 4,
          permissionMode: "default",
          cwd: own,
          settingSources: [],
          sandbox: sandbox as never,
          env,
          canUseTool: canUseTool as never,
        },
      });
      for await (const msg of q as AsyncIterable<any>) {
        if (msg.type !== "user") continue;
        const content = msg.message?.content;
        if (!Array.isArray(content)) continue;
        for (const b of content) {
          if (b?.type !== "tool_result") continue;
          const text =
            typeof b.content === "string" ? b.content : Array.isArray(b.content) ? b.content.map((c: any) => c?.text ?? "").join("") : "";
          // Keep every result that carries our markers (arm F2 runs two commands; the subagent's result is nested).
          if (/^(R|ENV) /m.test(text)) toolResult = toolResult && toolResult !== text ? `${toolResult}\n${text}` : text;
          else if (toolResult === null) toolResult = text;
        }
      }
    } catch (e) {
      if (!controller.signal.aborted) thrown = String(e).slice(0, 400);
    } finally {
      clearTimeout(timer);
      controller.abort();
    }
    Object.assign(extra, await during);
  } catch (e) {
    thrown = thrown || String(e).slice(0, 400);
  } finally {
    await stub.close();
    if (forwarder) fwd.teardownEgressForwarder(conversationId);
  }
  // The credential the forwarder must have injected for this session.
  const expectedAuth = forwarder ? `Basic ${Buffer.from(`${WORKSPACE_ID}:${forwarder.token}`).toString("base64")}` : null;
  const gw = gatewayRecords.slice(gwBefore).map((g) => ({ line: g.line, authOk: expectedAuth !== null && g.auth === expectedAuth, authPresent: g.auth !== "" }));
  RESULTS_FLOOR.push(arm.name);
  emit("NETNS_ARM", {
    arm: arm.name,
    tap: spec.tap,
    entitled: arm.entitled,
    wallMs: Date.now() - t0,
    thrown,
    toolResult: toolResult === null ? null : String(toolResult).slice(0, 4000),
    calls: tap.map((c) => ({ tool: c.tool, input: c.tool === "SandboxNetworkAccess" ? c.input : undefined, keys: c.input && typeof c.input === "object" ? Object.keys(c.input as object).sort() : [], behavior: c.behavior, message: c.message, agentID: c.agentID ?? null })),
    gateway: gw,
    decoys: decoyHits.slice(decoyBefore),
    stubRequests: stub.requests(),
    decoyPorts,
    ...extra,
  });
}

// ---- the arms ----------------------------------------------------------------------------------------------------------
function arms(decoyPorts: Record<string, number>): Record<string, ArmCtx> {
  const lp = decoyPorts.loopback2;
  return {
    control: {
      // Permanent positive control (CTO T9/T16): allow everything with NO egress env. Every decoy the silence checks rely
      // on must be hit here, or a silent arm cannot tell a closed path from a blind sensor.
      name: "control",
      entitled: false,
      command: [
        ENV_PROBE,
        curl("c-https-ip", `-k https://${DECOY_IP}/`),
        curl("c-http-ip", `http://${DECOY_IP}/`),
        SOCKS("c-socks-ip22", `http://${DECOY_IP}:22/`),
        curl("c-loop2", `-k https://127.0.0.2:${lp}/`),
        curl("c-http-loop2", `http://127.0.0.2:${lp}/`),
        curl("c-linklocal", "--noproxy '' http://169.254.169.254/"),
      ].join("; "),
    },
    A: {
      name: "A",
      entitled: false,
      command: [
        ENV_PROBE,
        curl("a-https-name", "https://example.test/"),
        curl("a-https-ip", `-k https://${DECOY_IP}/`),
        curl("a-loop2", `-k https://127.0.0.2:${lp}/`),
      ].join("; "),
    },
    B: {
      name: "B",
      entitled: true,
      command: [
        ENV_PROBE,
        curl("b-https-name", "https://example.test/"),
        curl("b-https-name-again", "https://example.test/"),
        curl("b-https-upper-dot", "https://EXAMPLE.TEST./"),
        curl("b-https-ip", `-k https://${DECOY_IP}/`),
        curl("b-http-name", "http://example.test/"),
        SOCKS("b-socks-name22", "http://example.test:22/"),
        SOCKS("b-socks-ip22", `http://${DECOY_IP}:22/`),
        curl("b-linklocal", "--noproxy '' -k https://169.254.169.254/"),
        curl("b-linklocal-name", "-k https://metadata.test/"),
      ].join("; "),
    },
    C: {
      name: "C",
      entitled: true,
      command: [
        ENV_PROBE,
        curl("c-supabase", "https://x.supabase.co/"),
        curl("c-localhost", `--noproxy '' -k https://localhost:${lp}/`),
        curl("c-loop2", `--noproxy '' -k https://127.0.0.2:${lp}/`),
        curl("c-decimal", `--noproxy '' -k https://2130706433:${lp}/`),
        curl("c-v6loop", `--noproxy '' -k https://[::1]:${lp}/`),
        curl("c-v6loop-long", `--noproxy '' -k https://[0:0::1]:${lp}/`),
        curl("c-localhost-dot", `--noproxy '' -k https://LOCALHOST.:${lp}/`),
        curl("c-hex", `--noproxy '' -k https://0x7f000001:${lp}/`),
        // AC23: a listener inside the sandbox on its own loopback, reached with curl's default NO_PROXY handling.
        `(python3 -c 'import http.server,socketserver; socketserver.TCPServer(("127.0.0.1",18765),http.server.SimpleHTTPRequestHandler).serve_forever()' >/dev/null 2>&1 &) ; sleep 1; ${curl("c-in-sandbox-loopback", "http://localhost:18765/")}`,
      ].join("; "),
    },
    D: {
      // Measurement 4 analog (CTO T8): the CLI's own Messages API traffic to a production NO_PROXY host. The hosts file maps
      // api.anthropic.com to 10.0.0.2, where the stub listens; it must reach the stub directly, never the gateway.
      name: "D",
      entitled: true,
      stubHost: "10.0.0.2",
      baseUrlHost: "api.anthropic.com",
      command: "echo D_TURN_RAN",
    },
    E: {
      name: "E",
      entitled: true,
      command: [ENV_PROBE, curl("e-1", `-k https://${DECOY_IP}/`), curl("e-2", `-k https://${DECOY_IP}/`)].join("; "),
      beforeTurn: async ({ conversationId, pid }) => {
        const fwd = await import("@/server/egress-forwarder");
        process.kill(pid, "SIGKILL");
        // The exit handler drops the registry entry; awaiting that is awaiting the exit event (otherwise the main case
        // silently becomes the sub-case).
        const exited = await waitFor(() => !fwd.hasEgressForwarder(conversationId), 10_000, 100);
        return { forwarderDeadBeforeTurn: exited && !fwd.hasEgressForwarder(conversationId) };
      },
    },
    F: {
      name: "F",
      entitled: true,
      command: [
        ENV_PROBE,
        curl("f-1", `-k https://${DECOY_IP}/`),
        "touch .f-step1",
        `i=0; while [ ! -f .f-barrier ] && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done; echo "R f-barrier seen=$([ -f .f-barrier ] && echo yes || echo no)"`,
        curl("f-2", `-k https://${DECOY_IP}/`),
        curl("f-3", `-k https://${DECOY_IP}/`),
      ].join("; "),
      duringTurn: async ({ conversationId, port, own }) => {
        const fwd = await import("@/server/egress-forwarder");
        const step1 = await waitFor(() => existsSync(join(own, ".f-step1")), 120_000, 200);
        if (!step1) return { fTornDown: false, fStep1: false };
        fwd.teardownEgressForwarder(conversationId);
        const closed = await waitFor(async () => !(await canConnect("127.0.0.1", port)), 10_000, 100);
        writeFileSync(join(own, ".f-barrier"), "go\n");
        return { fStep1: true, fTornDown: !fwd.hasEgressForwarder(conversationId), fPortClosed: closed };
      },
    },
    F2: {
      // The same re-ask question across two SEPARATE commands of one CLI session (the cache's scope).
      name: "F2",
      entitled: true,
      command: [curl("f2-1", `-k https://${DECOY_IP}/`), "touch .f2-step1"].join("; "),
      followUps: [
        [
          `i=0; while [ ! -f .f2-barrier ] && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done; echo "R f2-barrier seen=$([ -f .f2-barrier ] && echo yes || echo no)"`,
          curl("f2-2", `-k https://${DECOY_IP}/`),
          curl("f2-new-host", "https://example.test/"),
        ].join("; "),
      ],
      duringTurn: async ({ conversationId, port, own }) => {
        const fwd = await import("@/server/egress-forwarder");
        const step1 = await waitFor(() => existsSync(join(own, ".f2-step1")), 120_000, 200);
        if (!step1) return { fTornDown: false, fStep1: false };
        fwd.teardownEgressForwarder(conversationId);
        const closed = await waitFor(async () => !(await canConnect("127.0.0.1", port)), 10_000, 100);
        writeFileSync(join(own, ".f2-barrier"), "go\n");
        return { fStep1: true, fTornDown: !fwd.hasEgressForwarder(conversationId), fPortClosed: closed };
      },
    },
    G: {
      name: "G",
      entitled: true,
      subagentPrompt: "run the scripted command",
      command: [ENV_PROBE, curl("g-https-name", "https://example.test/")].join("; "),
    },
  };
}

async function main() {
  const ok = await setupNamespace();
  emit("NETNS_STEP0", step0);
  if (!ok) process.exit(0);
  // Decoys a direct (off-forwarder) route would reach.
  const decoyPorts: Record<string, number> = {};
  for (const p of [443, 80, 22]) decoyPorts[`ip${p}`] = await startDecoy(DECOY_IP, p);
  decoyPorts.loopback2 = await startDecoy("127.0.0.2", 0);
  for (const p of [443, 80]) decoyPorts[`linklocal${p}`] = await startDecoy("169.254.169.254", p);
  const gwPort = await startRecordingGateway();
  process.env.EGRESS_GW_HOST = "127.0.0.1";
  process.env.EGRESS_GW_PORT = String(gwPort);
  process.env.EGRESS_TOKEN_DIR = join(spec.scratch, "tokens");
  process.env.EGRESS_FORWARDER_PATH = join(spec.appRoot, "infra", "egress-forwarder.mjs");
  const shimDir = join(spec.scratch, "shim");
  mkdirSync(shimDir, { recursive: true });
  writeFileSync(join(shimDir, "bwrap"), `#!/usr/bin/env bash\nexec ${JSON.stringify(join(spec.appRoot, "infra", "bwrap-shim", "bwrap"))} "$@"\n`, { mode: 0o755 });
  const all = arms(decoyPorts);
  for (const name of spec.arms) {
    const arm = all[name];
    if (!arm) throw new Error(`unknown arm ${name}`);
    await runArm(arm, shimDir, gwPort, decoyPorts);
  }
  process.exit(0);
}

main().catch((e) => {
  emit("NETNS_ARM", { arm: "__harness__", thrown: String(e?.stack ?? e).slice(0, 800) });
  process.exit(1);
});
