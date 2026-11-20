// #12906 PR-1b — the verdict classifier for the SDK per-host SandboxNetworkAccess allow-cache re-measure (Guard 1 of the
// plan's Guard Contract). Every fixture is synthesized by `harnessRun()`, which builds FRESH objects on every call, so a
// mutation of the baseline fixture can never leak into the candidate (cq-test-fixtures-synthesized-only).

import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterAll, afterEach, describe, expect, it, vi } from "vitest";
import {
  ARMS,
  CACHES_MODEL,
  CONTROL_DECOYS,
  DEAD_FORWARDER,
  MEASURED_BASELINE,
  NEXT,
  PRECONDITIONS,
  SENTINEL,
  TEARDOWN_GATEWAY,
  VERDICTS,
  classify,
  identityLeak,
  main,
  mdCell,
  parseHarnessOutput,
  readCache,
  remeasureLine,
  renderDrafts,
  result,
  safeHost,
  type ClassifyInput,
} from "@/scripts/lib/sandbox-network-cache-verdict";
import { loadSdk, resolveSdkEntry } from "./helpers/netns-egress-harness.mjs";

const DECOY = "198.51.100.1";
const CONNECT = `CONNECT ${DECOY}:443 HTTP/1.1`;
const DEAD = "rc=7 out=000";
const CAND_SDK = "0.3.326";
const CAND_CLI = "2.1.326";

type Rec = Record<string, any>;

// Real files for the two SDK entries: precondition sdk-entry realpaths step0.sdkEntry against the expected entry.
const ROOT = realpathSync(mkdtempSync(join(tmpdir(), "snv-root-")));
const entryFor = (side: string) => {
  const p = join(ROOT, side, "node_modules", "@anthropic-ai", "claude-agent-sdk", "sdk.mjs");
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, "export {};\n");
  return p;
};
const BASE_ENTRY = entryFor("baseline");
const CAND_ENTRY = entryFor("candidate");
afterAll(() => rmSync(ROOT, { recursive: true, force: true }));

/** One harness run's stdout, built from fresh objects. `mut` edits the parsed records before they are serialized. */
function harnessRun(o: {
  sdk?: string;
  cli?: string;
  entry?: string;
  fHosts?: string[];
  f2Hosts?: string[];
  mut?: (step0: Rec, arms: Map<string, Rec>) => void;
  noise?: boolean;
} = {}): string {
  const sdk = o.sdk ?? CAND_SDK;
  const cli = o.cli ?? CAND_CLI;
  const step0: Rec = {
    ok: true,
    loUp: true,
    nestedBwrap: true,
    shimBwrap: true,
    imports: true,
    sdkEntry: o.entry ?? CAND_ENTRY,
    sdkVersion: sdk,
    cliPath: join(ROOT, "candidate", "node_modules", "@anthropic-ai", "claude-agent-sdk-linux-x64", "claude"),
    cliVersion: cli,
  };
  const call = (host: string) => ({ tool: "SandboxNetworkAccess", input: { host }, keys: ["host"], behavior: "allow", agentID: null });
  const bash = { tool: "Bash", keys: ["command"], behavior: "allow", agentID: null };
  const base = (arm: string, extra: Rec = {}): Rec => ({
    arm,
    tap: "allow-all",
    entitled: arm !== "control",
    wallMs: 1000,
    thrown: "",
    toolResult: "",
    calls: [{ ...bash }],
    gateway: [],
    decoys: [],
    stubRequests: 3,
    initClaudeCodeVersion: cli,
    ...extra,
  });
  const fHosts = o.fHosts ?? [...CACHES_MODEL.fHosts];
  const f2Hosts = o.f2Hosts ?? [...CACHES_MODEL.f2Hosts];
  const arms = new Map<string, Rec>([
    [
      "control",
      base("control", {
        decoys: [
          { addr: DECOY, port: 443 },
          { addr: DECOY, port: 80 },
          { addr: DECOY, port: 22 },
          { addr: "127.0.0.2", port: 40001 },
          { addr: "169.254.169.254", port: 80 },
        ],
      }),
    ],
    [
      "B",
      base("B", {
        calls: [{ ...bash }, call("example.test"), call(DECOY)],
        gateway: [
          { line: "CONNECT example.test:443 HTTP/1.1", authOk: true, authPresent: true },
          { line: CONNECT, authOk: true, authPresent: true },
        ],
      }),
    ],
    ["D", base("D", { toolResult: "D_TURN_RAN" })],
    [
      "E",
      base("E", {
        calls: [{ ...bash }, call(DECOY)],
        forwarderDeadBeforeTurn: true,
        toolResult: `R e-1 ${DEAD}\nR e-2 ${DEAD}`,
      }),
    ],
    [
      "F",
      base("F", {
        calls: [{ ...bash }, ...fHosts.map(call)],
        gateway: [{ line: CONNECT, authOk: true, authPresent: true }],
        fStep1: true,
        fTornDown: true,
        fPortClosed: true,
        toolResult: `R f-1 rc=0 out=403\nR f-barrier seen=yes\nR f-2 ${DEAD}\nR f-3 ${DEAD}`,
      }),
    ],
    [
      "F2",
      base("F2", {
        calls: [{ ...bash }, ...f2Hosts.map(call)],
        gateway: [{ line: CONNECT, authOk: true, authPresent: true }],
        fStep1: true,
        fTornDown: true,
        fPortClosed: true,
        toolResult: `R f2-1 rc=0 out=403\nR f2-barrier seen=yes\nR f2-2 ${DEAD}\nR f2-new-host ${DEAD}`,
      }),
    ],
  ]);
  o.mut?.(step0, arms);
  const lines: string[] = [];
  if (o.noise) lines.push('{"level":30,"msg":"server logger noise"}', "random line");
  lines.push(`NETNS_STEP0 ${JSON.stringify(step0)}`);
  for (const a of arms.values()) {
    lines.push(`NETNS_ARM ${JSON.stringify(a)}`);
    if (o.noise) lines.push("noise between records");
  }
  return `\n${lines.join("\n")}\n`;
}

