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

/**
 * `[--dev /dev] [--unshare-pid] [--unshare-user ...caps] then the two exclusive proc branches, then
 * `--unsetenv <var>` and the conditional `--disable-userns` (claude-code 2.1.311 / SDK 0.3.311). Both new calls sit AFTER
 * the proc branch: the mask is still the last mount the builder emits. `--unsetenv` takes an identifier (opaque);
 * `--disable-userns` is pushed only when no seccomp helper is in use AND nested user namespaces are not allowed AND the
 * bubblewrap it probes supports it (>= 0.8.0, not setuid). Measured 2026-11-04: ABSENT from the production-image capture and
 * from a live spawn through our shim, present in the builder, so a spawn may legitimately omit it (see `normalizeSpawnTail`).
 */
export const EXPECTED_TAIL_CALLS: readonly TailCall[] = [
  { args: ["--dev", "/dev"], opaque: false },
  { args: ["--unshare-pid"], opaque: false },
  { args: ["--unshare-user"], opaque: true },
  { args: ["--proc", "/proc"], opaque: false },
  { args: ["--bind", "/proc", "/proc"], opaque: false },
  { args: ["--unsetenv"], opaque: true },
  { args: ["--disable-userns"], opaque: false },
];

export const CAP_SEGMENT = "<CAP_SEGMENT>";
/** Stands for the env var name the builder passes to `--unsetenv` (an identifier in the binary, a literal in a spawn). */
export const UNSETENV_VAR = "<UNSETENV_VAR>";

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
    if (c.opaque) out.push(c.args[0] === "--unsetenv" ? UNSETENV_VAR : CAP_SEGMENT);
  });
  return out;
}

// ---------------------------------------------------------------------------------------------
// Cap segment + spawn-tail normalization.

/** Normalizes a spawn or builder tail for comparison: cap segment first, then the trailing flags. */
export function normalizeSpawnTail(tokens: readonly string[]): string[] {
  return normalizeTrailingFlags(normalizeCapSegment(tokens));
}

/**
 * The two flags the builder appends AFTER the proc branch. `--unsetenv <var>`: the name is an identifier in the binary
 * and a literal in a spawn, so both sides collapse to one marker AFTER checking it is a plausible env var name (an
 * `--unsetenv` with no operand, or one that swallowed a flag, is `UNSETENV_SHAPE`). `--disable-userns` is host-conditional
 * (see EXPECTED_TAIL_CALLS), so it is dropped from BOTH sides before comparison; its presence and position in the builder
 * are pinned by `EXPECTED_TAIL_CALLS`. Dropping it hides a MOUNT from nothing (whatever follows it is still compared), but it
 * does hide the flag itself: the builder emits it only when no seccomp helper is used, enableWeakerNestedSandbox is off and
 * bwrap lists it, which our production config never reaches, and on the production bwrap 0.8.0 it is the flag recorded as
 * breaking. The production-config live spawn therefore asserts its ABSENCE separately (sandbox-proc-mask-runtime.test.ts).
 */
function normalizeTrailingFlags(tokens: readonly string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < tokens.length; i += 1) {
    const t = tokens[i];
    if (t === "--disable-userns") continue;
    if (t === "--unsetenv") {
      const v = tokens[i + 1];
      if (v !== UNSETENV_VAR && !(typeof v === "string" && /^[A-Za-z_][A-Za-z0-9_]*$/.test(v))) {
        throw new Error(`UNSETENV_SHAPE: --unsetenv must be followed by one environment variable name, got ${JSON.stringify(v)} in: ${tokens.join(" ")}`);
      }
      out.push(t, UNSETENV_VAR);
      i += 1;
      continue;
    }
    out.push(t);
  }
  return out;
}

/**
 * Collapses the cap segment (the run of `--cap-drop` / `--cap-add` pairs right after `--unshare-user`)
 * to one marker token, AFTER checking it. The SDK returns `--cap-drop ALL` only, or adds
 * `--cap-add CAP_SETFCAP` when root with setfcap, so the two recorded shapes must compare equal; a
 * normalization that ignored the segment would let `--cap-add CAP_SYS_ADMIN` through, so anything
 * that is not exactly {one `--cap-drop ALL`, zero or more `--cap-add CAP_SETFCAP`} is `CAP_BARRIER`.
 */
function normalizeCapSegment(tokens: readonly string[]): string[] {
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
});

