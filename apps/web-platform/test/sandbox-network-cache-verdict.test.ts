// #12906 PR-1b — the verdict classifier for the SDK per-host SandboxNetworkAccess allow-cache re-measure (Guard 1 of the
// plan's Guard Contract). Every fixture is synthesized by `harnessRun()`, which builds FRESH objects on every call, so a
// mutation of the baseline fixture can never leak into the candidate (cq-test-fixtures-synthesized-only).

import { mkdtempSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  ARMS,
  CONTROL_DECOYS,
  DEAD_FORWARDER,
  MEASURED_BASELINE,
  PRECONDITIONS,
  classify,
  main,
  parseHarnessOutput,
  remeasureLine,
  type ClassifyInput,
} from "@/scripts/lib/sandbox-network-cache-verdict";

const DECOY = "198.51.100.1";
const CONNECT = `CONNECT ${DECOY}:443 HTTP/1.1`;
const DEAD = "rc=7 out=000";
const SENTINEL = "decoy-api-key-sentinel";
const CAND_SDK = "0.3.326";
const CAND_CLI = "2.1.326";

type Rec = Record<string, any>;

/** One harness run's stdout, built from fresh objects. `mut` edits the parsed records before they are serialized. */
function harnessRun(o: {
  sdk?: string;
  cli?: string;
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
    sdkEntry: "/scratch/x/candidate/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs",
    sdkVersion: sdk,
    cliPath: "/scratch/x/candidate/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude",
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
  const fHosts = o.fHosts ?? [...MEASURED_BASELINE.fHosts];
  const f2Hosts = o.f2Hosts ?? [...MEASURED_BASELINE.f2Hosts];
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
  harnessRun({ sdk: MEASURED_BASELINE.version, cli: "2.1.321", mut });

function input(over: Partial<{ baseline: string; candidate: string; candCli: string; candSdk: string }> = {}): ClassifyInput {
  return {
    baseline: { stdout: over.baseline ?? baselineRun(), expectedSdk: MEASURED_BASELINE.version, expectedCli: "2.1.321" },
    candidate: { stdout: over.candidate ?? harnessRun(), expectedSdk: over.candSdk ?? CAND_SDK, expectedCli: over.candCli ?? CAND_CLI },
  };
}
const cand = (o: Parameters<typeof harnessRun>[0]) => input({ candidate: harnessRun(o) });

describe("MEASURED_BASELINE and DEAD_FORWARDER", () => {
  it("pin the 0.3.321 reading the runtime suite asserts", () => {
    expect(MEASURED_BASELINE.version).toBe("0.3.321");
    expect(MEASURED_BASELINE.reading).toBe("CACHES");
    expect(MEASURED_BASELINE.fHosts).toEqual([DECOY]);
    expect(MEASURED_BASELINE.f2Hosts).toEqual([DECOY, "example.test"]);
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
    expect(PRECONDITIONS.map((p) => p.name)).toEqual(["versions", "arms-present", "control", "teardown", "post-teardown-ran", "asked"]);
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
    const b = harnessRun({ sdk: "0.3.321", cli: "2.1.321", fHosts: [DECOY, DECOY], f2Hosts: [DECOY, DECOY, "example.test"] });
    const v = classify(input({ baseline: b }));
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exit: 2, reason: "baseline:reading" });
    // The candidate fixture is untouched by the baseline mutation (fresh objects).
    expect(v.candidate!.reading).toBe("CACHES");
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
  it("parseHarnessOutput reports a parse failure instead of dropping the line", () => {
    expect(parseHarnessOutput("NETNS_STEP0 {bad").ok).toBe(false);
  });
});

describe("CLI: --out, --markdown and sentinel redaction", () => {
  let dir = "";
  afterEach(() => {
    if (dir) rmSync(dir, { recursive: true, force: true });
    dir = "";
  });
  async function runMain(cand: string) {
    dir = mkdtempSync(join(tmpdir(), "snv-"));
    const { writeFileSync } = await import("node:fs");
    writeFileSync(join(dir, "baseline.out"), baselineRun());
    writeFileSync(join(dir, "candidate.out"), cand);
    const out: string[] = [];
    const code = await main(
      [
        "--baseline", join(dir, "baseline.out"),
        "--candidate", join(dir, "candidate.out"),
        "--baseline-sdk", "0.3.321", "--baseline-cli", "2.1.321",
        "--candidate-sdk", CAND_SDK, "--candidate-cli", CAND_CLI,
        "--requested", "latest",
        "--command", "bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh latest",
        "--scratch-root", "/scratch/x",
        "--out", join(dir, "verdict.json"),
        "--markdown", join(dir, "md"),
      ],
      (s) => out.push(s),
    );
    return { code, stdout: out.join("") };
  }
  it("writes the verdict JSON and both drafts, and never carries the sentinel", async () => {
    const c = harnessRun({
      mut: (_s, a) => {
        a.get("B")!.stubRequests = [{ headers: { "x-api-key": SENTINEL } }];
        a.get("B")!.toolResult = `R b ${SENTINEL}`;
        a.get("B")!.calls[1].message = SENTINEL;
      },
    });
    const { code, stdout } = await runMain(c);
    expect(code).toBe(0);
    expect(stdout).toMatch(/^REMEASURE verdict=CACHES exit=0 reason=\S+ next=.+$/m);
    const json = readFileSync(join(dir, "verdict.json"), "utf8");
    const add = readFileSync(join(dir, "md", "addendum.md"), "utf8");
    const com = readFileSync(join(dir, "md", "issue-comment.md"), "utf8");
    for (const t of [stdout, json, add, com]) expect(t).not.toContain(SENTINEL);
    const v = JSON.parse(json);
    expect(v.requested).toBe("latest");
    expect(v.candidate.step0.sdkEntry).toBe("<scratch>/candidate/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs");
    for (const t of [add, com]) {
      expect(t).toContain("bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh latest");
      expect(t).toContain(CAND_SDK);
      expect(t).toContain("| F2 |");
      expect(t).toContain("<!-- POLICY: paste the dated ADR-278 policy sentences here -->");
    }
  });
  it("propagates a non-zero verdict exit code", async () => {
    const { code, stdout } = await runMain(harnessRun({ fHosts: [DECOY, DECOY] }));
    expect(code).toBe(2);
    expect(stdout).toMatch(/^REMEASURE verdict=INCONCLUSIVE exit=2 reason=candidate-reading:incoherent-f-f2 next=/m);
    expect(existsSync(join(dir, "verdict.json"))).toBe(true);
  });
});