const baselineRun = (mut?: (s: Rec, a: Map<string, Rec>) => void) =>
  harnessRun({ sdk: MEASURED_BASELINE.version, cli: "2.1.321", entry: BASE_ENTRY, mut });

function input(over: Partial<{ baseline: string; candidate: string; candCli: string; candSdk: string }> = {}): ClassifyInput {
  return {
    baseline: { stdout: over.baseline ?? baselineRun(), expectedSdk: MEASURED_BASELINE.version, expectedCli: "2.1.321", expectedEntry: BASE_ENTRY },
    candidate: {
      stdout: over.candidate ?? harnessRun(),
      expectedSdk: over.candSdk ?? CAND_SDK,
      expectedCli: over.candCli ?? CAND_CLI,
      expectedEntry: CAND_ENTRY,
    },
  };
}
const cand = (o: Parameters<typeof harnessRun>[0]) => input({ candidate: harnessRun(o) });

describe("MEASURED_BASELINE, CACHES_MODEL and DEAD_FORWARDER", () => {
  it("pin the 0.3.321 reading the runtime suite asserts; the CACHES model lives apart from the pin", () => {
    expect(MEASURED_BASELINE.version).toBe("0.3.321");
    expect(MEASURED_BASELINE.reading).toBe("CACHES");
    expect(Object.keys(MEASURED_BASELINE).sort()).toEqual(["integrity", "reading", "version"]);
    expect(CACHES_MODEL).toEqual({ fHosts: [DECOY], f2Hosts: [DECOY, "example.test"] });
    expect(TEARDOWN_GATEWAY).toEqual([CONNECT]);
    expect(MEASURED_BASELINE.integrity.sdk).toMatch(/^sha512-[A-Za-z0-9+/]+=*$/);
    expect(MEASURED_BASELINE.integrity.linuxX64).toMatch(/^sha512-[A-Za-z0-9+/]+=*$/);
  });
  it("DEAD_FORWARDER matches both measured dead-forwarder shapes and nothing else", () => {
    expect(DEAD).toMatch(DEAD_FORWARDER);
    expect("rc=56 out=curl: (56) CONNECT tunnel failed, response 502 ").toMatch(DEAD_FORWARDER);
    expect("rc=0 out=403").not.toMatch(DEAD_FORWARDER);
    expect("<missing>").not.toMatch(DEAD_FORWARDER);
  });
  it("the precondition list is the documented set", () => {
    expect(PRECONDITIONS.map((p) => p.name)).toEqual(["versions", "sdk-entry", "arms-present", "control", "teardown", "post-teardown-ran", "asked"]);
    expect(ARMS).toEqual(["control", "B", "D", "E", "F", "F2"]);
    expect(CONTROL_DECOYS).toHaveLength(5);
  });
});

