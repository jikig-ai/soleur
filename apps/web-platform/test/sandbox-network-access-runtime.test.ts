// #12585 — the SandboxNetworkAccess request, observed through the REAL Agent SDK, the production sandbox config and env
// builders, the production egress forwarder and the production canUseTool, inside a private network namespace.
//
// pyramid-justified: the property is the SDK's own routing after a canUseTool answer (which socket a sandboxed curl
// reaches), which no unit test can observe; the pure decision and the callback arm have their own unit suites.
//
// Topology (CTO T7/D6): vitest cannot sit inside a namespace, so each phase spawns test/helpers/netns-egress-harness.mts
// under `unshare -rnm`. The child brings up a private loopback with decoy listeners where a direct (off-forwarder) route
// would land, a recording gateway in the squid gateway's place (records the request line and the Proxy-Authorization the
// forwarder injected, answers 403), and runs one scripted sandboxed command per arm through query(). It reports JSON.
//
// Two phases:
//   MEASUREMENT (allow-all tap, plan Phase 1a): what the SDK does AFTER an allow, independent of the arm. This is the
//     go/no-go that decided row 6' (deny-all): allowed traffic does transit the forwarder with the session credential,
//     but the SDK caches a per-host allow for the session (arms F, F2). The F/F2 assertions pin that caching: when an
//     SDK bump stops caching, they go red and the follow-up allow arm can be reconsidered (ADR-278 addendum 2026-11-18).
//   PRODUCTION (production createCanUseTool, Phase 1b): every request a sandboxed command makes is answered by the arm.
//
// Any decoy hit, or a gateway connection without the session credential, fails the suite on its own.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import {
  CACHES_MODEL,
  CONTROL_DECOYS,
  DEAD_FORWARDER,
  decoyKey,
  MEASURED_BASELINE,
  MOVE_RULE,
  TEARDOWN_GATEWAY,
  result,
} from "@/scripts/lib/sandbox-network-cache-verdict";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const HARNESS = join(APP_ROOT, "test", "helpers", "netns-egress-harness.mts");
const TSX = join(APP_ROOT, "node_modules", ".bin", "tsx");

// The SDK version the measurements below were taken on (CTO T16). Single-sourced with the re-measure classifier
// (#12906 PR-1b). It moves only per the classifier's MOVE_RULE.
// The F/F2 host assertions read CACHES_MODEL (the classifier's invariant CACHES model), guarded by the pinned reading.
const MEASURED_ON_SDK = MEASURED_BASELINE.version;
const SEMVER = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/;
const REMEASURE_CMD = "bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh";

const has = (cmd: string) => spawnSync("sh", ["-c", `command -v ${cmd}`], { stdio: "ignore" }).status === 0;
const UNSHARE_OK =
  process.platform === "linux" &&
  has("unshare") &&
  has("ip") &&
  has("curl") &&
  has("socat") &&
  has("bwrap") &&
  spawnSync("unshare", ["-rnm", "true"], { stdio: "ignore", timeout: 15_000 }).status === 0;
if (process.platform === "linux" && !UNSHARE_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error(
    "C4_BWRAP_REQUIRED is set but the network-namespace harness cannot run here (needs unshare -rnm, ip, curl, socat, bwrap). " +
      "apt-get install bubblewrap socat iproute2 curl && sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (Ubuntu)",
  );
}

interface Call {
  tool: string;
  input?: { host?: unknown };
  keys: string[];
  behavior: string;
  message?: string;
  agentID: string | null;
}
interface ArmRecord {
  arm: string;
  initClaudeCodeVersion?: string | null;
  tap: string;
  entitled: boolean;
  thrown: string;
  toolResult: string | null;
  calls: Call[];
  gateway: { line: string; authOk: boolean; authPresent: boolean }[];
  decoys: { addr: string; port: number }[];
  forwarderReady?: boolean;
  forwarderDeadBeforeTurn?: boolean;
  fStep1?: boolean;
  fTornDown?: boolean;
  fPortClosed?: boolean;
}