/**
 * The settings -> builder mapping. The pre-0.3.311 optional-chain source form (`sandbox?.network?.allowAllUnixSockets`)
 * is gone from the bundle: the knob is now read through a settings resolver that can also drop it under a managed policy
 * (`network.allowAllUnixSockets` in the policy-controlled key list). A minified identifier or an optional chain is NOT a stable
 * anchor, so these are content anchors only: the property key as written in the settings schema / config literals, and
 * the dotted setting path the managed-policy key list names. DRIFT TRIPWIRE ONLY, never the proof: that
 * `network.allowAllUnixSockets: true` still skips the `apply-seccomp` wrapper under OUR config is shown by the
 * wrapped-command arm (test/sandbox-wrapped-command-runtime.test.ts and infra/sandbox-masked-proc-docker.test.sh), which
 * has its own negative control (knob off, helper present).
 */
export const SETTINGS_MAPPING_NEEDLES: Readonly<Record<string, string>> = Object.freeze({
  propertyKey: "allowAllUnixSockets:",
  settingPath: "network.allowAllUnixSockets",
});

export interface HelperSelectionPins {
  skipLine: number;
  applyLine: number;
  missingLine: number;
}

export function scanHelperSelection(src: ByteSource): Record<keyof HelperSelectionPins, number> & { settingsMapping: Record<string, number> } {
  const needles: Record<string, Buffer> = {};
  for (const [k, v] of Object.entries(HELPER_SELECTION_NEEDLES)) needles[k] = Buffer.from(v);
  for (const [k, v] of Object.entries(SETTINGS_MAPPING_NEEDLES)) needles[`mapping:${k}`] = Buffer.from(v);
  const hits = scanNeedles(src, needles);
  const settingsMapping: Record<string, number> = {};
  for (const k of Object.keys(SETTINGS_MAPPING_NEEDLES)) settingsMapping[k] = hits[`mapping:${k}`].length;
  return {
    skipLine: hits.skipLine.length,
    applyLine: hits.applyLine.length,
    missingLine: hits.missingLine.length,
    settingsMapping,
  };
}

export function assertHelperSelection(
  counts: Record<keyof HelperSelectionPins, number> & { settingsMapping: Record<string, number> },
  pins: HelperSelectionPins,
  label: string,
): void {
  const lines: string[] = [];
  for (const k of Object.keys(pins) as (keyof HelperSelectionPins)[]) {
    if (counts[k] !== pins[k]) {
      lines.push(`HELPER_SELECTION ${k} want ${pins[k]} got ${counts[k]} (${JSON.stringify(HELPER_SELECTION_NEEDLES[k])})`);
    }
  }
  // At least one hit per mapping anchor (a tripwire, not a census: the key also appears in the settings schema, destructures and the managed-policy list, so its count moves with unrelated edits; measured 12 and 4 hits at 2.1.311).
  const mappingKeys = Object.keys(SETTINGS_MAPPING_NEEDLES);
  if (mappingKeys.length === 0) lines.push("HELPER_SELECTION settingsMapping has no anchors (a tripwire over zero needles cannot fire)");
  for (const k of mappingKeys) {
    const n = counts.settingsMapping[k] ?? 0;
    if (n < 1) lines.push(`HELPER_SELECTION settingsMapping.${k} want >= 1 got ${n} (${JSON.stringify(SETTINGS_MAPPING_NEEDLES[k])})`);
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
// pool as `apply-seccomp: <step>` followed by NUL. Measured on claude-agent-sdk 0.3.311 (the same binary as
// claude-code 2.1.311): 21 distinct strings, one occurrence each. 19 are `<step>` literals that take a
// `: <strerror>` suffix; `observe sendmsg failed` and the `user.max_user_namespaces` warning are fixed messages with no
// errno suffix. (0.3.284 / 2.1.293 carried 17: 16 steps and `observe sendmsg failed`.)

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
/** Helper strings deliberately NOT classified (a fixed message with no errno suffix). Test-only: the census needs
 *  it to tell "known and excluded" from "new in the binary"; production never reads it. */
export const HELPER_NON_STEP_LINES: readonly string[] = [
  "observe sendmsg failed",
  // Added by claude-code 2.1.311 / SDK 0.3.311: a non-fatal warning (the seccomp filter alone still blocks namespace creation),
  // printed by the init before the tenant command, with a `(%s)` errno slot in the middle and NO `: <errno>` suffix, so the
  // classifier's exact-step allowlist does not contain it, so `^apply-seccomp: <step>: Operation not permitted$` never classifies it.
  "could not set user.max_user_namespaces (%s); the seccomp filter alone keeps the command from making namespaces",
];

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
      "step runs before the tenant command (can show the platform notice) or after it, then update HELPER_STEPS / " +
      "HELPER_STEPS_PRE_COMMAND / HELPER_STEPS_POST_COMMAND in server/sandbox-startup-classifier.ts and " +
      "HELPER_NON_STEP_LINES in test/helpers/vendored-bwrap-tail.ts (#10455 e).",
  );
}