describe("verdicts", () => {
  it("CACHES: both runs read the measured sequences (exit 0)", () => {
    const v = classify(input());
    expect(v).toMatchObject({ verdict: "CACHES", exit: 0 });
    expect(remeasureLine(v)).toMatch(/^REMEASURE verdict=CACHES exit=0 reason=\S+ next=.+$/);
  });
  it("the canonical fixture passes every precondition in both runs", () => {
    const v = classify(input());
    for (const run of [v.baseline!, v.candidate!]) {
      expect(run.preconditions.every((p) => p.ok), JSON.stringify(run.preconditions)).toBe(true);
      expect(run.preconditions.map((p) => p.name)).toEqual(PRECONDITIONS.map((p) => p.name));
    }
  });
  it("RE-ASKS-AFTER-TEARDOWN: F re-asks the decoy, F2 re-asks it and asks example.test (exit 0)", () => {
    expect(classify(cand({ fHosts: [DECOY, DECOY], f2Hosts: [DECOY, DECOY, "example.test"] }))).toMatchObject({
      verdict: "RE-ASKS-AFTER-TEARDOWN",
      exit: 0,
    });
  });
  it("must-PASS non-canonical: F asks three times and arm B lists hosts in another order", () => {
    const v = classify(
      cand({
        fHosts: [DECOY, DECOY, DECOY],
        f2Hosts: [DECOY, "example.test", DECOY],
        mut: (_s, a) => a.get("B")!.calls.reverse(),
      }),
    );
    expect(v).toMatchObject({ verdict: "RE-ASKS-AFTER-TEARDOWN", exit: 0 });
  });
  it("MIXED: F caches within a command, F2 re-asks across commands (exit 0)", () => {
    expect(classify(cand({ f2Hosts: [DECOY, DECOY, "example.test"] }))).toMatchObject({ verdict: "MIXED", exit: 0 });
  });
  it("INCONCLUSIVE incoherent-f-f2: F re-asks, F2 caches (exit 2)", () => {
    expect(classify(cand({ fHosts: [DECOY, DECOY] }))).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "candidate-reading:incoherent-f-f2" });
  });
  it("F2 counts: two decoy and two example.test asks read RE-ASKS-AFTER-TEARDOWN", () => {
    expect(classify(cand({ fHosts: [DECOY, DECOY], f2Hosts: [DECOY, DECOY, "example.test", "example.test"] }))).toMatchObject({
      verdict: "RE-ASKS-AFTER-TEARDOWN",
    });
  });
  it("F2 asking only example.test (the allowed host never asked) is INCONCLUSIVE, never a re-ask", () => {
    const v = classify(cand({ fHosts: [DECOY, DECOY], f2Hosts: ["example.test"] }));
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "candidate-reading:unrecognized-sequence" });
  });
  it("extra input keys still classify, and are recorded as inputShapeChanged", () => {
    const v = classify(
      cand({
        mut: (_s, a) => {
          for (const c of a.get("B")!.calls) if (c.tool === "SandboxNetworkAccess") c.keys = ["host", "port"];
        },
      }),
    );
    expect(v).toMatchObject({ verdict: "CACHES", exit: 0 });
    expect(v.candidate!.arms.B.inputShapeChanged).toEqual(["host", "port"]);
  });
  // The plan's reading-shape clauses: F re-asks = the decoy two or more times and no other host; F2 re-asks = the decoy
  // two or more times, example.test at least once, and no other host.
  const shapes: [string, string[], string[]][] = [
    ["F2 re-asks the decoy but never asks example.test", [DECOY, DECOY], [DECOY, DECOY]],
    ["F asks another host", [DECOY, "other.test"], [DECOY, DECOY, "example.test"]],
    ["F2 asks another host", [DECOY, DECOY], [DECOY, DECOY, "example.test", "other.test"]],
  ];
  for (const [name, fHosts, f2Hosts] of shapes) {
    it(`unrecognized-sequence: ${name}`, () => {
      expect(classify(cand({ fHosts, f2Hosts }))).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "candidate-reading:unrecognized-sequence" });
    });
  }
  for (const n of ["F", "F2"]) {
    it(`a tool other than Bash or SandboxNetworkAccess in ${n} is INCONCLUSIVE unknown-tool (a renamed ask is never dropped)`, () => {
      const v = classify(cand({ mut: (_s, a) => a.get(n)!.calls.push({ tool: "NetworkAccess", input: { host: DECOY }, keys: ["host"] }) }));
      expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "candidate-reading:unknown-tool" });
    });
  }
  it("an unknown tool in the baseline's F fails the baseline reading", () => {
    const v = classify(input({ baseline: baselineRun((_s, a) => a.get("F")!.calls.push({ tool: "Read", keys: ["file_path"] })) }));
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "baseline:reading" });
    expect(v.baseline!.readingWhy).toBe("unknown-tool");
  });
  it("readCache does not depend on MEASURED_BASELINE (a moved re-ask baseline cannot invert it)", () => {
    const b = MEASURED_BASELINE as unknown as Rec;
    const saved = { ...b };
    const run = (o: Parameters<typeof harnessRun>[0]) => {
      const p = parseHarnessOutput(harnessRun(o));
      if (!p.ok) throw new Error(p.reason);
      return p.run;
    };
    try {
      Object.assign(b, { reading: "RE-ASKS-AFTER-TEARDOWN", fHosts: [DECOY, DECOY, DECOY], f2Hosts: [DECOY, DECOY, "example.test"] });
      expect(readCache(run({})).reading).toBe("CACHES");
      expect(readCache(run({ fHosts: [DECOY, DECOY, DECOY], f2Hosts: [DECOY, DECOY, "example.test"] })).reading).toBe("RE-ASKS-AFTER-TEARDOWN");
    } finally {
      for (const k of Object.keys(b)) delete b[k];
      Object.assign(b, saved);
    }
    expect(MEASURED_BASELINE.reading).toBe("CACHES");
  });
});

