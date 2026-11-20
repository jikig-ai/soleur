// #12906 PR-1b — verdict classifier for the Agent SDK per-host SandboxNetworkAccess allow-cache re-measure.
//
// Reads two outputs of test/helpers/netns-egress-harness.mts (allow-all tap, arms control,B,D,E,F,F2): one run on the
// pinned baseline SDK (MEASURED_BASELINE) and one on the candidate SDK, each installed in its own scratch prefix by
// apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh. It prints one machine-read line,
//
//   REMEASURE verdict=<word> exit=<n> reason=<token> next=<action>
//
// and exits with <n>. Importing it has no side effects (the CLI entry at the bottom is guarded); classify() only reads the
// filesystem to realpath the two SDK entries (precondition sdk-entry). The runtime suite and the harness import
// MEASURED_BASELINE, CACHES_MODEL, DEAD_FORWARDER, CONTROL_DECOYS, TEARDOWN_GATEWAY, SENTINEL and result() from here, so
// none of them is restated.
//
// Precedence (fixed; the combine step evaluates it top to bottom):
//   1 ERROR         exit 1  unparseable output, no NETNS_STEP0, a duplicate NETNS_STEP0 or NETNS_ARM, a __harness__ crash
//                           record, a malformed NETNS_ARM line
//   2 LEAK          exit 4  in either run, a non-control arm hit a decoy or reached the gateway without the credential
//   3 UNVERIFIED    exit 3  step0.ok not true in either run (the namespace could not be built on this host)
//   4 INCONCLUSIVE  exit 2  a baseline precondition failed, or the baseline did not read MEASURED_BASELINE.reading
//   5 INCONCLUSIVE  exit 2  a candidate precondition failed
//   6 INCONCLUSIVE  exit 2  the candidate's F/F2 sequence fits no cache model (incl. incoherent-f-f2, unknown-tool)
//   7 CACHES | RE-ASKS-AFTER-TEARDOWN | MIXED  exit 0
//
// Actions per verdict: NEXT below is the only live copy (`... sandbox-network-cache-verdict.ts table` prints it).

import { mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { isIP } from "node:net";
import { hostname } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

/** The answer measured on the production pin (PR #12897, ADR-278 addendum 2026-11-18). MEASURED_BASELINE moves only with
 * a recorded re-measure verdict on the new version and an ADR-278 addendum in the same PR; a move to a version whose
 * reading is not CACHES happens only in #12906's allow-arm PR, which replaces the runtime suite's F/F2 assertions in the
 * same PR. */
export const MEASURED_BASELINE = {
  version: "0.3.321",
  reading: "CACHES",
  integrity: {
    sdk: "sha512-Smer/h/jQLTtT+l4sxaAUwZq7wif/9RzzuqltS5Gy+kAFo/iP89H7JHa8avhVT0xGkPBvBD/1Bbdg3pcArhQcw==",
    linuxX64: "sha512-i/Y8Ps4q68SRwWB54yFXyItBwn5YHIOYY4R1gla6p4UwF/pM+xxrHycv+yecbC7oU30ShuBYKWN9mRIZ/BCMqw==",
  },
} as const;

/** What a caching SDK asks in arms F and F2. This is the CACHES model itself, invariant whatever version is pinned:
 * readCache compares against it and never against MEASURED_BASELINE. */
export const CACHES_MODEL = { fHosts: ["198.51.100.1"], f2Hosts: ["198.51.100.1", "example.test"] } as const;

// A request routed at a dead forwarder fails in one of two measured shapes (rc=7 locally, rc=56 + 502 on CI runners).
export const DEAD_FORWARDER = /^rc=7 |^rc=56 out=curl: \(56\) CONNECT tunnel failed, response 502 /;

export const ARMS = ["control", "B", "D", "E", "F", "F2"] as const;
export const CONTROL_DECOYS = ["198.51.100.1:443", "198.51.100.1:80", "198.51.100.1:22", "127.0.0.2:p", "169.254.169.254:80"];
const DECOY = "198.51.100.1";
const NEW_HOST = "example.test";
/** The one gateway line F and F2 each make before teardown. */
export const TEARDOWN_GATEWAY = [`CONNECT ${DECOY}:443 HTTP/1.1`] as const;
/** The decoy credential the harness hands the forwarder; no record may carry it. */
export const SENTINEL = "decoy-api-key-sentinel";

type Rec = Record<string, any>;
export interface ParsedRun {
  step0: Rec;
  arms: Map<string, Rec>;
}
export type ParseResult = { ok: true; run: ParsedRun } | { ok: false; reason: string };

/** Fail closed on any record the parent cannot attribute: a repeated STEP0 or arm record could hide the first one. */
export function parseHarnessOutput(stdout: string): ParseResult {
  let step0: Rec | undefined;
  let step0Seen = false;
  const arms = new Map<string, Rec>();
  for (const line of stdout.split("\n")) {
    if (line.startsWith("NETNS_STEP0 ")) {
      if (step0Seen) return { ok: false, reason: "duplicate-step0" };
      step0Seen = true;
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
      if (arms.has(a.arm)) return { ok: false, reason: "duplicate-arm" };
      arms.set(a.arm, a);
    }
  }
  if (!step0 || typeof step0 !== "object") return { ok: false, reason: "no-step0" };
  return { ok: true, run: { step0, arms } };
}

const netCalls = (a: Rec | undefined): Rec[] => (Array.isArray(a?.calls) ? a!.calls.filter((c: Rec) => c?.tool === "SandboxNetworkAccess") : []);
const hostsOf = (a: Rec | undefined): unknown[] => netCalls(a).map((c) => c?.input?.host);
/** The `R <label> <value>` line of an arm's tool result (first match), or "<missing>". */
export function result(a: { toolResult?: unknown } | undefined, label: string): string {
  if (typeof a?.toolResult !== "string") return "<missing>";
  const prefix = `R ${label} `;
  const line = a.toolResult.split(/\r\n|[\n\r\u2028\u2029]/).find((l) => l.startsWith(prefix));
  return line === undefined ? "<missing>" : line.slice(prefix.length);
}
const eqList = (x: unknown[], y: readonly string[]) => x.length === y.length && x.every((v, i) => v === y[i]);
const count = (x: unknown[], v: string) => x.filter((h) => h === v).length;
const realpathOrNull = (p: unknown): string | null => {
  if (typeof p !== "string" || p === "") return null;
  try {
    return realpathSync(p);
  } catch {
    return null;
  }
};

interface Ctx {
  run: ParsedRun;
  expectedSdk: string;
  expectedCli: string;
  expectedEntry: string;
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
    // The harness imported the SDK the script installed for this side, not some other copy (e.g. the app's pin).
    name: "sdk-entry",
    check: ({ run, expectedEntry }) => {
      const got = realpathOrNull(run.step0.sdkEntry);
      return got !== null && got === realpathOrNull(expectedEntry);
    },
  },
  {
    // Every arm is present, did not throw, and carries the three lists leakIn and readCache read (a dropped field
    // would otherwise read as "no leak").
    name: "arms-present",
    check: ({ run }) =>
      ARMS.every((n) => {
        const a = run.arms.get(n);
        return !!a && a.thrown === "" && Array.isArray(a.decoys) && Array.isArray(a.gateway) && Array.isArray(a.calls);
      }),
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
    // No authOk clause here: leakIn runs first over the same F/F2 gateway lines and returns LEAK for any line without
    // the credential, so such a clause could never decide a verdict.
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
          eqList(gw.map((g: Rec) => g.line), TEARDOWN_GATEWAY)
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
/** Reads one run's F/F2 sequence against the CACHES model. Takes no baseline: a moved MEASURED_BASELINE cannot change it. */
export function readCache(run: ParsedRun): { reading: Reading; why?: string } {
  // A tool other than Bash or SandboxNetworkAccess in F/F2 could be a renamed network ask that netCalls would drop.
  const unknownTool = (["F", "F2"] as const).some((n) => {
    const calls = run.arms.get(n)?.calls;
    return Array.isArray(calls) && calls.some((c: Rec) => c?.tool !== "Bash" && c?.tool !== "SandboxNetworkAccess");
  });
  if (unknownTool) return { reading: "INCONCLUSIVE", why: "unknown-tool" };
  const f = hostsOf(run.arms.get("F"));
  const f2 = hostsOf(run.arms.get("F2"));
  const fCaches = eqList(f, CACHES_MODEL.fHosts);
  const f2Caches = eqList(f2, CACHES_MODEL.f2Hosts);
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
/** Verdict words in classify-precedence order (the `table` subcommand prints them in this order). */
export const VERDICTS = ["ERROR", "LEAK", "UNVERIFIED", "INCONCLUSIVE", "CACHES", "RE-ASKS-AFTER-TEARDOWN", "MIXED"] as const;
export interface Verdict {
  verdict: (typeof VERDICTS)[number];
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
  /** The SDK entry (sdk.mjs) the script installed for this side; step0.sdkEntry must realpath to it. */
  expectedEntry: string;
}
export interface ClassifyInput {
  baseline: RunInput;
  candidate: RunInput;
}

// The step0 probes that decide step0.ok (each is a boolean or a list of { ok }), and the summary fields: the probes plus
// what was measured. One list, so the UNVERIFIED reason and the recorded summary name the same probes.
const STEP0_PROBES = ["loUp", "aliases", "mounts", "nestedBwrap", "shimBwrap", "imports"];
const STEP0_FIELDS = ["ok", ...STEP0_PROBES, "sdkEntry", "sdkVersion", "cliPath", "cliVersion"];
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

/** The verdict-to-action table: the only live copy (the REMEASURE line, `table`, and the recorded drafts use it). */
export const NEXT: Record<Verdict["verdict"], string> = {
  ERROR: "fix the cause and re-run; record nothing; app-mutated also files a bug against the script",
  LEAK: "write a separate ADR-278 addendum and file a bug issue against adopting that SDK",
  UNVERIFIED: "record UNVERIFIED:sdk-<v>-sandbox-network-allow-cache and file an issue",
  INCONCLUSIVE: "re-run once; then record the run and file an issue naming the reason",
  CACHES: "#12906 stays blocked; re-run on the next SDK bump",
  "RE-ASKS-AFTER-TEARDOWN":
    "record the run; it triggers #12906's allow-arm build and its live-forwarder deny-flip arm; it is not proof that an allow is revocable",
  MIXED: "record the run; a #12906 trigger like RE-ASKS-AFTER-TEARDOWN (most consistent with a per-command cache)",
};

export function classify(input: ClassifyInput): Verdict {
  const parsed = { baseline: parseHarnessOutput(input.baseline.stdout), candidate: parseHarnessOutput(input.candidate.stdout) };
  const mk = (verdict: Verdict["verdict"], exit: Verdict["exit"], reason: string, s?: { baseline: RunSummary; candidate: RunSummary }): Verdict => ({
    verdict,
    exit,
    reason,
    next: NEXT[verdict],
    baseline: s?.baseline ?? null,
    candidate: s?.candidate ?? null,
  });
  // 1 ERROR
  for (const which of ["baseline", "candidate"] as const) {
    const p = parsed[which];
    if (!p.ok) return mk("ERROR", 1, `${which}:${p.reason}`);
  }
  const ctxOf = (which: "baseline" | "candidate"): Ctx => ({ run: (parsed[which] as { run: ParsedRun }).run, ...input[which] });
  const ctx = { baseline: ctxOf("baseline"), candidate: ctxOf("candidate") };
  const sum = { baseline: summarize(ctx.baseline), candidate: summarize(ctx.candidate) };
  // 2 LEAK
  for (const which of ["candidate", "baseline"] as const) {
    const l = leakIn(ctx[which].run);
    if (l) return mk("LEAK", 4, `${which}:${l}`, sum);
  }
  // 3 UNVERIFIED
  for (const which of ["baseline", "candidate"] as const) {
    const s0 = ctx[which].run.step0;
    if (s0.ok !== true) {
      const failed = STEP0_PROBES.filter((k) => k in s0).filter((k) => {
        const v = s0[k];
        return Array.isArray(v) ? !v.every((x: Rec) => x?.ok === true) : v !== true;
      });
      return mk("UNVERIFIED", 3, `step0:${which}:${failed.join(",") || "unknown"}`, sum);
    }
  }
  // 4 baseline
  const bFail = sum.baseline.preconditions.find((p) => !p.ok);
  if (bFail) return mk("INCONCLUSIVE", 2, `baseline:${bFail.name}`, sum);
  if (sum.baseline.reading !== MEASURED_BASELINE.reading) return mk("INCONCLUSIVE", 2, "baseline:reading", sum);
  // 5 candidate
  const cFail = sum.candidate.preconditions.find((p) => !p.ok);
  if (cFail) return mk("INCONCLUSIVE", 2, `candidate:${cFail.name}`, sum);
  // 6 / 7
  if (sum.candidate.reading === "INCONCLUSIVE") return mk("INCONCLUSIVE", 2, `candidate-reading:${sum.candidate.readingWhy}`, sum);
  return mk(sum.candidate.reading, 0, "measured", sum);
}

export function remeasureLine(v: Pick<Verdict, "verdict" | "exit" | "reason" | "next">): string {
  return `REMEASURE verdict=${v.verdict} exit=${v.exit} reason=${v.reason} next=${v.next}`;
}

// ---- output: redaction and drafts ------------------------------------------------------------------------------------

/** Rewrite absolute paths to relative forms. identityLeak then refuses output that still carries an identity. */
export function redact(text: string, roots: { scratch?: string; app?: string }): string {
  let t = text;
  if (roots.scratch) t = t.split(roots.scratch).join("<scratch>");
  if (roots.app) t = t.split(roots.app).join("<app>");
  return t;
}

export interface Identity {
  home?: string;
  user?: string;
  logname?: string;
  host?: string;
}
/**
 * The operator's identity. The script runs this module under `env -i` with HOME pointed at a scratch dir, so it passes
 * the real home as REMEASURE_IDENTITY_HOME; without it the home-path check would compare against the scratch HOME.
 */
export const currentIdentity = (): Identity => ({
  home: process.env.REMEASURE_IDENTITY_HOME || process.env.HOME,
  user: process.env.USER,
  logname: process.env.LOGNAME,
  host: hostname(),
});
const isWordChar = (ch: string | undefined) => ch !== undefined && /[A-Za-z0-9_]/.test(ch);
/** `w` as a whole word, case-insensitively; `-` and `.` count as boundaries on both sides. */
function hasWord(text: string, w: string): boolean {
  const t = text.toLowerCase();
  const n = w.toLowerCase();
  for (let i = t.indexOf(n); i >= 0; i = t.indexOf(n, i + 1)) {
    if (!isWordChar(t[i - 1]) && !isWordChar(t[i + n.length])) return true;
  }
  return false;
}
/**
 * The first identity `text` still carries, or null. `benign` lists values the script wrote as host facts (the os-release
 * ID): an identity equal to one of them (a hostname left at the distro default) tells a reader nothing the record does
 * not already state, so it is not refused. The script's env keys (nodeVersion, npmVersion, ...) are never whole words
 * a USER of `node` or `npm` matches.
 */
export function identityLeak(text: string, id: Identity = currentIdentity(), benign: readonly string[] = []): string | null {
  if (text.includes(SENTINEL)) return "stub-sentinel";
  if (id.home && id.home.length > 1 && text.includes(id.home)) return "home";
  const isBenign = (w: string) => benign.some((b) => b.toLowerCase() === w.toLowerCase());
  const word = (w: string | undefined) => !!w && w.length >= 3 && !isBenign(w) && hasWord(text, w);
  if (word(id.user)) return "user";
  if (word(id.logname)) return "logname";
  if (word(id.host)) return "hostname";
  if (/\/egress-tokens\/[A-Za-z0-9_-]{16,}/.test(text)) return "egress-token";
  return null;
}

export interface RecordMeta {
  requested: string;
  command: string;
  env?: Rec;
}

const HOSTNAME = /^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\.?$/;
/** A host the candidate's CLI asked for, as recorded: a hostname, IPv4 or IPv6 literal, else `<invalid>`. */
export const safeHost = (h: unknown): string => (typeof h === "string" && (isIP(h) !== 0 || HOSTNAME.test(h)) ? h : "<invalid>");
/**
 * One Markdown table cell as an inert code span: line breaks become spaces, a backtick (which would close the span; a
 * backslash cannot escape it inside one) becomes `'`, backslashes and `|` are escaped for the GFM row splitter, and `@`
 * is stripped so no mention is ever sent.
 */
export function mdCell(v: unknown): string {
  const s = String(v)
    .replace(/[\r\n\u2028\u2029]+/g, " ")
    .replace(/`/g, "'")
    .replace(/\\/g, "\\\\")
    .replace(/\|/g, "\\|")
    .replace(/@/g, "");
  return `\`${s === "" ? "-" : s}\``;
}

function armTable(r: RunSummary | null): string {
  if (!r) return "_no parsed run_\n";
  const rows = ARMS.map((n) => {
    const a = r.arms[n];
    if (!a) return `| ${mdCell(n)} | ${mdCell("missing")} | ${mdCell("-")} | ${mdCell("-")} |`;
    const asks = a.askedHosts.map(safeHost).join(", ") || "-";
    return `| ${mdCell(n)} | ${mdCell(asks)} | ${mdCell(a.gateway.join("; ") || "-")} | ${mdCell(a.decoys.join(", ") || "-")} |`;
  });
  return ["| Arm | SandboxNetworkAccess asks (in order) | Gateway lines | Decoy hits |", "|---|---|---|---|", ...rows].join("\n") + "\n";
}

/** The one Markdown draft (the script writes it as both addendum.md and issue-comment.md). */
export function renderDrafts(v: Verdict, m: RecordMeta): string {
  const vb = v.baseline?.step0 ?? {};
  const vc = v.candidate?.step0 ?? {};
  const versions = [
    "| | Baseline | Candidate |",
    "|---|---|---|",
    `| Requested | ${mdCell(MEASURED_BASELINE.version)} | ${mdCell(m.requested)} |`,
    `| Observed SDK | ${mdCell(vb.sdkVersion ?? "-")} | ${mdCell(vc.sdkVersion ?? "-")} |`,
    `| Observed CLI | ${mdCell(vb.cliVersion ?? "-")} | ${mdCell(vc.cliVersion ?? "-")} |`,
    `| Reading | ${mdCell(v.baseline?.reading ?? "-")} | ${mdCell(v.candidate?.reading ?? "-")} |`,
  ].join("\n");
  const envRows = m.env
    ? Object.entries(m.env)
        .map(([k, val]) => `- ${k.replace(/[^A-Za-z0-9_]/g, "")}: ${mdCell(val)}`)
        .join("\n")
    : "";
  return [
    "**Command.**",
    "",
    "```text",
    m.command,
    "```",
    "",
    `**Result.** ${mdCell(remeasureLine(v))}`,
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
}

// ---- CLI ---------------------------------------------------------------------------------------------------------------

function arg(argv: string[], name: string): string | undefined {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
}

export async function main(argv: string[], write: (s: string) => void = (s) => process.stdout.write(s)): Promise<number> {
  // The script reads the pinned baseline (version, integrity), the arm list and the sentinel from here: one copy each.
  if (argv[0] === "baseline-json") {
    write(`${JSON.stringify({ ...MEASURED_BASELINE, arms: ARMS, sentinel: SENTINEL })}\n`);
    return 0;
  }
  // The verdict-to-action table, one `<VERDICT>\t<next>` line per verdict in precedence order (the script's --help).
  if (argv[0] === "table") {
    write(`${VERDICTS.map((v) => `${v}\t${NEXT[v]}`).join("\n")}\n`);
    return 0;
  }
  const need = [
    "--baseline", "--candidate", "--baseline-sdk", "--baseline-cli", "--candidate-sdk", "--candidate-cli",
    "--baseline-entry", "--candidate-entry", "--requested", "--command",
  ];
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
  const side = (s: "baseline" | "candidate"): RunInput => ({
    stdout: read(arg(argv, `--${s}`)!),
    expectedSdk: arg(argv, `--${s}-sdk`)!,
    expectedCli: arg(argv, `--${s}-cli`)!,
    expectedEntry: arg(argv, `--${s}-entry`)!,
  });
  const v = classify({ baseline: side("baseline"), candidate: side("candidate") });
  let env: Rec | undefined;
  const envPath = arg(argv, "--env");
  if (envPath) {
    try {
      env = JSON.parse(read(envPath));
    } catch {
      env = undefined;
    }
  }
  const meta: RecordMeta = { requested: arg(argv, "--requested")!, command: arg(argv, "--command")!, env };
  const roots = { scratch: arg(argv, "--scratch-root"), app: arg(argv, "--app-root") };
  const out = redact(
    JSON.stringify({ requested: meta.requested, command: meta.command, env: meta.env ?? null, ...v }, null, 2),
    roots,
  );
  const draft = redact(renderDrafts(v, meta), roots);
  const line = redact(remeasureLine(v), roots);
  const benign = typeof env?.os === "string" ? [env.os] : [];
  const leak = [out, draft, line].map((t) => identityLeak(t, currentIdentity(), benign)).find((x) => x !== null);
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
    for (const f of ["addendum.md", "issue-comment.md"]) writeFileSync(join(md, f), draft);
  }
  write(`${redact(lines.join("\n"), roots)}\n${line}\n`);
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
