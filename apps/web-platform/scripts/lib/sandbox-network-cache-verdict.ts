// #12906 PR-1b — verdict classifier for the Agent SDK per-host SandboxNetworkAccess allow-cache re-measure.
//
// Reads two outputs of test/helpers/netns-egress-harness.mts (allow-all tap, arms control,B,D,E,F,F2): one run on the
// pinned baseline SDK (MEASURED_BASELINE) and one on the candidate SDK, each installed in its own scratch prefix by
// apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh. It prints one machine-read line,
//
//   REMEASURE verdict=<word> exit=<n> reason=<token> next=<action>
//
// and exits with <n>. It is pure apart from the guarded CLI entry at the bottom (importing it has no side effects); the
// runtime suite imports MEASURED_BASELINE and DEAD_FORWARDER from here so the two cannot drift.
//
// Precedence (fixed; the combine step evaluates it top to bottom):
//   1 ERROR         exit 1  unparseable output, no NETNS_STEP0, a __harness__ crash record, a malformed NETNS_ARM line
//   2 LEAK          exit 4  in either run, a non-control arm hit a decoy or reached the gateway without the credential
//   3 UNVERIFIED    exit 3  step0.ok false in either run (the namespace could not be built on this host)
//   4 INCONCLUSIVE  exit 2  a baseline precondition failed, or the baseline did not read MEASURED_BASELINE.reading
//   5 INCONCLUSIVE  exit 2  a candidate precondition failed
//   6 INCONCLUSIVE  exit 2  the candidate's F/F2 sequence fits no cache model (incl. incoherent-f-f2)
//   7 CACHES | RE-ASKS-AFTER-TEARDOWN | MIXED  exit 0
//
// Verdict-to-action table (the same table is in the script header and in ADR-278):
//   CACHES                  #12906 stays blocked; record the run in ADR-278 and on #12906
//   RE-ASKS-AFTER-TEARDOWN  record the run; it triggers #12906's build and its live-forwarder deny-flip arm; it is not
//                           proof that an allow is revocable
//   MIXED                   record the run; most consistent with a per-command cache; a trigger like RE-ASKS-AFTER-TEARDOWN
//   INCONCLUSIVE            re-run once; then record the run and file an issue naming the reason
//   ERROR                   fix the cause and re-run; app-mutated also files a bug against the script
//   LEAK                    separate ADR-278 addendum plus a bug issue against adopting that SDK
//   UNVERIFIED              record UNVERIFIED:sdk-<v>-sandbox-network-allow-cache and file an issue
//   REFUSED                 (script only) no finding; wait for the floor, or file a security issue

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { hostname } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

/** The answer measured on the production pin (PR #12897, ADR-278 addendum 2026-11-18). Moves only with a CACHES verdict
 * on the new pin and an ADR-278 addendum in the same PR. */
export const MEASURED_BASELINE = {
  version: "0.3.321",
  reading: "CACHES",
  fHosts: ["198.51.100.1"],
  f2Hosts: ["198.51.100.1", "example.test"],
  integrity: {
    sdk: "sha512-Smer/h/jQLTtT+l4sxaAUwZq7wif/9RzzuqltS5Gy+kAFo/iP89H7JHa8avhVT0xGkPBvBD/1Bbdg3pcArhQcw==",
    linuxX64: "sha512-i/Y8Ps4q68SRwWB54yFXyItBwn5YHIOYY4R1gla6p4UwF/pM+xxrHycv+yecbC7oU30ShuBYKWN9mRIZ/BCMqw==",
  },
} as const;

// A request routed at a dead forwarder fails in one of two measured shapes (rc=7 locally, rc=56 + 502 on CI runners).
export const DEAD_FORWARDER = /^rc=7 |^rc=56 out=curl: \(56\) CONNECT tunnel failed, response 502 /;