describe("INCONCLUSIVE: one case per precondition (one-field change, exact reason)", () => {
  for (const d of ["198.51.100.1:443", "198.51.100.1:80", "198.51.100.1:22", "127.0.0.2:p", "169.254.169.254:80"]) {
    it(`control missed decoy ${d}`, () => {
      const v = classify(
        cand({
          mut: (_s, a) => {
            const c = a.get("control")!;
            c.decoys = c.decoys.filter((x: Rec) => `${x.addr}:${x.addr.startsWith("127.") ? "p" : x.port}` !== d);
          },
        }),
      );
      expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "candidate:control" });
    });
  }
  it("control hit only the first decoy (a `.some` check would pass it)", () => {
    const v = classify(cand({ mut: (_s, a) => (a.get("control")!.decoys = [{ addr: DECOY, port: 443 }]) }));
    expect(v.reason).toBe("candidate:control");
  });
  it("a control gateway line is a precondition failure, not a LEAK", () => {
    const v = classify(cand({ mut: (_s, a) => (a.get("control")!.gateway = [{ line: CONNECT, authOk: false, authPresent: false }]) }));
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "candidate:control" });
  });
  const cases: [string, (s: Rec, a: Map<string, Rec>) => void, string][] = [
    ["fPortClosed false", (_s, a) => (a.get("F")!.fPortClosed = false), "candidate:teardown"],
    ["F2 fTornDown false", (_s, a) => (a.get("F2")!.fTornDown = false), "candidate:teardown"],
    ["f-barrier seen=no", (_s, a) => (a.get("F")!.toolResult = a.get("F")!.toolResult.replace("f-barrier seen=yes", "f-barrier seen=no")), "candidate:teardown"],
    ["f2-barrier seen=no", (_s, a) => (a.get("F2")!.toolResult = a.get("F2")!.toolResult.replace("f2-barrier seen=yes", "f2-barrier seen=no")), "candidate:teardown"],
    ["F gateway carries a second CONNECT", (_s, a) => a.get("F")!.gateway.push({ line: CONNECT, authOk: true, authPresent: true }), "candidate:teardown"],
    ["F2 gateway empty", (_s, a) => (a.get("F2")!.gateway = []), "candidate:teardown"],
    ["f-3 did not hit the dead forwarder", (_s, a) => (a.get("F")!.toolResult = a.get("F")!.toolResult.replace(`f-3 ${DEAD}`, "f-3 rc=0 out=403")), "candidate:post-teardown-ran"],
    ["f-3 never ran", (_s, a) => (a.get("F")!.toolResult = a.get("F")!.toolResult.replace(`R f-3 ${DEAD}`, "")), "candidate:post-teardown-ran"],
    ["f2-2 did not hit the dead forwarder", (_s, a) => (a.get("F2")!.toolResult = a.get("F2")!.toolResult.replace(`f2-2 ${DEAD}`, "f2-2 rc=0 out=403")), "candidate:post-teardown-ran"],
    ["zero SandboxNetworkAccess calls in arm B", (_s, a) => (a.get("B")!.calls = a.get("B")!.calls.filter((c: Rec) => c.tool !== "SandboxNetworkAccess")), "candidate:asked"],
    ["a non-string host", (_s, a) => (a.get("E")!.calls[1].input = { host: 7 }), "candidate:asked"],
    ["a non-string host in B's second SandboxNetworkAccess call", (_s, a) => (a.get("B")!.calls[2].input = { host: 7 }), "candidate:asked"],
    ["step0.sdkEntry is the baseline's entry (the wrong SDK was measured)", (s) => (s.sdkEntry = BASE_ENTRY), "candidate:sdk-entry"],
    ["step0.sdkEntry missing", (s) => delete s.sdkEntry, "candidate:sdk-entry"],
    ["step0.sdkEntry does not exist", (s) => (s.sdkEntry = join(ROOT, "nowhere", "sdk.mjs")), "candidate:sdk-entry"],
    ...(["decoys", "gateway", "calls"] as const).map(
      (f): [string, (s: Rec, a: Map<string, Rec>) => void, string] => [`arm B without a ${f} list`, (_s, a) => delete a.get("B")![f], "candidate:arms-present"],
    ),
    ["a missing arm record", (_s, a) => a.delete("E"), "candidate:arms-present"],
    ["a thrown value", (_s, a) => (a.get("D")!.thrown = "Error: boom"), "candidate:arms-present"],
    ["observed sdkVersion is the baseline 0.3.321", (s) => (s.sdkVersion = "0.3.321"), "candidate:versions"],
    ["cliVersion 2.1.326 vs expected 2.1.32 (exact token)", () => undefined, "candidate:versions"],
    ["one arm's initClaudeCodeVersion differs", (_s, a) => (a.get("F2")!.initClaudeCodeVersion = "2.1.321"), "candidate:versions"],
    ["an arm's initClaudeCodeVersion missing", (_s, a) => delete a.get("B")!.initClaudeCodeVersion, "candidate:versions"],
  ];
  for (const [name, mut, reason] of cases) {
    it(name, () => {
      const i = name.startsWith("cliVersion") ? { ...input(), candidate: { ...input().candidate, expectedCli: "2.1.32" } } : cand({ mut });
      expect(classify(i)).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason });
    });
  }
  it("baseline: the baseline reading RE-ASKS-AFTER-TEARDOWN is INCONCLUSIVE (baseline)", () => {
    const b = harnessRun({ sdk: "0.3.321", cli: "2.1.321", entry: BASE_ENTRY, fHosts: [DECOY, DECOY], f2Hosts: [DECOY, DECOY, "example.test"] });
    const v = classify(input({ baseline: b }));
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "baseline:reading" });
    // The candidate fixture is untouched by the baseline mutation (fresh objects).
    expect(v.candidate!.reading).toBe("CACHES");
  });
  it("sdk-entry compares realpaths: a symlink to the expected entry passes", () => {
    const link = join(ROOT, "link-sdk.mjs");
    if (!existsSync(link)) symlinkSync(CAND_ENTRY, link);
    expect(classify(cand({ mut: (s) => (s.sdkEntry = link) }))).toMatchObject({ verdict: "CACHES", exit: 0 });
  });
  it("baseline: a baseline precondition failure outranks the candidate", () => {
    const v = classify(input({ baseline: baselineRun((_s, a) => (a.get("F")!.fPortClosed = false)), candidate: harnessRun({ fHosts: [DECOY, DECOY] }) }));
    expect(v.reason).toBe("baseline:teardown");
  });
});