// ---------------------------------------------------------------------------------------------
// Proxy-bridge structure (#10455 a).
//
// The AF_UNIX-deny seccomp variant is safe for NO-EGRESS sessions only because of how the builder lays out the per-command
// network: with a restricted network it `--unshare-net`s, binds the two bridge sockets, and wraps EVERY command in a shell
// that starts the `socat TCP6-LISTEN:3128/1080 ... UNIX-CONNECT:<sock>` bridges BEFORE the user command (the bridges are
// what an egress session reaches its proxy through; under the variant they fail to open their AF_UNIX client and the
// no-egress session simply has no working proxy, which it must not have anyway). The source-form of both functions is
// embedded in the binary (minified names differ per release), so they are matched with name-agnostic regexes.
// Measured 2026-11-04 on claude-agent-sdk 0.3.311 and claude-code 2.1.311 (one byte-identical binary): one source-form occurrence.
// (0.3.284 / 2.1.293 anchored on `TCP-LISTEN:3128,fork,reuseaddr UNIX-CONNECT:${`, which the IPv6-first rewrite removed.)

export const BRIDGE_WRAPPER_ANCHOR = "TCP6-LISTEN:${";
export const BRIDGE_NET_ANCHOR = '.push("--unshare-net"),';
const BRIDGE_WINDOW_BYTES = 1600;

export const BRIDGE_PINS = Object.freeze({ wrapperHits: 1, netHits: 1 });

