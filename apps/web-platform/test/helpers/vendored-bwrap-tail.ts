// Reads the vendored bwrap BUILDER's literal `.push(...)` calls straight out of the Claude Code
// platform binaries (`@anthropic-ai/claude-agent-sdk-linux-x64`, `@anthropic-ai/claude-code-linux-x64`),
// creds-free, so a fixture of the SDK's setup argv tail can be pinned to the builder that emits it
// (#10065 Guard 2). The binaries are pinned by package-lock.json integrity; nothing here reads git
// state or the sdk-bump ack trailer.
//
// Shape of the code being read (minified JS inside a ~250 MB Bun single-file executable):
//
//   X.push("--dev","/dev"),X.push("--unshare-pid"); ... ;
//   if(X.push("--unshare-user",...CAPS({...})),!weaker)X.push("--proc","/proc");
//   else X.push("--bind","/proc","/proc"); ... ; X.push("--",SHELL,"-c") ...
//
// `extractBuilderTail` anchors on the literal `.push("--dev","/dev"),`, takes a window of at most
// 4 KiB, and collects the consecutive string-literal arguments of every `.push(` call in it up to
// the `.push("--",` terminator. A spread / identifier argument ends a call's literal run and marks it
// `opaque` (the `...CAPS(...)` segment is covered by the cap-segment rules and the live-spawn row).
// No regex is applied to anything unbounded: the 243 MB file is only ever scanned with
// `Buffer.indexOf` over bounded chunks, and the parser sees a window of at most 4096 bytes.

import { closeSync, fstatSync, openSync, readFileSync, readSync } from "node:fs";
import { join } from "node:path";

export const TAIL_ANCHOR = '.push("--dev","/dev"),';
export const TAIL_WINDOW_BYTES = 4096;
const HOOK_LOOKBEHIND_BYTES = 2048;
const DEFAULT_CHUNK_BYTES = 8 * 1024 * 1024;
const DEFAULT_OVERLAP_BYTES = 64 * 1024;

export interface ByteSource {
  readonly size: number;
  /** Reads up to `length` bytes at `offset` (clipped at EOF). */
  read(offset: number, length: number): Buffer;
}

export function bufferSource(buf: Buffer): ByteSource {
  return {
    size: buf.length,
    read: (offset, length) => buf.subarray(Math.max(0, offset), Math.max(0, offset) + length),
  };
}

export function fileSource(path: string): { source: ByteSource; close: () => void } {
  const fd = openSync(path, "r");
  const size = fstatSync(fd).size;
  return {
    source: {
      size,
      read(offset, length) {
        const start = Math.max(0, offset);
        const len = Math.max(0, Math.min(length, size - start));
        const out = Buffer.allocUnsafe(len);
        let got = 0;
        while (got < len) {
          const n = readSync(fd, out, got, len - got, start + got);
          if (n === 0) break;
          got += n;
        }
        return got === len ? out : out.subarray(0, got);
      },
    },
    close: () => closeSync(fd),
  };
}

/** Skip the real-binary rows only off linux-x64 with CI unset; under CI an absent binary must FAIL. */
export function shouldSkipRealBinaryRows(
  platform: string,
  arch: string,
  ci: string | undefined,
): boolean {
  return !(platform === "linux" && arch === "x64") && !ci;
}

export interface VendoredBinary {
  path: string;
  size: number;
  version: string;
}

export function resolveVendoredBinary(
  pkg: "claude-agent-sdk" | "claude-code",
  nodeModulesDir: string,
): VendoredBinary {
  const dir = join(nodeModulesDir, "@anthropic-ai", `${pkg}-linux-x64`);
  const path = join(dir, "claude");
  // One open, no existsSync: a check-then-open pair is a file-system race (CodeQL js/file-system-race).
  let fd: number;
  try {
    fd = openSync(path, "r");
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
    throw new Error(
      `BINARY_MISSING: @anthropic-ai/${pkg}-linux-x64 has no claude binary at ${path}. ` +
        "Run `npm ci` in apps/web-platform (the platform package is an optionalDependency); " +
        "a missing binary is a failure, never a skip, on linux-x64 and under CI.",
    );
  }
  let size: number;
  try {
    size = fstatSync(fd).size;
  } finally {
    closeSync(fd);
  }
  let version = "unknown";
  try {
    const pj = JSON.parse(readFileSync(join(dir, "package.json"), "utf8")) as { version?: string };
    if (typeof pj.version === "string") version = pj.version;
  } catch {
    /* version is only a label in failure messages */
  }
  return { path, size, version };
}