describe("LEAK (exit 4) and precedence", () => {
  it("a decoy hit in the candidate's arm B", () => {
    const v = classify(cand({ mut: (_s, a) => a.get("B")!.decoys.push({ addr: DECOY, port: 443 }) }));
    expect(v).toMatchObject({ verdict: "LEAK", exit: 4, reason: "candidate:B:decoy" });
  });
  it("a decoy hit in the baseline is LEAK (baseline)", () => {
    const v = classify(input({ baseline: baselineRun((_s, a) => a.get("F")!.decoys.push({ addr: DECOY, port: 443 })) }));
    expect(v).toMatchObject({ verdict: "LEAK", exit: 4, reason: "baseline:F:decoy" });
  });
  it("an offender that is not the first gateway line: B's second CONNECT lacks the credential", () => {
    const v = classify(cand({ mut: (_s, a) => (a.get("B")!.gateway[1].authOk = false) }));
    expect(v).toMatchObject({ verdict: "LEAK", exit: 4, reason: "candidate:B:gateway-auth" });
  });
  for (const n of ["B", "D", "E", "F", "F2"]) {
    it(`a decoy hit in arm ${n} is LEAK`, () => {
      const v = classify(cand({ mut: (_s, a) => a.get(n)!.decoys.push({ addr: DECOY, port: 443 }) }));
      expect(v).toMatchObject({ verdict: "LEAK", exit: 4, reason: `candidate:${n}:decoy` });
    });
  }
  it("authOk false in arm E", () => {
    const v = classify(cand({ mut: (_s, a) => a.get("E")!.gateway.push({ line: CONNECT, authOk: false, authPresent: true }) }));
    expect(v).toMatchObject({ verdict: "LEAK", exit: 4, reason: "candidate:E:gateway-auth" });
  });
  it("LEAK outranks a failed precondition in the same run", () => {
    const v = classify(
      cand({
        mut: (_s, a) => {
          a.get("F")!.fPortClosed = false;
          a.get("B")!.decoys.push({ addr: DECOY, port: 80 });
        },
      }),
    );
    expect(v).toMatchObject({ verdict: "LEAK", exit: 4 });
  });
  it("LEAK outranks step0.ok false in the other run", () => {
    const v = classify(
      input({
        baseline: baselineRun((s) => (s.ok = false)),
        candidate: harnessRun({ mut: (_s, a) => a.get("B")!.decoys.push({ addr: DECOY, port: 443 }) }),
      }),
    );
    expect(v).toMatchObject({ verdict: "LEAK", exit: 4 });
  });
});