export const ARMS = ["control", "B", "D", "E", "F", "F2"] as const;
export const CONTROL_DECOYS = ["198.51.100.1:443", "198.51.100.1:80", "198.51.100.1:22", "127.0.0.2:p", "169.254.169.254:80"];
const DECOY = "198.51.100.1";
const NEW_HOST = "example.test";
const TEARDOWN_GATEWAY = [`CONNECT ${DECOY}:443 HTTP/1.1`];
const SENTINEL = "decoy-api-key-sentinel";

type Rec = Record<string, any>;
export interface ParsedRun {
  step0: Rec;
  arms: Map<string, Rec>;
}
export type ParseResult = { ok: true; run: ParsedRun } | { ok: false; reason: string };

export function parseHarnessOutput(stdout: string): ParseResult {
  let step0: Rec | undefined;
  const arms = new Map<string, Rec>();
  for (const line of stdout.split("\n")) {
    if (line.startsWith("NETNS_STEP0 ")) {
      try {
        step0 = JSON.parse(line.slice(12));
      } catch {
        return { ok: false, reason: "parse-step0" };
      }
    } else if (line.startsWith("NETNS_ARM ")) {
      let a: Rec;
      try {
        a = JSON.parse(line.slice(10));
      } catch {
        return { ok: false, reason: "parse-arm" };
      }
      if (a?.arm === "__harness__") return { ok: false, reason: "harness-crash" };
      if (typeof a?.arm !== "string") return { ok: false, reason: "parse-arm" };
      arms.set(a.arm, a);
    }
  }
  if (!step0 || typeof step0 !== "object") return { ok: false, reason: "no-step0" };
  return { ok: true, run: { step0, arms } };
}

const netCalls = (a: Rec | undefined): Rec[] => (Array.isArray(a?.calls) ? a!.calls.filter((c: Rec) => c?.tool === "SandboxNetworkAccess") : []);
const hostsOf = (a: Rec | undefined): unknown[] => netCalls(a).map((c) => c?.input?.host);
const result = (a: Rec | undefined, label: string): string =>
  (typeof a?.toolResult === "string" ? a.toolResult.match(new RegExp(`^R ${label} (.*)$`, "m"))?.[1] : undefined) ?? "<missing>";
const eqList = (x: unknown[], y: readonly string[]) => x.length === y.length && x.every((v, i) => v === y[i]);
const count = (x: unknown[], v: string) => x.filter((h) => h === v).length;

interface Ctx {
  run: ParsedRun;
  expectedSdk: string;
  expectedCli: string;
}
export interface Precondition {
  name: string;
  check: (c: Ctx) => boolean;
}

/** The per-run preconditions, iterated by the combine step in this order. Adding one means adding a member here. */
export const PRECONDITIONS: Precondition[] = [
  {
    name: "versions",
    check: ({ run, expectedSdk, expectedCli }) =>
      run.step0.sdkVersion === expectedSdk &&
      run.step0.cliVersion === expectedCli &&
      ARMS.every((n) => !run.arms.has(n) || run.arms.get(n)!.initClaudeCodeVersion === expectedCli),
  },
  {
    name: "arms-present",
    check: ({ run }) => ARMS.every((n) => run.arms.has(n) && run.arms.get(n)!.thrown === ""),
  },
  {
    name: "control",
    check: ({ run }) => {
      const c = run.arms.get("control");
      if (!c || !Array.isArray(c.decoys)) return false;
      const hit = new Set(c.decoys.map((d: Rec) => `${d.addr}:${String(d.addr).startsWith("127.") ? "p" : d.port}`));
      return CONTROL_DECOYS.every((d) => hit.has(d)) && Array.isArray(c.gateway) && c.gateway.length === 0;
    },
  },
  {
    name: "teardown",
    check: ({ run }) =>
      (["F", "F2"] as const).every((n) => {
        const a = run.arms.get(n);
        if (!a) return false;
        const gw = Array.isArray(a.gateway) ? a.gateway : [];
        return (
          a.fStep1 === true &&
          a.fTornDown === true &&
          a.fPortClosed === true &&
          result(a, n === "F" ? "f-barrier" : "f2-barrier") === "seen=yes" &&
          eqList(gw.map((g: Rec) => g.line), TEARDOWN_GATEWAY) &&
          gw.every((g: Rec) => g.authOk === true)
        );
      }),
  },
  {
    name: "post-teardown-ran",
    check: ({ run }) => DEAD_FORWARDER.test(result(run.arms.get("F"), "f-3")) && DEAD_FORWARDER.test(result(run.arms.get("F2"), "f2-2")),
  },
  {
    name: "asked",
    check: ({ run }) =>
      ARMS.filter((n) => n !== "control" && n !== "D").every((n) => {
        const calls = netCalls(run.arms.get(n));
        return calls.length > 0 && calls.every((c) => typeof c?.input?.host === "string");
      }),
  },
];