// ---------------------------------------------------------------------------------------------
// Chunked needle scan (64 KiB overlap, never a whole-file read).

export interface ScanOptions {
  chunkSize?: number;
  overlap?: number;
}

/** One pass; every match is counted by the chunk its START falls in, so overlap never double counts. */
export function scanNeedles(
  src: ByteSource,
  needles: Record<string, Buffer>,
  opts: ScanOptions = {},
): Record<string, number[]> {
  const chunk = Math.max(1, opts.chunkSize ?? DEFAULT_CHUNK_BYTES);
  const overlap = opts.overlap ?? DEFAULT_OVERLAP_BYTES;
  const longest = Math.max(...Object.values(needles).map((n) => n.length));
  if (overlap < longest) {
    throw new Error(`SCAN_OVERLAP: overlap ${overlap} is shorter than the longest needle (${longest})`);
  }
  const out: Record<string, number[]> = {};
  for (const k of Object.keys(needles)) out[k] = [];
  for (let pos = 0; pos < src.size; pos += chunk) {
    const buf = src.read(pos, chunk + overlap);
    for (const [name, needle] of Object.entries(needles)) {
      let from = 0;
      for (;;) {
        const i = buf.indexOf(needle, from);
        if (i < 0 || i >= chunk) break;
        out[name].push(pos + i);
        from = i + 1;
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Builder tail extraction.

export interface TailCall {
  args: string[];
  /** True when a non-literal argument (a spread, an identifier) followed the literal run. */
  opaque: boolean;
}
export interface BuilderTail {
  offset: number;
  calls: TailCall[];
  /** True when the `.push("--",` terminator was found inside the window. */
  terminated: boolean;
}

/** `[--dev /dev] [--unshare-pid] [--unshare-user ...caps] then the two exclusive proc branches. */
export const EXPECTED_TAIL_CALLS: readonly TailCall[] = [
  { args: ["--dev", "/dev"], opaque: false },
  { args: ["--unshare-pid"], opaque: false },
  { args: ["--unshare-user"], opaque: true },
  { args: ["--proc", "/proc"], opaque: false },
  { args: ["--bind", "/proc", "/proc"], opaque: false },
];

export const CAP_SEGMENT = "<CAP_SEGMENT>";

function parseCalls(win: string): { calls: TailCall[]; terminated: boolean } {
  const calls: TailCall[] = [];
  let i = 0;
  for (;;) {
    const p = win.indexOf(".push(", i);
    if (p < 0) return { calls, terminated: false };
    let j = p + ".push(".length;
    const args: string[] = [];
    let opaque = false;
    for (;;) {
      if (win[j] !== '"') {
        opaque = j < win.length && win[j] !== ")";
        break;
      }
      let k = j + 1;
      while (k < win.length && win[k] !== '"') k += win[k] === "\\" ? 2 : 1;
      if (k >= win.length) {
        opaque = true; // literal cut off by the window end
        j = win.length;
        break;
      }
      args.push(win.slice(j + 1, k));
      j = k + 1;
      if (win[j] === ",") {
        j += 1;
        continue;
      }
      opaque = j < win.length && win[j] !== ")";
      break;
    }
    i = Math.max(j, p + 1);
    if (args[0] === "--") return { calls, terminated: true };
    calls.push({ args, opaque });
  }
}

/** The one supported way to refresh the committed canary fixture, and what to do without credentials. */
export const FIXTURE_REGEN_HINT =
  "To refresh infra/sandbox-canary-argv.json run, from the repo root with docker and ANTHROPIC_API_KEY set, " +
  "`SANDBOX_CANARY_MODE=capture bash apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` (it captures INSIDE the " +
  "deploy base image; a bare `sandbox-canary.mjs --capture` on a dev host bakes in host-conditional tokens and is the wrong " +
  "fixture for production). The SDK-bump CI gate runs the same script. Without credentials, stop and report this failure: " +
  "never hand-edit the fixture and never re-pin to turn the check green. After a capture, check that the verdict is not " +
  "canary_infra_error and that the fixture file actually changed (the capture is a paid Haiku call).";

export function extractBuilderTailFrom(src: ByteSource): BuilderTail {
  const hits = scanNeedles(src, { anchor: Buffer.from(TAIL_ANCHOR, "latin1") }).anchor;
  if (hits.length !== 1) {
    throw new Error(
      `TAIL_ANCHOR found ${hits.length} (want exactly 1 occurrence of ${TAIL_ANCHOR}). The vendored ` +
        "builder changed shape (refactor or minifier change): inspect the new builder in the platform " +
        "binary (`/usr/bin/grep -abo -F '<needle>' apps/web-platform/node_modules/@anthropic-ai/{claude-agent-sdk,claude-code}-linux-x64/claude` prints each offset), " +
        "decide whether the new shape still ends in the /proc mask, and only then update the anchor and EXPECTED_TAIL_CALLS in " +
        "test/helpers/vendored-bwrap-tail.ts (a re-pin is a security decision, not a way to turn this green).",
    );
  }
  const offset = hits[0];
  const win = src.read(offset, TAIL_WINDOW_BYTES).toString("latin1");
  return { offset, ...parseCalls(win) };
}

export function extractBuilderTail(buf: Buffer): BuilderTail {
  return extractBuilderTailFrom(bufferSource(buf));
}

export function assertBuilderTail(tail: BuilderTail, label = "binary"): void {
  const same =
    tail.terminated &&
    tail.calls.length === EXPECTED_TAIL_CALLS.length &&
    tail.calls.every(
      (c, i) =>
        c.opaque === EXPECTED_TAIL_CALLS[i].opaque &&
        c.args.length === EXPECTED_TAIL_CALLS[i].args.length &&
        c.args.every((a, k) => a === EXPECTED_TAIL_CALLS[i].args[k]),
    );
  if (same) return;
  throw new Error(
    `TAIL_LITERALS [${label}]: the builder's literal push sequence from ${TAIL_ANCHOR} to .push("--", ` +
      `changed (terminator found within ${TAIL_WINDOW_BYTES} bytes: ${tail.terminated}). ` +
      `want ${JSON.stringify(EXPECTED_TAIL_CALLS)} got ${JSON.stringify(tail.calls)}. ` +
      "Inspect the new builder first (an added mount after the proc branches can re-cover or re-expose /proc), " +
      "then update EXPECTED_TAIL_CALLS ONLY if the new sequence still ends in the mask (a re-pin is a security decision, " +
      "not a way to turn this green). " + FIXTURE_REGEN_HINT,
  );
}

/** Flat literal tokens of the tail with the exclusive proc alternation resolved to `branch`. */
export function builderTailTokens(tail: BuilderTail, branch: "proc" | "bind"): string[] {
  assertBuilderTail(tail, "tokens");
  const out: string[] = [];
  const isProcBranch = (c: { args: string[] }) => c.args[0] === "--proc";
  const isBindBranch = (c: { args: string[] }) => c.args[0] === "--bind" && c.args[1] === "/proc";
  const branchStart = tail.calls.findIndex((c) => isProcBranch(c) || isBindBranch(c));
  tail.calls.forEach((c, i) => {
    if (i >= branchStart && branchStart >= 0 && (isProcBranch(c) || isBindBranch(c))) {
      if (branch === "proc" ? !isProcBranch(c) : !isBindBranch(c)) return;
    }
    out.push(...c.args);
    if (c.opaque) out.push(CAP_SEGMENT);
  });
  return out;
}

// ---------------------------------------------------------------------------------------------
// Cap segment + spawn-tail normalization.

/**
 * Collapses the cap segment (the run of `--cap-drop` / `--cap-add` pairs right after `--unshare-user`)
 * to one marker token, AFTER checking it. The SDK returns `--cap-drop ALL` only, or adds
 * `--cap-add CAP_SETFCAP` when root with setfcap, so the two recorded shapes must compare equal; a
 * normalization that ignored the segment would let `--cap-add CAP_SYS_ADMIN` through, so anything
 * that is not exactly {one `--cap-drop ALL`, zero or more `--cap-add CAP_SETFCAP`} is `CAP_BARRIER`.
 */
export function normalizeSpawnTail(tokens: readonly string[]): string[] {
  if (tokens.includes(CAP_SEGMENT)) return [...tokens];
  const u = tokens.indexOf("--unshare-user");
  if (u < 0) {
    throw new Error(`CAP_BARRIER: no --unshare-user in the tail, so the cap segment cannot be located: ${tokens.join(" ")}`);
  }
  let end = u + 1;
  const drops: string[] = [];
  const adds: string[] = [];
  while (end < tokens.length && (tokens[end] === "--cap-drop" || tokens[end] === "--cap-add")) {
    (tokens[end] === "--cap-drop" ? drops : adds).push(tokens[end + 1] ?? "<missing>");
    end += 2;
  }
  const stray = tokens.some((t, i) => (t === "--cap-drop" || t === "--cap-add") && (i <= u || i >= end));
  const bad =
    stray ||
    drops.length !== 1 ||
    drops[0] !== "ALL" ||
    adds.some((a) => a !== "CAP_SETFCAP");
  if (bad) {
    throw new Error(
      `CAP_BARRIER: the cap segment must be exactly one --cap-drop ALL plus only --cap-add CAP_SETFCAP, directly ` +
        `after --unshare-user (the vendor's --cap-drop ALL is what keeps a sandboxed process from reaching the ` +
        `container's procfs beneath the /proc mask). got drops=${JSON.stringify(drops)} adds=${JSON.stringify(adds)} ` +
        `stray=${stray} in: ${tokens.join(" ")}`,
    );
  }
  return [...tokens.slice(0, u + 1), CAP_SEGMENT, ...tokens.slice(end)];
}

/** The committed fixture's tokens from its LAST `--dev` (the vendor tail), as captured. */
export function readFixtureTail(fixturePath: string): string[] {
  const j = JSON.parse(readFileSync(fixturePath, "utf8")) as { bwrapSetupArgv?: unknown };
  const argv = j.bwrapSetupArgv;
  if (!Array.isArray(argv) || !argv.every((t) => typeof t === "string")) {
    throw new Error(`FIXTURE_TAIL: ${fixturePath} has no string[] bwrapSetupArgv`);
  }
  const lastDev = argv.lastIndexOf("--dev");
  if (lastDev < 0) throw new Error(`FIXTURE_TAIL: no --dev in ${fixturePath}`);
  return argv.slice(lastDev);
}

/** Tokens from the last `--dev` up to (excluding) the first `--` boundary of a recorded spawn. */
export function liveTailOf(callTokens: readonly string[]): string[] | null {
  const boundary = callTokens.indexOf("--");
  const setup = boundary >= 0 ? callTokens.slice(0, boundary) : [...callTokens];
  const lastDev = setup.lastIndexOf("--dev");
  return lastDev < 0 ? null : setup.slice(lastDev);
}

export function assertTailMatchesFixture(
  actual: readonly string[],
  fixtureTail: readonly string[],
  label: string,
): void {
  const a = normalizeSpawnTail(actual);
  const f = normalizeSpawnTail(fixtureTail);
  if (a.length === f.length && a.every((t, i) => t === f[i])) return;
  throw new Error(
    `TAIL_DRIFT [${label}]: the argv tail differs from the committed fixture infra/sandbox-canary-argv.json ` +
      `(tokens from its last --dev, cap segment normalized, proc alternation resolved). ` +
      `fixture: ${f.join(" ")} | actual: ${a.join(" ")}. Inspect the new vendored builder first. ` + FIXTURE_REGEN_HINT,
  );
}

// ---------------------------------------------------------------------------------------------
// Literal census (procfs-mount sites, namespace/root binds, cap flags, hook-sandbox anchor).

export interface LiteralPins {
  /** `"--proc","/proc"` literals (every builder). */
  procSites: number;
  /** Of those, sites with the `/run/claude-hook` literal within 2 KiB before (the hook sandbox). */
  hookProcSites: number;
  /** `"--bind","/proc","/proc"` literals. */
  bindProcSites: number;
  /** `"--unshare-pid"` literals. */
  unsharePid: number;
  /** `"--ro-bind","/","/"` literals. */
  rootBind: number;
  /** `"--cap-drop","ALL"` literals, and every `"--cap-drop"` literal. */
  capDropAll: number;
  capDropTotal: number;
  /** `"--cap-add","CAP_SETFCAP"` literals, and every `"--cap-add"` literal. */
  capAddSetfcap: number;
  capAddTotal: number;
  /** `/run/claude-hook` literals. */
  hookAnchors: number;
}

export interface LiteralCensus {
  counts: LiteralPins;
  offsets: Record<string, number[]>;
}

const CENSUS_NEEDLES = {
  procSites: '"--proc","/proc"',
  bindProcSites: '"--bind","/proc","/proc"',
  unsharePid: '"--unshare-pid"',
  rootBind: '"--ro-bind","/","/"',
  capDropAll: '"--cap-drop","ALL"',
  capDropTotal: '"--cap-drop"',
  capAddSetfcap: '"--cap-add","CAP_SETFCAP"',
  capAddTotal: '"--cap-add"',
  hookAnchors: "/run/claude-hook",
} as const;

export function scanLiterals(src: ByteSource, opts: ScanOptions = {}): LiteralCensus {
  const needles: Record<string, Buffer> = {};
  for (const [k, v] of Object.entries(CENSUS_NEEDLES)) needles[k] = Buffer.from(v, "latin1");
  const offsets = scanNeedles(src, needles, opts);
  const hook = Buffer.from(CENSUS_NEEDLES.hookAnchors, "latin1");
  let hookProcSites = 0;
  for (const off of offsets.procSites) {
    const start = Math.max(0, off - HOOK_LOOKBEHIND_BYTES);
    if (src.read(start, off - start).includes(hook)) hookProcSites += 1;
  }
  const c = (k: keyof typeof CENSUS_NEEDLES) => offsets[k].length;
  return {
    counts: {
      procSites: c("procSites"),
      hookProcSites,
      bindProcSites: c("bindProcSites"),
      unsharePid: c("unsharePid"),
      rootBind: c("rootBind"),
      capDropAll: c("capDropAll"),
      capDropTotal: c("capDropTotal"),
      capAddSetfcap: c("capAddSetfcap"),
      capAddTotal: c("capAddTotal"),
      hookAnchors: c("hookAnchors"),
    },
    offsets,
  };
}

/** Throws one error listing every deviation, each line starting with its failure code. */
export function assertLiteralCensus(
  census: LiteralCensus,
  pins: LiteralPins,
  label: string,
  context: string,
): void {
  const g = census.counts;
  const lines: string[] = [];
  const check = (code: string, what: keyof LiteralPins, desc: string) => {
    if (g[what] !== pins[what]) lines.push(`${code} want ${pins[what]} got ${g[what]} (${desc})`);
  };
  check("PROC_SITE_COUNT", "procSites", '"--proc","/proc" literals');
  check("PROC_SITE_COUNT", "hookProcSites", '"--proc","/proc" literals inside the /run/claude-hook sandbox function');
  check("PROC_SITE_COUNT", "bindProcSites", '"--bind","/proc","/proc" literals');
  check("NS_SITE_COUNT", "unsharePid", '"--unshare-pid" literals');
  check("ROOT_SITE_COUNT", "rootBind", '"--ro-bind","/","/" literals');
  check("HOOK_SITE_COUNT", "hookAnchors", "/run/claude-hook literals");
  check("CAP_BARRIER", "capDropAll", '"--cap-drop","ALL" literals (inferred to be the barrier to the container procfs on an unelevated bwrap; ADR-075 addendum 2026-10-12)');
  check("CAP_BARRIER", "capDropTotal", 'every "--cap-drop" literal (a different drop value is a different barrier)');
  check("CAP_BARRIER", "capAddSetfcap", '"--cap-add","CAP_SETFCAP" literals (the only permitted --cap-add)');
  check("CAP_BARRIER", "capAddTotal", 'every "--cap-add" literal (any other capability is CAP_BARRIER)');
  if (lines.length === 0) return;
  const siteProblem = lines.some((l) => /^(PROC_SITE_COUNT|NS_SITE_COUNT|ROOT_SITE_COUNT|HOOK_SITE_COUNT)\b/.test(l));
  const capProblem = lines.some((l) => l.startsWith("CAP_BARRIER"));
  const steps =
    (siteProblem
      ? " A site count moved in the vendored builder: (1) inspect the new site in the platform binary " +
        "(`/usr/bin/grep -abo -F '<needle>' apps/web-platform/node_modules/@anthropic-ai/{claude-agent-sdk,claude-code}-linux-x64/claude` prints each offset) and " +
        "decide whether tenant input can reach it and whether the bwrap shim drops its --proc/--bind /proc, " +
        "(2) only then update PINS in apps/web-platform/test/sandbox-vendored-argv-tail.test.ts with the re-measured " +
        "counts and the measured version; a re-pin is a security decision, not a way to turn this green."
      : "") +
    (capProblem
      ? " The cap segment moved: inspect it in the platform binary, then update PINS only if the barrier is unchanged " +
        "(exactly one --cap-drop ALL; only CAP_SETFCAP may ever be added)."
      : "");
  throw new Error(`[${label}] (${context}) ${lines.join("; ")}.${steps}`);
}

// ---------------------------------------------------------------------------------------------
// #10445 — helper-selection condition. The SDK wraps every Bash command in an `apply-seccomp`
// helper UNLESS `sandbox.network.allowAllUnixSockets` is set; our config sets it so the helper
// (whose first call, unshare(CLONE_NEWUSER), our shim filter denies) is never engaged. These
// literals are the three log lines of that selection plus the settings->builder mapping; if a
// bump removes or reshapes any of them the "knob skips the helper" premise is unproven and the
// fix must be re-measured through the real SDK path (infra/sandbox-masked-proc-docker.test.sh
// wrapped-command arm).

export const HELPER_SELECTION_NEEDLES: Readonly<Record<string, string>> = Object.freeze({
  skipLine: "Skipping seccomp filter - allowAllUnixSockets is enabled",
  applyLine: "Applying seccomp filter for Unix socket blocking",
  missingLine: "apply-seccomp binary not available - unix socket blocking disabled",
  settingsMapping: "sandbox?.network?.allowAllUnixSockets",
});

export interface HelperSelectionPins {
  skipLine: number;
  applyLine: number;
  missingLine: number;
  /** 0 for the CLI package, which never reads the programmatic `sandbox` option. */
  settingsMapping: number;
}

export function scanHelperSelection(src: ByteSource): Record<keyof HelperSelectionPins, number> {
  const needles: Record<string, Buffer> = {};
  for (const [k, v] of Object.entries(HELPER_SELECTION_NEEDLES)) needles[k] = Buffer.from(v);
  const hits = scanNeedles(src, needles);
  return {
    skipLine: hits.skipLine.length,
    applyLine: hits.applyLine.length,
    missingLine: hits.missingLine.length,
    settingsMapping: hits.settingsMapping.length,
  };
}

export function assertHelperSelection(
  counts: Record<keyof HelperSelectionPins, number>,
  pins: HelperSelectionPins,
  label: string,
): void {
  const lines: string[] = [];
  for (const k of Object.keys(pins) as (keyof HelperSelectionPins)[]) {
    if (counts[k] !== pins[k]) {
      lines.push(`HELPER_SELECTION ${k} want ${pins[k]} got ${counts[k]} (${JSON.stringify(HELPER_SELECTION_NEEDLES[k])})`);
    }
  }
  if (lines.length === 0) return;
  throw new Error(
    `[${label}] ${lines.join("; ")}. The vendored builder's unix-socket helper selection moved: re-prove that ` +
      "`network.allowAllUnixSockets: true` still skips the `apply-seccomp` wrapper through the real SDK path " +
      "(infra/sandbox-masked-proc-docker.test.sh wrapped-command arm) before updating the pins (#10445).",
  );
}

// ---------------------------------------------------------------------------------------------
// `apply-seccomp:` helper step strings (#10455 e, Guard 2).
//
// The SDK's command-side helper (the multicall embedded in the same `claude` binary) prints
// `apply-seccomp: <step>: <strerror>` for each failing step. The step literal sits in the binary's string
// pool as `apply-seccomp: <step>` followed by NUL. Measured on claude-agent-sdk 0.3.284 (and identical in
// claude-code 2.1.293): 17 distinct strings, one occurrence each. 16 are `<step>` literals that take a
// `: <strerror>` suffix; `observe sendmsg failed` is a fixed message with no errno.

export const HELPER_STEP_PREFIX = "apply-seccomp: ";
/** A step literal is short printable ASCII; the longest measured is ~110 bytes. Bounded read, no regex on the binary. */
const HELPER_STEP_READ_BYTES = 200;

/** Every distinct `apply-seccomp: ...` string in the source, prefix stripped, sorted. */
export function scanHelperStepStrings(src: ByteSource, opts: ScanOptions = {}): string[] {
  const hits = scanNeedles(src, { step: Buffer.from(HELPER_STEP_PREFIX, "latin1") }, opts).step;
  const found = new Set<string>();
  for (const at of hits) {
    const buf = src.read(at + HELPER_STEP_PREFIX.length, HELPER_STEP_READ_BYTES);
    let end = 0;
    while (end < buf.length && buf[end] >= 0x20 && buf[end] <= 0x7e) end += 1;
    if (end > 0) found.add(buf.subarray(0, end).toString("latin1"));
  }
  return [...found].sort();
}

export interface HelperStepPins {
  /** Steps the classifier allowlists (take a `: <strerror>` suffix). */
  classified: readonly string[];
  /** Strings the binary carries that are deliberately NOT classified (no errno suffix). */
  excluded: readonly string[];
  /** Floor on the number of distinct strings read: a scan that reads nothing must red, never pass. */
  minStrings: number;
}

/** Census: binary strings === classified ∪ excluded, both directions, with a floor. */
export function assertHelperStepCensus(found: readonly string[], pins: HelperStepPins, label: string): void {
  const known = new Set([...pins.classified, ...pins.excluded]);
  const seen = new Set(found);
  const problems: string[] = [];
  if (found.length < pins.minStrings) {
    problems.push(`HELPER_STEP_FLOOR want >= ${pins.minStrings} strings got ${found.length}`);
  }
  for (const s of pins.classified) {
    if (!seen.has(s)) problems.push(`HELPER_STEP_ABSENT allowlisted ${JSON.stringify(s)} is not in the binary`);
  }
  for (const s of found) {
    if (!known.has(s)) problems.push(`HELPER_STEP_NEW the binary carries ${JSON.stringify(s)}, neither classified nor excluded`);
  }
  if (problems.length === 0) return;
  throw new Error(
    `[${label}] ${problems.join("; ")}. The vendored apply-seccomp helper's step list moved: decide whether each new ` +
      "step is a pre-worker-fork step (can show the platform notice) or a post-fork one, then update HELPER_STEPS / " +
      "HELPER_STEPS_PRE_WORKER_FORK / HELPER_NON_STEP_LINES in server/sandbox-startup-classifier.ts (#10455 e).",
  );
}

// ---------------------------------------------------------------------------------------------
// Proxy-bridge structure (#10455 a).
//
// The AF_UNIX-deny seccomp variant is safe for NO-EGRESS sessions only because of how the builder lays out the per-command
// network: with a restricted network it `--unshare-net`s, binds the two bridge sockets, and wraps EVERY command in a shell
// that starts the `socat TCP-LISTEN:3128/1080 ... UNIX-CONNECT:<sock>` bridges BEFORE the user command (the bridges are
// what an egress session reaches its proxy through; under the variant they fail to open their AF_UNIX client and the
// no-egress session simply has no working proxy, which it must not have anyway). The source-form of both functions is
// embedded in the binary (minified names differ per release), so they are matched with name-agnostic regexes.
// Measured 2026-10-19 on claude-agent-sdk 0.3.284 and claude-code 2.1.293: one source-form occurrence each.

export const BRIDGE_WRAPPER_ANCHOR = "TCP-LISTEN:3128,fork,reuseaddr UNIX-CONNECT:${";
export const BRIDGE_NET_ANCHOR = '.push("--unshare-net"),';
const BRIDGE_WINDOW_BYTES = 1600;

export const BRIDGE_PINS = Object.freeze({ wrapperHits: 1, netHits: 1 });

// `[bridge-3128, bridge-1080, trap]` is built first, then the user command is appended AFTER it (`[...S, T]`).
const BRIDGE_WRAPPER_RE =
  /^TCP-LISTEN:3128,fork,reuseaddr UNIX-CONNECT:\$\{\w+\} >\/dev\/null 2>&1 &`,`\$\{\w+\} TCP-LISTEN:1080,fork,reuseaddr UNIX-CONNECT:\$\{\w+\} >\/dev\/null 2>&1 &`,"trap 'rc=\$\?; kill %1 %2 2>\/dev\/null; exit \$rc' EXIT"\];if\(\w+\)\{let \w+=\w+\+\w+\(\[\w+,"-c",\w+\]\),\w+=\[\.\.\.\w+,\w+\]\.join\(/;
// `--unshare-net` first, then (when both bridge sockets exist) the two bridge binds.
const BRIDGE_NET_RE =
  /^\.push\("--unshare-net"\),\w+&&\w+\)\{if\(!\w+\.existsSync\(\w+\)\)throw Error\(`Linux HTTP bridge socket does not exist[^`]*`\);if\(!\w+\.existsSync\(\w+\)\)throw Error\(`Linux SOCKS bridge socket does not exist[^`]*`\);if\(\w+\.push\("--bind",\w+,\w+\),\w+!==\w+\)\w+\.push\("--bind",\w+,\w+\);/;

export interface BridgeScan {
  wrapperHits: number;
  netHits: number;
  wrapperWindow: string;
  netWindow: string;
}

export function scanBridgeStructure(src: ByteSource): BridgeScan {
  const hits = scanNeedles(src, {
    wrapper: Buffer.from(BRIDGE_WRAPPER_ANCHOR, "latin1"),
    net: Buffer.from(BRIDGE_NET_ANCHOR, "latin1"),
  });
  const win = (offs: number[]): string => (offs.length === 1 ? src.read(offs[0], BRIDGE_WINDOW_BYTES).toString("latin1") : "");
  return {
    wrapperHits: hits.wrapper.length,
    netHits: hits.net.length,
    wrapperWindow: win(hits.wrapper),
    netWindow: win(hits.net),
  };
}

export function assertBridgeStructure(scan: BridgeScan, label: string): void {
  const problems: string[] = [];
  if (scan.wrapperHits !== BRIDGE_PINS.wrapperHits) {
    problems.push(`bridge wrapper anchor ${JSON.stringify(BRIDGE_WRAPPER_ANCHOR)} found ${scan.wrapperHits}, want ${BRIDGE_PINS.wrapperHits}`);
  } else if (!BRIDGE_WRAPPER_RE.test(scan.wrapperWindow)) {
    problems.push("BRIDGE_ORDER: the wrapper no longer builds [bridge 3128, bridge 1080, trap] and then appends the user command");
  }
  if (scan.netHits !== BRIDGE_PINS.netHits) {
    problems.push(`net anchor ${JSON.stringify(BRIDGE_NET_ANCHOR)} found ${scan.netHits}, want ${BRIDGE_PINS.netHits}`);
  } else if (!BRIDGE_NET_RE.test(scan.netWindow)) {
    problems.push("BRIDGE_NET: --unshare-net is no longer followed by the bridge-socket checks and the two bridge binds");
  }
  if (problems.length === 0) return;
  throw new Error(
    `[${label}] ${problems.join("; ")}. The unixdeny variant assumes the vendored builder starts the socat proxy bridges before ` +
      "the user command inside an unshared net namespace. Re-measure through the real SDK (test/sandbox-wrapped-command-runtime.test.ts, " +
      "the AF_UNIX-deny variant block) before updating the pins; a no-egress session's Bash must still start under the variant (ADR-075 addendum 2026-10-19).",
  );
}