describe("UNVERIFIED (exit 3) and ERROR (exit 1)", () => {
  it("step0.ok false in the candidate", () => {
    const v = classify(
      cand({
        mut: (s, a) => {
          s.ok = false;
          s.nestedBwrap = false;
          a.clear();
        },
      }),
    );
    expect(v).toMatchObject({ verdict: "UNVERIFIED", exit: 3, reason: "step0:candidate:nestedBwrap" });
  });
  it("step0 without an ok key is UNVERIFIED (unknown when no listed probe failed)", () => {
    expect(classify(cand({ mut: (s) => delete s.ok }))).toMatchObject({ verdict: "UNVERIFIED", exit: 3, reason: "step0:candidate:unknown" });
  });
  it("a failed alias probe is named in the UNVERIFIED reason", () => {
    const v = classify(cand({ mut: (s) => Object.assign(s, { ok: false, aliases: [{ a: "10.0.0.2/32", ok: false }] }) }));
    expect(v).toMatchObject({ verdict: "UNVERIFIED", exit: 3, reason: "step0:candidate:aliases" });
  });
  it("step0.ok false in the baseline", () => {
    expect(classify(input({ baseline: baselineRun((s) => (s.ok = false)) }))).toMatchObject({ verdict: "UNVERIFIED", exit: 3 });
  });
  it("noise lines between records are ignored", () => {
    expect(classify(input({ candidate: harnessRun({ noise: true }) }))).toMatchObject({ verdict: "CACHES", exit: 0 });
  });
  it("a malformed NETNS_ARM JSON line is ERROR, never a silent drop", () => {
    const v = classify(input({ candidate: `${harnessRun()}\nNETNS_ARM {"arm":"F",\n` }));
    expect(v).toMatchObject({ verdict: "ERROR", exit: 1, reason: "candidate:parse-arm" });
  });
  it("empty stdout is ERROR", () => {
    expect(classify(input({ candidate: "" }))).toMatchObject({ verdict: "ERROR", exit: 1, reason: "candidate:no-step0" });
  });
  it("a missing NETNS_STEP0 line is ERROR", () => {
    const s = harnessRun().split("\n").filter((l) => !l.startsWith("NETNS_STEP0")).join("\n");
    expect(classify(input({ candidate: s }))).toMatchObject({ verdict: "ERROR", exit: 1, reason: "candidate:no-step0" });
  });
  it("a __harness__ crash record is ERROR", () => {
    const s = `${harnessRun()}\nNETNS_ARM ${JSON.stringify({ arm: "__harness__", thrown: "boom" })}\n`;
    expect(classify(input({ candidate: s }))).toMatchObject({ verdict: "ERROR", exit: 1, reason: "candidate:harness-crash" });
  });
  it("an arm record whose arm is not a string is ERROR parse-arm", () => {
    const v = classify(input({ candidate: `${harnessRun()}\nNETNS_ARM ${JSON.stringify({ arm: 7, thrown: "" })}\n` }));
    expect(v).toMatchObject({ verdict: "ERROR", exit: 1, reason: "candidate:parse-arm" });
  });
  it("a second record for the same arm is ERROR duplicate-arm (a clean copy cannot hide a leaky first one)", () => {
    const leaky = harnessRun({ mut: (_s, a) => a.get("F")!.decoys.push({ addr: DECOY, port: 443 }) });
    const cleanF = harnessRun().split("\n").find((l) => l.startsWith('NETNS_ARM {"arm":"F",'))!;
    expect(classify(input({ candidate: `${leaky}${cleanF}\n` }))).toMatchObject({ verdict: "ERROR", exit: 1, reason: "candidate:duplicate-arm" });
  });
  it("a second NETNS_STEP0 record is ERROR duplicate-step0", () => {
    const s = `${harnessRun()}NETNS_STEP0 ${JSON.stringify({ ok: true })}\n`;
    expect(classify(input({ candidate: s }))).toMatchObject({ verdict: "ERROR", exit: 1, reason: "candidate:duplicate-step0" });
  });
  it("parseHarnessOutput reports a parse failure instead of dropping the line", () => {
    expect(parseHarnessOutput("NETNS_STEP0 {bad").ok).toBe(false);
  });
});