export type Reading = "CACHES" | "RE-ASKS-AFTER-TEARDOWN" | "MIXED" | "INCONCLUSIVE";
export function readCache(run: ParsedRun): { reading: Reading; why?: string } {
  const f = hostsOf(run.arms.get("F"));
  const f2 = hostsOf(run.arms.get("F2"));
  const fCaches = eqList(f, MEASURED_BASELINE.fHosts);
  const f2Caches = eqList(f2, MEASURED_BASELINE.f2Hosts);
  const fReasks = f.length >= 2 && f.every((h) => h === DECOY);
  const f2Reasks = count(f2, DECOY) >= 2 && count(f2, NEW_HOST) >= 1 && f2.every((h) => h === DECOY || h === NEW_HOST);
  if (fCaches && f2Caches) return { reading: "CACHES" };
  if (fReasks && f2Reasks) return { reading: "RE-ASKS-AFTER-TEARDOWN" };
  if (fCaches && f2Reasks) return { reading: "MIXED" };
  if (fReasks && f2Caches) return { reading: "INCONCLUSIVE", why: "incoherent-f-f2" };
  return { reading: "INCONCLUSIVE", why: "unrecognized-sequence" };
}

function leakIn(run: ParsedRun): string | null {
  for (const [name, a] of run.arms) {
    if (name === "control") continue;
    if (Array.isArray(a.decoys) && a.decoys.length > 0) return `${name}:decoy`;
    if (Array.isArray(a.gateway) && a.gateway.some((g: Rec) => g?.authOk !== true)) return `${name}:gateway-auth`;
  }
  return null;
}

export interface ArmSummary {
  askedHosts: unknown[];
  inputShapeChanged?: string[];
  gateway: string[];
  decoys: string[];
  initClaudeCodeVersion: unknown;
}
export interface RunSummary {
  step0: Rec;
  preconditions: { name: string; ok: boolean }[];
  reading: Reading;
  readingWhy?: string;
  arms: Record<string, ArmSummary>;
}
export interface Verdict {
  verdict: "CACHES" | "RE-ASKS-AFTER-TEARDOWN" | "MIXED" | "INCONCLUSIVE" | "LEAK" | "UNVERIFIED" | "ERROR";
  exit: 0 | 1 | 2 | 3 | 4;
  reason: string;
  next: string;
  baseline: RunSummary | null;
  candidate: RunSummary | null;
}
export interface RunInput {
  stdout: string;
  expectedSdk: string;
  expectedCli: string;
}
export interface ClassifyInput {
  baseline: RunInput;
  candidate: RunInput;
}