// `[bridge-3128, _srt_http=$!, bridge-1080, _srt_socks=$!, trap, ...watchdog]` is built first (the array `I`), then the user
// command is appended AFTER it (`[...I, D]`, or `[...I, eval <cmd>]` when there is no hook site). The bridge itself is now a
// `{ socat TCP6-LISTEN:<port>,ipv6only=0,... || exec socat TCP4-LISTEN:<port>,... ; } &` group. Identifiers are minified and
// change per release, so each is `[\w$]+`; every other byte is a content anchor.
const BRIDGE_WRAPPER_RE =
  /^TCP6-LISTEN:\$\{[\w$]+\},ipv6only=0,fork,reuseaddr,backlog=4096 UNIX-CONNECT:\$\{[\w$]+\} \|\| exec \$\{[\w$]+\} TCP4-LISTEN:\$\{[\w$]+\},fork,reuseaddr,backlog=4096 UNIX-CONNECT:\$\{[\w$]+\}; \} >\/dev\/null 2>&1 &`,[\w$]+=\[[\w$]+\(3128,[\w$]+\),"_srt_http=\$!",[\w$]+\(1080,[\w$]+\),"_srt_socks=\$!","trap 'rc=\$\?; kill %1 %2 2>\/dev\/null; exit \$rc' EXIT",\.\.\.[\w$]+\];if\([\w$]+\)\{let [\w$]+=[\w$]+\+[\w$]+\(\[[\w$]+,"-c",[\w$]+\]\),[\w$]+=\[\.\.\.[\w$]+,[\w$]+\]\.join\(/;
// The no-hook-site branch of the same function appends `eval <cmd>` after the same array.
const BRIDGE_ELSE_RE = /\}else\{let [\w$]+=\[\.\.\.[\w$]+,`eval \$\{[\w$]+\(\[[\w$]+\]\)\}`\]\.join\(/;
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
  } else if (!BRIDGE_WRAPPER_RE.test(scan.wrapperWindow) || !BRIDGE_ELSE_RE.test(scan.wrapperWindow)) {
    problems.push("BRIDGE_ORDER: the wrapper no longer builds [bridge 3128, bridge 1080, trap, ...] and then appends the user command (both branches)");
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

// ---------------------------------------------------------------------------------------------
// Embedded Bun runtime floor (CVE-2026-111497, Brotli decoder RCE, fixed in Bun 1.4.4; #12026).
//
// The `claude` platform binaries are Bun single-file executables: the vulnerable decoder is the one in the runtime the binary
// embeds, not in anything the package manager resolves, so a pin test proves the package version and NOT the runtime. This
// reads the runtime banner out of each binary. The version appears as `Bun v<maj>.<min>.<patch> (` (the banner carries a
// platform or commit in the parentheses); the string pool also carries bare `Bun v` fragments, which are NOT a version and are
// ignored, so a scan that finds only fragments reds "no version found" instead of passing. The minimum over ALL occurrences is
// compared (numeric, never lexicographic), so a later lower occurrence after a compliant first cannot hide.

export const BUN_FLOOR: readonly [number, number, number] = [1, 4, 4];
/** Both packages are examined by the same code path, so they can diverge again (they are one byte-identical binary at 0.3.311 / 2.1.311). */
export const BUN_FLOOR_PACKAGES: readonly ("claude-agent-sdk" | "claude-code")[] = ["claude-agent-sdk", "claude-code"];
const BUN_BANNER_PREFIX = "Bun v";
const BUN_BANNER_READ_BYTES = 40;
const BUN_BANNER_RE = /^(\d+)\.(\d+)\.(\d+) \(/;

/** Every distinct `Bun v<x.y.z> (` banner in the source, as `x.y.z`, sorted. Bare `Bun v` fragments are ignored. */
export function scanEmbeddedBunVersions(src: ByteSource, opts: ScanOptions = {}): string[] {
  const hits = scanNeedles(src, { bun: Buffer.from(BUN_BANNER_PREFIX, "latin1") }, opts).bun;
  const found = new Set<string>();
  for (const at of hits) {
    const text = src.read(at + BUN_BANNER_PREFIX.length, BUN_BANNER_READ_BYTES).toString("latin1");
    const m = BUN_BANNER_RE.exec(text);
    if (m) found.add(`${m[1]}.${m[2]}.${m[3]}`);
  }
  return [...found].sort(compareSemver);
}

/** Numeric `x.y.z` comparison. Throws on anything else, so a malformed value cannot compare as equal. */
export function compareSemver(a: string, b: string): number {
  const parse = (v: string): number[] => {
    if (!/^\d+\.\d+\.\d+$/.test(v)) throw new Error(`SEMVER_SHAPE: ${JSON.stringify(v)} is not x.y.z`);
    return v.split(".").map(Number);
  };
  const pa = parse(a);
  const pb = parse(b);
  for (let i = 0; i < 3; i += 1) if (pa[i] !== pb[i]) return pa[i] - pb[i];
  return 0;
}

export interface EmbeddedBunRow {
  pkg: string;
  /** For failure messages: package plus installed version. */
  label: string;
  versions: readonly string[];
}

/** Reads the embedded runtime version(s) of each named package's installed linux-x64 binary (bounded, chunked reads). */
export function scanInstalledEmbeddedBun(
  nodeModulesDir: string,
  pkgs: readonly ("claude-agent-sdk" | "claude-code")[] = BUN_FLOOR_PACKAGES,
): EmbeddedBunRow[] {
  return pkgs.map((pkg) => {
    const bin = resolveVendoredBinary(pkg, nodeModulesDir);
    const fs = fileSource(bin.path);
    try {
      return { pkg, label: `${pkg}@${bin.version}`, versions: scanEmbeddedBunVersions(fs.source) };
    } finally {
      fs.close();
    }
  });
}

/**
 * Throws unless EVERY required package was examined (a scan of zero or one binary cannot pass) and each one embeds a Bun
 * runtime at or above the floor, judged on the lowest version it carries.
 */
export function assertEmbeddedBunFloor(
  rows: readonly EmbeddedBunRow[],
  floor: readonly [number, number, number] = BUN_FLOOR,
  required: readonly string[] = BUN_FLOOR_PACKAGES,
): void {
  const floorStr = floor.join(".");
  const problems: string[] = [];
  const examined = rows.map((r) => r.pkg);
  for (const pkg of required) {
    if (!examined.includes(pkg)) problems.push(`BUN_COVERAGE ${pkg} was not examined (examined: [${examined.join(", ")}], want: [${required.join(", ")}])`);
  }
  for (const r of rows) {
    if (r.versions.length === 0) {
      problems.push(`BUN_VERSION_NOT_FOUND ${r.label}: no "Bun v<x.y.z> (" banner (bare "Bun v" string-pool fragments are not a version)`);
      continue;
    }
    const lowest = [...r.versions].sort(compareSemver)[0];
    if (compareSemver(lowest, floorStr) < 0) {
      problems.push(`BUN_BELOW_FLOOR ${r.label} embeds Bun ${lowest} (all occurrences: ${r.versions.join(", ")}), below the ${floorStr} floor`);
    }
  }
  if (problems.length === 0) return;
  throw new Error(
    `${problems.join("; ")}. CVE-2026-111497 (Brotli decoder RCE) is fixed in Bun ${floorStr}; the runtime embedded in the ` +
      "claude binary decodes `Content-Encoding: br` responses itself. Bump the @anthropic-ai/claude-code and " +
      "@anthropic-ai/claude-agent-sdk pins together to a pair whose binary embeds a fixed Bun, and re-prove the sandbox builder properties (#12026).",
  );
}