describe("CLI: --out, --markdown and sentinel redaction", () => {
  let dir = "";
  afterEach(() => {
    vi.unstubAllEnvs();
    if (dir) rmSync(dir, { recursive: true, force: true });
    dir = "";
  });
  const ENV_ROWS = { startedAt: "2026-11-20T00:00:00Z", nodeVersion: "v22.11.0", npmVersion: "11.20.0", kernel: "7.2.15", os: "fixtureos" };
  async function runMain(cand: string, o: { env?: Rec; drop?: string } = {}) {
    dir = mkdtempSync(join(tmpdir(), "snv-"));
    writeFileSync(join(dir, "baseline.out"), baselineRun());
    writeFileSync(join(dir, "candidate.out"), cand);
    writeFileSync(join(dir, "env.json"), JSON.stringify(o.env ?? ENV_ROWS));
    const args: [string, string][] = [
      ["--baseline", join(dir, "baseline.out")],
      ["--candidate", join(dir, "candidate.out")],
      ["--baseline-sdk", "0.3.321"],
      ["--baseline-cli", "2.1.321"],
      ["--candidate-sdk", CAND_SDK],
      ["--candidate-cli", CAND_CLI],
      ["--baseline-entry", BASE_ENTRY],
      ["--candidate-entry", CAND_ENTRY],
      ["--requested", "latest"],
      ["--command", "bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh latest"],
      ["--scratch-root", ROOT],
      ["--env", join(dir, "env.json")],
      ["--out", join(dir, "verdict.json")],
      ["--markdown", join(dir, "md")],
    ];
    const out: string[] = [];
    const code = await main(args.filter(([k]) => k !== o.drop).flat(), (s) => out.push(s));
    return { code, stdout: out.join("") };
  }
  it("writes the verdict JSON and one draft under both names, and never carries the sentinel", async () => {
    const c = harnessRun({
      mut: (_s, a) => {
        a.get("B")!.stubRequests = [{ headers: { "x-api-key": SENTINEL } }];
        a.get("B")!.toolResult = `R b ${SENTINEL}`;
        a.get("B")!.calls[1].message = SENTINEL;
      },
    });
    const { code, stdout } = await runMain(c);
    expect(code).toBe(0);
    expect(stdout).toMatch(/^REMEASURE verdict=CACHES exit=0 reason=measured next=#12906 stays blocked; re-run on the next SDK bump$/m);
    const json = readFileSync(join(dir, "verdict.json"), "utf8");
    const add = readFileSync(join(dir, "md", "addendum.md"), "utf8");
    const com = readFileSync(join(dir, "md", "issue-comment.md"), "utf8");
    expect(com).toBe(add);
    for (const t of [stdout, json, add]) expect(t).not.toContain(SENTINEL);
    const v = JSON.parse(json);
    expect(v.requested).toBe("latest");
    expect(v.env).toEqual(ENV_ROWS);
    expect(v.candidate.step0.sdkEntry).toBe("<scratch>/candidate/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs");
    expect(add).toContain("bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh latest");
    expect(add).toContain(`\`${CAND_SDK}\``);
    expect(add).toContain("| `F2` |");
    expect(add).toContain("- nodeVersion: `v22.11.0`");
    expect(add).toContain("- npmVersion: `11.20.0`");
    expect(add).toContain("<!-- POLICY: paste the dated ADR-278 policy sentences here -->");
  });
  it("propagates a non-zero verdict exit code", async () => {
    const { code, stdout } = await runMain(harnessRun({ fHosts: [DECOY, DECOY] }));
    expect(code).toBe(2);
    expect(stdout).toMatch(/^REMEASURE verdict=INCONCLUSIVE exit=2 reason=candidate-reading:incoherent-f-f2 next=/m);
    expect(existsSync(join(dir, "verdict.json"))).toBe(true);
  });
  for (const flag of ["--baseline-entry", "--candidate-entry"]) {
    it(`a missing ${flag} is ERROR classifier-args`, async () => {
      const { code, stdout } = await runMain(harnessRun(), { drop: flag });
      expect(code).toBe(1);
      expect(stdout).toMatch(new RegExp(`^REMEASURE verdict=ERROR exit=1 reason=classifier-args next=pass ${flag}$`, "m"));
    });
  }
  it("USER=node / npm with the script's env rows present is not refused", async () => {
    for (const u of ["node", "npm"]) {
      vi.stubEnv("USER", u);
      vi.stubEnv("LOGNAME", u);
      const { code, stdout } = await runMain(harnessRun());
      expect(stdout, u).toMatch(/^REMEASURE verdict=CACHES exit=0 /m);
      expect(code).toBe(0);
      rmSync(dir, { recursive: true, force: true });
    }
  });
  it("a USER that appears in the output is refused before anything is written", async () => {
    vi.stubEnv("USER", "zzfixtureuser");
    const { code, stdout } = await runMain(harnessRun({ mut: (_s, a) => (a.get("B")!.gateway[0].line = "CONNECT zzfixtureuser.test:443 HTTP/1.1") }));
    expect(code).toBe(1);
    expect(stdout).toMatch(/^REMEASURE verdict=ERROR exit=1 reason=redaction-refused:user /m);
    expect(existsSync(join(dir, "verdict.json"))).toBe(false);
  });
  it("table prints one `<VERDICT>\\t<next>` line per verdict, in precedence order, from NEXT", async () => {
    const out: string[] = [];
    expect(await main(["table"], (s) => out.push(s))).toBe(0);
    const rows = out.join("").trimEnd().split("\n").map((l) => l.split("\t"));
    expect(rows.map((r) => r[0])).toEqual(["ERROR", "LEAK", "UNVERIFIED", "INCONCLUSIVE", "CACHES", "RE-ASKS-AFTER-TEARDOWN", "MIXED"]);
    expect(rows.map((r) => r[0])).toEqual([...VERDICTS]);
    for (const [v, next] of rows) expect(next).toBe(NEXT[v as keyof typeof NEXT]);
    expect(NEXT.CACHES).toBe("#12906 stays blocked; re-run on the next SDK bump");
    expect(NEXT["RE-ASKS-AFTER-TEARDOWN"]).toContain("it is not proof that an allow is revocable");
    expect(NEXT.ERROR).toContain("app-mutated also files a bug");
  });
  it("baseline-json carries the pin, the arm list and the sentinel", async () => {
    const out: string[] = [];
    expect(await main(["baseline-json"], (s) => out.push(s))).toBe(0);
    const j = JSON.parse(out.join(""));
    expect(j).toEqual({ ...MEASURED_BASELINE, arms: [...ARMS], sentinel: SENTINEL });
  });
});

describe("identityLeak: one case per branch", () => {
  const id = { home: "/home/zzfixture", user: "zzuser", logname: "zzlogin", host: "zzhost" };
  const cases: [string, string, string | null][] = [
    ["sentinel", `x ${SENTINEL} y`, "stub-sentinel"],
    ["home path", "cwd /home/zzfixture/repo", "home"],
    ["user, case-insensitive", "owner ZZUser here", "user"],
    ["user joined by - and .", "kernel 7.2-zzuser.x", "user"],
    ["user at a leading dot", "file x.zzuser", "user"],
    ["logname", "by zzlogin.", "logname"],
    ["hostname joined by -", "kernel 7.2.15-1-zzhost", "hostname"],
    ["egress token path", "/run/egress-tokens/abcdefghijklmnopq", "egress-token"],
    ["no identity: a longer word", "zzuserx zzhosts node_modules", null],
  ];
  for (const [name, text, want] of cases) it(name, () => expect(identityLeak(text, id)).toBe(want));
  it("USER=node never matches the script's env keys or node_modules", () => {
    const text = "- nodeVersion: `v22.11.0`\n- npmVersion: `11.20.0`\n<scratch>/candidate/node_modules/x";
    expect(identityLeak(text, { user: "node", logname: "npm", host: "zzhost" })).toBeNull();
  });
  it("a hostname equal to the os-release ID (the distro default) is benign, other hosts are not", () => {
    const text = "- os: `omarchy`";
    expect(identityLeak(text, { host: "omarchy" }, ["omarchy"])).toBeNull();
    expect(identityLeak(text, { host: "omarchy" })).toBe("hostname");
  });
});

describe("Markdown drafts: candidate strings are inert", () => {
  it("mdCell makes a code span: backticks replaced, backslash and | escaped, @ stripped, newlines flattened", () => {
    expect(mdCell("a|b")).toBe("`a\\|b`");
    expect(mdCell("x`y")).toBe("`x'y`");
    expect(mdCell("a\\")).toBe("`a\\\\`");
    expect(mdCell("hi @octocat")).toBe("`hi octocat`");
    expect(mdCell("l1\nl2")).toBe("`l1 l2`");
    expect(mdCell("")).toBe("`-`");
  });
  it("safeHost keeps hostnames and IP literals, anything else is <invalid>", () => {
    for (const h of ["example.test", DECOY, "::1", "LOCALHOST.", "x.supabase.co"]) expect(safeHost(h)).toBe(h);
    for (const h of ["a|b", "x](http://evil)", "<img>", "a b", "", 7, null]) expect(safeHost(h)).toBe("<invalid>");
  });
  it("an injected host, gateway line and version render only as code spans", () => {
    const v = classify(
      cand({
        mut: (s, a) => {
          s.sdkVersion = "0.3.326 | @owner";
          a.get("B")!.calls[1].input = { host: "x](http://evil) | @octocat" };
          a.get("B")!.gateway[0].line = "CONNECT `a`|<b>@c HTTP/1.1";
        },
      }),
    );
    const md = renderDrafts(v, { requested: "latest", command: "bash x.sh latest" });
    expect(md).not.toContain("@");
    expect(md).not.toContain("](http://evil)");
    expect(md).toContain("`<invalid>, 198.51.100.1`");
    expect(md).toContain("`CONNECT 'a'\\|<b>c HTTP/1.1; CONNECT 198.51.100.1:443 HTTP/1.1`");
    expect(md).toContain("`0.3.326 \\| owner`");
    // Every data row of every table has exactly its column count of unescaped pipes.
    for (const row of md.split("\n").filter((l) => l.startsWith("| ") && !l.startsWith("| Arm") && !l.startsWith("| |"))) {
      const pipes = row.replace(/\\./g, "").split("|").length - 1;
      expect([4, 5], row).toContain(pipes);
    }
  });
});

describe("result(): the R <label> line of a tool result", () => {
  it("returns the first matching line's value, tolerating CRLF, else <missing>", () => {
    expect(result({ toolResult: "R f-1 a\r\nR f-barrier seen=yes\r\nR f-barrier seen=no" }, "f-barrier")).toBe("seen=yes");
    expect(result({ toolResult: "xR f-3 no\nR f-3x no" }, "f-3")).toBe("<missing>");
    expect(result({ toolResult: null }, "f-3")).toBe("<missing>");
    expect(result(undefined, "f-3")).toBe("<missing>");
  });
});

describe("harness NETNS_SDK_ENTRY wire", () => {
  it("resolveSdkEntry returns the realpath of NETNS_SDK_ENTRY, and loadSdk imports exactly that file", async () => {
    const fake = join(ROOT, "fake-sdk", "sdk.mjs");
    mkdirSync(dirname(fake), { recursive: true });
    writeFileSync(fake, 'export const netnsFixtureMarker = "fake-sdk-entry";\n');
    const link = join(ROOT, "fake-sdk-link.mjs");
    if (!existsSync(link)) symlinkSync(fake, link);
    const entry = resolveSdkEntry({ NETNS_SDK_ENTRY: link });
    expect(entry).toBe(fake);
    const m = (await loadSdk(entry)) as unknown as Rec;
    expect(m.netnsFixtureMarker).toBe("fake-sdk-entry");
  });
  it("unset, resolveSdkEntry is the app's pinned SDK (the runtime suite's path is unchanged)", () => {
    expect(resolveSdkEntry({})).toMatch(/node_modules\/@anthropic-ai\/claude-agent-sdk\/sdk\.mjs$/);
  });
});