const STEP0_FIELDS = ["ok", "loUp", "nestedBwrap", "shimBwrap", "imports", "sdkEntry", "sdkVersion", "cliPath", "cliVersion"];
function summarize(c: Ctx): RunSummary {
  const step0: Rec = {};
  for (const k of STEP0_FIELDS) if (k in c.run.step0) step0[k] = c.run.step0[k];
  const arms: Record<string, ArmSummary> = {};
  for (const [name, a] of c.run.arms) {
    const changed = netCalls(a).find((x) => !(Array.isArray(x.keys) && x.keys.length === 1 && x.keys[0] === "host"));
    arms[name] = {
      askedHosts: hostsOf(a),
      ...(changed ? { inputShapeChanged: Array.isArray(changed.keys) ? changed.keys.map(String) : [] } : {}),
      gateway: (Array.isArray(a.gateway) ? a.gateway : []).map((g: Rec) => `${g.line}${g.authOk === true ? "" : " (no credential)"}`),
      decoys: (Array.isArray(a.decoys) ? a.decoys : []).map((d: Rec) => `${d.addr}:${d.port}`),
      initClaudeCodeVersion: a.initClaudeCodeVersion ?? null,
    };
  }
  const r = readCache(c.run);
  return {
    step0,
    preconditions: PRECONDITIONS.map((p) => ({ name: p.name, ok: p.check(c) })),
    reading: r.reading,
    ...(r.why ? { readingWhy: r.why } : {}),
    arms,
  };
}

const NEXT: Record<Verdict["verdict"], string> = {
  CACHES: "record the run in ADR-278 and on #12906; #12906 stays blocked until the next SDK bump's run",
  "RE-ASKS-AFTER-TEARDOWN": "record the run; it triggers #12906's allow-arm build and its live-forwarder deny-flip arm",
  MIXED: "record the run; a #12906 trigger like RE-ASKS-AFTER-TEARDOWN (most consistent with a per-command cache)",
  INCONCLUSIVE: "re-run once; then record the run and file an issue naming the reason",
  LEAK: "write a separate ADR-278 addendum and file a bug issue against adopting that SDK",
  UNVERIFIED: "record UNVERIFIED:sdk-<v>-sandbox-network-allow-cache and file an issue",
  ERROR: "fix the cause and re-run; record nothing",
};

export function classify(input: ClassifyInput): Verdict {
  const parsed = { baseline: parseHarnessOutput(input.baseline.stdout), candidate: parseHarnessOutput(input.candidate.stdout) };
  const mk = (verdict: Verdict["verdict"], exit: Verdict["exit"], reason: string, b: RunSummary | null, c: RunSummary | null): Verdict => ({
    verdict,
    exit,
    reason,
    next: NEXT[verdict],
    baseline: b,
    candidate: c,
  });
  // 1 ERROR
  for (const which of ["baseline", "candidate"] as const) {
    const p = parsed[which];
    if (!p.ok) return mk("ERROR", 1, `${which}:${p.reason}`, null, null);
  }
  const ctx = {
    baseline: { run: (parsed.baseline as { run: ParsedRun }).run, expectedSdk: input.baseline.expectedSdk, expectedCli: input.baseline.expectedCli },
    candidate: { run: (parsed.candidate as { run: ParsedRun }).run, expectedSdk: input.candidate.expectedSdk, expectedCli: input.candidate.expectedCli },
  };
  const sum = { baseline: summarize(ctx.baseline), candidate: summarize(ctx.candidate) };
  const done = (v: Verdict["verdict"], e: Verdict["exit"], r: string) => mk(v, e, r, sum.baseline, sum.candidate);
  // 2 LEAK
  for (const which of ["candidate", "baseline"] as const) {
    const l = leakIn(ctx[which].run);
    if (l) return done("LEAK", 4, `${which}:${l}`);
  }
  // 3 UNVERIFIED
  for (const which of ["baseline", "candidate"] as const) {
    const s0 = ctx[which].run.step0;
    if (s0.ok !== true) {
      const failed = ["loUp", "aliases", "mounts", "nestedBwrap", "shimBwrap", "imports"].filter((k) => k in s0).filter((k) => {
        const v = s0[k];
        return Array.isArray(v) ? !v.every((x: Rec) => x?.ok === true) : v !== true;
      });
      return done("UNVERIFIED", 3, `step0:${which}:${failed.join(",") || "ok"}`);
    }
  }
  // 4 baseline
  const bFail = sum.baseline.preconditions.find((p) => !p.ok);
  if (bFail) return done("INCONCLUSIVE", 2, `baseline:${bFail.name}`);
  if (sum.baseline.reading !== MEASURED_BASELINE.reading) return done("INCONCLUSIVE", 2, "baseline:reading");
  // 5 candidate
  const cFail = sum.candidate.preconditions.find((p) => !p.ok);
  if (cFail) return done("INCONCLUSIVE", 2, `candidate:${cFail.name}`);
  // 6 / 7
  if (sum.candidate.reading === "INCONCLUSIVE") return done("INCONCLUSIVE", 2, `candidate-reading:${sum.candidate.readingWhy}`);
  return done(sum.candidate.reading, 0, "measured");
}