function runHarness(tap: "allow-all" | "production", arms: string[]): { step0: Record<string, unknown>; arms: Map<string, ArmRecord> } {
  const scratch = mkdtempSync(join(tmpdir(), "snx-"));
  try {
    const spec = join(scratch, "spec.json");
    writeFileSync(spec, JSON.stringify({ appRoot: APP_ROOT, scratch, tap, arms }));
    const r = spawnSync("unshare", ["-rnm", TSX, "--tsconfig", join(APP_ROOT, "tsconfig.json"), HARNESS, spec], {
      cwd: APP_ROOT,
      encoding: "utf8",
      timeout: 420_000,
      maxBuffer: 64 * 1024 * 1024,
      env: { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: scratch, LANG: "C.UTF-8", NODE_ENV: "test" },
    });
    const lines = (r.stdout ?? "").split("\n");
    const step0Line = lines.find((l) => l.startsWith("NETNS_STEP0 "));
    if (!step0Line) throw new Error(`harness printed no step-0 record (status ${r.status}):\n${(r.stderr ?? "").slice(-2000)}`);
    const records = lines.filter((l) => l.startsWith("NETNS_ARM ")).map((l) => JSON.parse(l.slice(10)) as ArmRecord);
    const crash = records.find((a) => a.arm === "__harness__");
    if (crash) throw new Error(`harness crashed: ${crash.thrown}`);
    return { step0: JSON.parse(step0Line.slice(12)), arms: new Map(records.map((a) => [a.arm, a])) };
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

const net = (a: ArmRecord) => a.calls.filter((c) => c.tool === "SandboxNetworkAccess");
const hosts = (a: ArmRecord) => net(a).map((c) => String(c.input?.host));
// result() (the `R <label> <value>` line of an arm's tool result) is imported from the classifier: one copy.

/** The invariants every arm holds whatever it returned: no decoy hit, every gateway connection carries the credential. */
function assertNoLeak(a: ArmRecord) {
  expect(a.thrown, `${a.arm} threw`).toBe("");
  expect(a.decoys, `${a.arm}: a connection left without transiting the forwarder`).toEqual([]);
  for (const g of a.gateway) expect(g.authOk, `${a.arm}: gateway saw ${g.line} without the session credential`).toBe(true);
}
function assertAsked(a: ArmRecord) {
  expect(net(a).length, `${a.arm}: no SandboxNetworkAccess call recorded; tools seen: ${a.calls.map((c) => c.tool).join(",")}`).toBeGreaterThan(0);
  // The SDK's input shape, pinned at runtime only (the SDK types it as Record<string, unknown>): exactly { host }.
  for (const c of net(a)) expect(c.keys).toEqual(["host"]);
}

// A request routed at a dead forwarder fails in one of two measured shapes, and both mean no tunnel was opened:
// rc=7 (curl could not connect: the path to the forwarder's port was refused) or rc=56 with a 502 on CONNECT (the SDK's
// sandbox proxy accepted the tunnel request and its dial to the dead forwarder failed). Local runs show the first and CI
// runners the second (PR #12897, run 44322968227). The no-leak and empty-gateway assertions in each arm prove that
// nothing got out; this only pins that the request itself failed, and in no other way.
// DEAD_FORWARDER is imported from the classifier, so the suite and the re-measure share one copy.
const ARMS_RUN = new Set<string>();

describe("installed SDK matches the measured one (CTO T16)", () => {
  it(`@anthropic-ai/claude-agent-sdk is ${MEASURED_ON_SDK}`, () => {
    const pkg = JSON.parse(readFileSync(join(APP_ROOT, "node_modules", "@anthropic-ai", "claude-agent-sdk", "package.json"), "utf8"));
    expect(
      pkg.version,
      `The SDK changed: installed ${pkg.version}, measured ${MEASURED_ON_SDK}. Run \`${REMEASURE_CMD} ${pkg.version}\` ` +
        "(it installs both into scratch dirs and measures them side by side) and record the result in ADR-278. " +
        `MEASURED_BASELINE is in scripts/lib/sandbox-network-cache-verdict.ts. ${MOVE_RULE}`,
    ).toBe(MEASURED_ON_SDK);
  });
  it("the classifier's CACHES model is the F/F2 sequence measured on 0.3.321 (one literal copy, PR #12897)", () => {
    expect(CACHES_MODEL).toEqual({ fHosts: ["198.51.100.1"], f2Hosts: ["198.51.100.1", "example.test"] });
  });
});

const READING_MSG = `a pin whose reading is not CACHES needs #12906's allow-arm PR, which replaces these assertions. ${MOVE_RULE}`;

describe.skipIf(!UNSHARE_OK)("MEASUREMENT: the SDK's routing after an allow (allow-all tap, plan Phase 1a)", () => {
  let run: ReturnType<typeof runHarness>;
  beforeAll(() => {
    run = runHarness("allow-all", ["control", "B", "D", "E", "F", "F2"]);
  }, 420_000);
  const arm = (n: string) => {
    const a = run.arms.get(n);
    if (!a) throw new Error(`arm ${n} produced no record`);
    return a;
  };

  it("step 0: loopback aliases, hermetic name resolution, nested bwrap (with --proc) and the production imports", () => {
    expect(run.step0).toMatchObject({ ok: true, loUp: true, nestedBwrap: true, shimBwrap: true, imports: true });
    // #12906: the harness reports what it measured. Shape first, so two failed probes cannot pass as null === null.
    expect(String(run.step0.sdkVersion)).toMatch(SEMVER);
    expect(String(run.step0.cliVersion)).toMatch(SEMVER);
    expect(run.step0.sdkVersion).toBe(MEASURED_ON_SDK);
    for (const a of run.arms.values()) {
      expect(String(a.initClaudeCodeVersion), `${a.arm}: no system/init claude_code_version`).toMatch(SEMVER);
      expect(a.initClaudeCodeVersion, `${a.arm}: the CLI the SDK spawned is not the one step 0 probed`).toBe(run.step0.cliVersion);
    }
    ARMS_RUN.add("m-step0");
  });

  it("control: with no egress env an allowed request goes direct and hits EVERY decoy the silence checks rely on", () => {
    const a = arm("control");
    expect(a.thrown).toBe("");
    const hit = new Set(a.decoys.map((d) => decoyKey(d)));
    for (const d of CONTROL_DECOYS) {
      expect(hit, `decoy ${d} was not reached: the sensor is blind`).toContain(d);
    }
    expect(a.gateway).toEqual([]);
    ARMS_RUN.add("m-control");
  });

  it("B: every allowed transport reaches the gateway with the session credential (ADR-278 measurement 3; AC6, AC8)", () => {
    const a = arm("B");
    assertNoLeak(a);
    assertAsked(a);
    expect(a.forwarderReady).toBe(true);
    const lines = a.gateway.map((g) => g.line);
    for (const l of [
      "CONNECT example.test:443 HTTP/1.1",
      "CONNECT 198.51.100.1:443 HTTP/1.1",
      "GET http://example.test/ HTTP/1.1", // plain HTTP arrives as an absolute-URI request
      "CONNECT example.test:22 HTTP/1.1", // SOCKS is bridged onto the same HTTP proxy chain
      "CONNECT 198.51.100.1:22 HTTP/1.1",
      "CONNECT 169.254.169.254:443 HTTP/1.1", // the gateway, not the name, decides on link-local
      "CONNECT metadata.test:443 HTTP/1.1",
    ]) {
      expect(lines).toContain(l);
    }
    expect(a.gateway.every((g) => g.authPresent && g.authOk)).toBe(true);
    // AC27: the host arrives bare, without a port.
    expect(hosts(a)).toEqual(expect.arrayContaining(["example.test", "198.51.100.1"]));
    for (const h of hosts(a)) expect(h).not.toMatch(/:\d+$/);
    ARMS_RUN.add("m-B");
  });

  it("D: the CLI's own API traffic to a NO_PROXY host goes direct, never to the gateway (ADR-278 measurement 4)", () => {
    const a = arm("D");
    assertNoLeak(a);
    expect(a.toolResult).toContain("D_TURN_RAN");
    expect(a.gateway).toEqual([]);
    ARMS_RUN.add("m-D");
  });

  it("E: a forwarder killed before the turn => the allowed request fails, with no direct retry", () => {
    const a = arm("E");
    assertNoLeak(a);
    assertAsked(a);
    expect(a.forwarderDeadBeforeTurn).toBe(true);
    expect(a.gateway).toEqual([]);
    expect(result(a, "e-2")).toMatch(DEAD_FORWARDER);
    ARMS_RUN.add("m-E");
  });

  it("F: the SDK caches a per-host allow within a command: after teardown the host is NOT re-asked (fails closed at the dead forwarder)", () => {
    const a = arm("F");
    assertNoLeak(a);
    expect(a).toMatchObject({ fStep1: true, fTornDown: true, fPortClosed: true });
    expect(result(a, "f-barrier")).toBe("seen=yes");
    expect(MEASURED_BASELINE.reading, READING_MSG).toBe("CACHES");
    expect(hosts(a)).toEqual([...CACHES_MODEL.fHosts]); // asked once, for three requests
    expect(a.gateway.map((g) => g.line)).toEqual([...TEARDOWN_GATEWAY]); // only the pre-teardown one
    expect(result(a, "f-3")).toMatch(DEAD_FORWARDER);
    ARMS_RUN.add("m-F");
  });

  it("F2: the cache spans commands of one session (a NEW host is asked, the allowed one is not): the reason row 6' ships", () => {
    const a = arm("F2");
    assertNoLeak(a);
    expect(a).toMatchObject({ fStep1: true, fTornDown: true, fPortClosed: true });
    expect(MEASURED_BASELINE.reading, READING_MSG).toBe("CACHES");
    expect(hosts(a)).toEqual([...CACHES_MODEL.f2Hosts]);
    expect(a.gateway.map((g) => g.line)).toEqual([...TEARDOWN_GATEWAY]); // only the pre-teardown one
    expect(net(a).length).toBe(2);
    expect(result(a, "f2-2")).toMatch(DEAD_FORWARDER);
    ARMS_RUN.add("m-F2");
  });
});

describe.skipIf(!UNSHARE_OK)("PRODUCTION: the production canUseTool answers every sandboxed request", () => {
  let run: ReturnType<typeof runHarness>;
  beforeAll(() => {
    run = runHarness("production", ["A", "B", "C", "E", "G"]);
  }, 420_000);
  const arm = (n: string) => {
    const a = run.arms.get(n);
    if (!a) throw new Error(`arm ${n} produced no record`);
    return a;
  };
  const NOT_AVAILABLE = "Network access from sandboxed commands is not available in this session.";
  const HOST_DENIED = "Commands can't connect to this host from this session.";

  it("A unentitled: every host is denied with the not-available copy; nothing reaches the gateway or a decoy (AC1)", () => {
    const a = arm("A");
    assertNoLeak(a);
    assertAsked(a);
    expect(hosts(a)).toEqual(["example.test", "198.51.100.1", "127.0.0.2"]);
    for (const c of net(a)) expect(c).toMatchObject({ behavior: "deny", message: NOT_AVAILABLE });
    expect(a.gateway).toEqual([]);
    ARMS_RUN.add("p-A");
  });

  it("B entitled: every host is denied gateway-unverified (row 6', AC22); a deny is re-asked per request (no cached deny)", () => {
    const a = arm("B");
    assertNoLeak(a);
    assertAsked(a);
    for (const c of net(a)) {
      expect(c.behavior).toBe("deny");
      expect(c.message).toMatch(/`WebFetch` tool/);
    }
    // example.test is asked for :443 twice, :80 and :22: a deny is never cached.
    expect(hosts(a).filter((h) => h === "example.test").length).toBe(4);
    expect(a.gateway).toEqual([]);
    ARMS_RUN.add("p-B");
  });

  it("C entitled, proxy-bypass shapes: denied with the host copy; in-sandbox loopback still works and is never asked (AC3, AC23)", () => {
    const a = arm("C");
    assertNoLeak(a);
    assertAsked(a);
    // curl canonicalizes numeric and bracketed spellings before the SDK sees them (2130706433 and 0x7f000001 arrive as
    // 127.0.0.1, [0:0::1] as ::1): the SDK passes the bare host it was asked to dial.
    expect(new Set(hosts(a))).toEqual(new Set(["x.supabase.co", "localhost", "127.0.0.2", "127.0.0.1", "::1", "LOCALHOST."]));
    for (const c of net(a)) expect(c).toMatchObject({ behavior: "deny", message: HOST_DENIED });
    expect(a.gateway).toEqual([]);
    expect(result(a, "c-in-sandbox-loopback")).toBe("rc=0 out=200");
    ARMS_RUN.add("p-C");
  });

  it("E entitled with a dead forwarder: denied with the degraded copy (egress-not-running, granted)", () => {
    const a = arm("E");
    assertNoLeak(a);
    assertAsked(a);
    expect(a.forwarderDeadBeforeTurn).toBe(true);
    for (const c of net(a)) expect(c.message).toMatch(/web access isn't working in this session/);
    ARMS_RUN.add("p-E");
  });

  it("G subagent: the subagent's sandboxed request reaches the same callback and is denied (CTO T11)", () => {
    const a = arm("G");
    assertNoLeak(a);
    assertAsked(a);
    // The subagent's Bash call carries its agentID; on 0.3.321 its SandboxNetworkAccess request does not (measured).
    expect(a.calls.some((c) => c.tool === "Bash" && c.agentID !== null)).toBe(true);
    for (const c of net(a)) expect(c.message).toMatch(/`WebFetch` tool/);
    expect(a.gateway).toEqual([]);
    ARMS_RUN.add("p-G");
  });
});

describe.skipIf(!UNSHARE_OK)("floor", () => {
  it("every arm ran to its last assertion (a skipped or filtered arm cannot pass vacuously)", () => {
    expect([...ARMS_RUN].sort()).toEqual(
      ["m-B", "m-D", "m-E", "m-F", "m-F2", "m-control", "m-step0", "p-A", "p-B", "p-C", "p-E", "p-G"].sort(),
    );
  });
});