export function remeasureLine(v: Pick<Verdict, "verdict" | "exit" | "reason" | "next">): string {
  return `REMEASURE verdict=${v.verdict} exit=${v.exit} reason=${v.reason} next=${v.next}`;
}

// ---- output: redaction and drafts ------------------------------------------------------------------------------------

/** Rewrite absolute paths to relative forms, then refuse output that still carries an identity or the stub sentinel. */
export function redact(text: string, roots: { scratch?: string; app?: string }): string {
  let t = text;
  if (roots.scratch) t = t.split(roots.scratch).join("<scratch>");
  if (roots.app) t = t.split(roots.app).join("<app>");
  return t;
}
export function identityLeak(text: string): string | null {
  if (text.includes(SENTINEL)) return "stub-sentinel";
  const home = process.env.HOME;
  if (home && home.length > 1 && text.includes(home)) return "home";
  const word = (w: string | undefined) => w && w.length >= 3 && new RegExp(`(^|[^A-Za-z0-9_.-])${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}($|[^A-Za-z0-9_-])`).test(text);
  if (word(process.env.USER)) return "user";
  if (word(hostname())) return "hostname";
  if (/\/egress-tokens\/[A-Za-z0-9_-]{16,}/.test(text)) return "egress-token";
  return null;
}

export interface RecordMeta {
  requested: string;
  command: string;
  scratchRoot?: string;
  appRoot?: string;
  startedAt?: string;
  env?: Rec;
}

function armTable(r: RunSummary | null): string {
  if (!r) return "_no parsed run_\n";
  const rows = ARMS.map((n) => {
    const a = r.arms[n];
    if (!a) return `| ${n} | _missing_ | | |`;
    return `| ${n} | ${a.askedHosts.map(String).join(", ") || "-"} | ${a.gateway.join("; ") || "-"} | ${a.decoys.join(", ") || "-"} |`;
  });
  return ["| Arm | SandboxNetworkAccess asks (in order) | Gateway lines | Decoy hits |", "|---|---|---|---|", ...rows].join("\n") + "\n";
}

export function renderDrafts(v: Verdict, m: RecordMeta): { addendum: string; comment: string } {
  const vb = v.baseline?.step0 ?? {};
  const vc = v.candidate?.step0 ?? {};
  const versions = [
    "| | Baseline | Candidate |",
    "|---|---|---|",
    `| Requested | ${MEASURED_BASELINE.version} | ${m.requested} |`,
    `| Observed SDK | ${vb.sdkVersion ?? "-"} | ${vc.sdkVersion ?? "-"} |`,
    `| Observed CLI | ${vb.cliVersion ?? "-"} | ${vc.cliVersion ?? "-"} |`,
    `| Reading | ${v.baseline?.reading ?? "-"} | ${v.candidate?.reading ?? "-"} |`,
  ].join("\n");
  const envRows = m.env ? Object.entries(m.env).map(([k, val]) => `- ${k}: ${String(val)}`).join("\n") : "";
  const body = [
    "**Command.**",
    "",
    "```text",
    m.command,
    "```",
    "",
    `**Result.** \`${remeasureLine(v)}\``,
    "",
    "**Versions.**",
    "",
    versions,
    "",
    ...(envRows ? ["**Host.**", "", envRows, ""] : []),
    "**Baseline per-arm outcome.**",
    "",
    armTable(v.baseline),
    "**Candidate per-arm outcome.**",
    "",
    armTable(v.candidate),
    "<!-- POLICY: paste the dated ADR-278 policy sentences here -->",
    "",
  ].join("\n");
  return { addendum: body, comment: body };
}

// ---- CLI ---------------------------------------------------------------------------------------------------------------

function arg(argv: string[], name: string): string | undefined {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
}

export async function main(argv: string[], write: (s: string) => void = (s) => process.stdout.write(s)): Promise<number> {
  const need = ["--baseline", "--candidate", "--baseline-sdk", "--baseline-cli", "--candidate-sdk", "--candidate-cli", "--requested", "--command"];
  const missing = need.filter((n) => arg(argv, n) === undefined);
  if (missing.length) {
    write(`${remeasureLine({ verdict: "ERROR", exit: 1, reason: "classifier-args", next: `pass ${missing.join(",")}` })}\n`);
    return 1;
  }
  const read = (p: string) => {
    try {
      return readFileSync(p, "utf8");
    } catch {
      return "";
    }
  };
  const v = classify({
    baseline: { stdout: read(arg(argv, "--baseline")!), expectedSdk: arg(argv, "--baseline-sdk")!, expectedCli: arg(argv, "--baseline-cli")! },
    candidate: { stdout: read(arg(argv, "--candidate")!), expectedSdk: arg(argv, "--candidate-sdk")!, expectedCli: arg(argv, "--candidate-cli")! },
  });
  let env: Rec | undefined;
  const envPath = arg(argv, "--env");
  if (envPath) {
    try {
      env = JSON.parse(read(envPath));
    } catch {
      env = undefined;
    }
  }
  const meta: RecordMeta = {
    requested: arg(argv, "--requested")!,
    command: arg(argv, "--command")!,
    scratchRoot: arg(argv, "--scratch-root"),
    appRoot: arg(argv, "--app-root"),
    env,
  };
  const roots = { scratch: meta.scratchRoot, app: meta.appRoot };
  const out = redact(
    JSON.stringify({ requested: meta.requested, command: meta.command, env: meta.env ?? null, ...v }, null, 2),
    roots,
  );
  const drafts = renderDrafts(v, meta);
  const texts = [out, redact(drafts.addendum, roots), redact(drafts.comment, roots), redact(remeasureLine(v), roots)];
  const leak = texts.map(identityLeak).find((x) => x !== null);
  if (leak) {
    write(`${remeasureLine({ verdict: "ERROR", exit: 1, reason: `redaction-refused:${leak}`, next: "fix the redaction; record nothing" })}\n`);
    return 1;
  }
  const lines: string[] = [];
  for (const which of ["baseline", "candidate"] as const) {
    const r = v[which];
    if (!r) continue;
    lines.push(`${which}: reading=${r.reading} preconditions=${r.preconditions.map((p) => `${p.name}:${p.ok ? "ok" : "FAIL"}`).join(",")}`);
    for (const n of ARMS) {
      const a = r.arms[n];
      if (a) lines.push(`  ${n}: asks=[${a.askedHosts.map(String).join(",")}] gateway=${a.gateway.length} decoys=${a.decoys.length}${a.inputShapeChanged ? ` WARN inputShapeChanged=${a.inputShapeChanged.join(",")}` : ""}`);
    }
  }
  const outPath = arg(argv, "--out");
  if (outPath) writeFileSync(outPath, `${out}\n`);
  const md = arg(argv, "--markdown");
  if (md) {
    mkdirSync(md, { recursive: true });
    writeFileSync(join(md, "addendum.md"), texts[1]);
    writeFileSync(join(md, "issue-comment.md"), texts[2]);
  }
  write(`${redact(lines.join("\n"), roots)}\n${texts[3]}\n`);
  return v.exit;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e) => {
      process.stdout.write(`${remeasureLine({ verdict: "ERROR", exit: 1, reason: "classifier-crash", next: String(e).slice(0, 200).replace(/\s+/g, " ") })}\n`);
      process.exit(1);
    },
  );
}
