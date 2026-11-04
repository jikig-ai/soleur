// #10065 Guard 2 (plan 2026-10-12-test-sandbox-masked-proc-suite-parity, Phase 6): pin the
// committed canary fixture's argv tail to the vendored bwrap BUILDER ITSELF, creds-free.
//
// The two vendored platform binaries (`@anthropic-ai/claude-agent-sdk-linux-x64`, the agent
// runner; `@anthropic-ai/claude-code-linux-x64`, the cron CLI path) are pinned by
// package-lock.json integrity, so what they push cannot change inside a PR. This file reads the
// builder's literal `.push(...)` calls straight out of those binaries and chains them, by
// equality, to infra/sandbox-canary-argv.json (the fixture the docker suite replays) and, in
// sandbox-proc-mask-runtime.test.ts, to the live spawn the SDK hands the shim. It does NOT read
// the sdk-bump ack trailer or any git state (guard row at the bottom).
//
// Counts below were MEASURED on 2026-11-04 against the installed binaries (python3 -I mmap
// reads, then re-derived by the helper); each pin names the version it was measured on. A new
// procfs-mount site in a bump reds `PROC_SITE_COUNT`; a changed tail reds `TAIL_LITERALS`.
// At claude-agent-sdk 0.3.311 / claude-code 2.1.311 the two platform packages ship ONE byte-identical binary
// (sha256 86dc1fcc...), so both pin rows carry the same measured shape; the scan still examines both packages so they
// can diverge again. That binary embeds Bun 1.4.4 (CVE-2026-111497 fix); the floor itself is asserted by
// claude-cli-pin-knows-models.test.ts.

import { beforeAll, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { stripComments } from "./helpers/strip-comments";
import {
  EXPECTED_TAIL_CALLS,
  HELPER_SELECTION_NEEDLES,
  SETTINGS_MAPPING_NEEDLES,
  assertBuilderTail,
  assertHelperSelection,
  scanHelperSelection,
  assertLiteralCensus,
  assertTailMatchesFixture,
  BRIDGE_PINS,
  assertBridgeStructure,
  scanBridgeStructure,
  bufferSource,
  builderTailTokens,
  extractBuilderTail,
  extractBuilderTailFrom,
  fileSource,
  normalizeSpawnTail,
  readFixtureTail,
  resolveVendoredBinary,
  scanLiterals,
  shouldSkipRealBinaryRows,
  type HelperSelectionPins,
  type LiteralPins,
} from "./helpers/vendored-bwrap-tail";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const FIXTURE_PATH = join(APP_ROOT, "infra", "sandbox-canary-argv.json");
const SANDBOX_CONFIG_PATH = join(APP_ROOT, "server", "agent-runner-sandbox-config.ts");
const HELPER_PATH = join(APP_ROOT, "test", "helpers", "vendored-bwrap-tail.ts");
const THIS_FILE = fileURLToPath(import.meta.url);

const SKIP_REAL = shouldSkipRealBinaryRows(process.platform, process.arch, process.env.CI);

// A scan of a ~250 MB binary is I/O bound; the vitest default (16 s) is too tight on a cold cache.
const REAL_BINARY_TIMEOUT_MS = 90_000;

// Measured 2026-11-04. `measuredVersion` is the installed package version the numbers were taken
// on; a different installed version is reported in every failure message, never silently accepted.
// Two proc sites (the per-command builder plus the `/run/claude-hook` sandbox), one of them in the hook
// function; two `--unshare-pid` literals (builder and hook); one root bind, one `--cap-drop ALL`, one `--cap-add CAP_SETFCAP`.
const MEASURED_SHAPE: LiteralPins = {
  procSites: 2,
  hookProcSites: 1,
  bindProcSites: 1,
  unsharePid: 2,
  rootBind: 1,
  capDropAll: 1,
  capDropTotal: 1,
  capAddSetfcap: 1,
  capAddTotal: 1,
  hookAnchors: 2,
};
const PINS: Record<"claude-agent-sdk" | "claude-code", LiteralPins & { measuredVersion: string }> = {
  "claude-agent-sdk": { measuredVersion: "0.3.311", ...MEASURED_SHAPE },
  "claude-code": { measuredVersion: "2.1.311", ...MEASURED_SHAPE },
};
type Pkg = keyof typeof PINS;
const PKGS = Object.keys(PINS) as Pkg[];

// ---------------------------------------------------------------------------------------------
// Synthetic builder buffers (written for this test; shaped like the minified builder, never a
// copy of vendor bytes). Variants isolate one mutation each.

interface SynthOpts {
  extraAfterBind?: string;
  extraAfterUnsetenv?: string;
  extraBeforeDev?: string;
  extraProcSite?: string;
  omitCapDrop?: boolean;
  capAddValue?: string | null;
  /** The hook sandbox is part of the measured shape for both packages; `false` removes it. */
  withHookSite?: boolean;
  anchorCopies?: number;
  noRootBind?: boolean;
  omitUnsetenv?: boolean;
  omitDisableUserns?: boolean;
  disableUsernsBeforeProc?: boolean;
}
const FILLER = "x".repeat(6000);
function synth(o: SynthOpts = {}): Buffer {
  const withHookSite = o.withHookSite ?? true;
  const anchor = `Xe.push("--dev","/dev"),Xe.push("--unshare-pid");`;
  const capFn = o.omitCapDrop
    ? `function CAP({euid:e}){let s=[];return s}`
    : `function CAP({euid:e,n}){let s=["--cap-drop","ALL"];if(e!==0)return s;${
        o.capAddValue === null ? "" : `if(n)s.push("--cap-add","${o.capAddValue ?? "CAP_SETFCAP"}");`
      }return s}`;
  // The shape after the proc branch: `--unsetenv <identifier>` in the condition, then the host-conditional `--disable-userns`.
  const disable = o.omitDisableUserns ? "" : `Xe.push("--disable-userns")`;
  const tailFlags = o.omitUnsetenv
    ? `if(Me===void 0&&X!==!0){let Ut=ee?null:Ae;if(Ut!==null&&D9(Ut))${disable || "0"};else if(!v1)v1=!0,wt("no seccomp helper in use")}`
    : `if(Xe.push("--unsetenv",R1),Me===void 0&&X!==!0){let Ut=ee?null:Ae;if(Ut!==null&&D9(Ut))${disable || "0"};else if(!v1)v1=!0,wt("no seccomp helper in use")}`;
  const builder =
    `${o.noRootBind ? "" : `Xe.push("--ro-bind","/","/");`}let kr={start:1,end:2};` +
    `${o.extraBeforeDev ?? ""}${anchor.repeat(o.anchorCopies ?? 1)}let br=process.geteuid?.();` +
    `${o.disableUsernsBeforeProc ? `Xe.push("--disable-userns");` : ""}` +
    `if(Xe.push("--unshare-user",...CAP({euid:br,n:1})),!ee)Xe.push("--proc","/proc");` +
    `else Xe.push("--bind","/proc","/proc");${o.extraAfterBind ?? ""}` +
    `${tailFlags}${o.extraAfterUnsetenv ?? ""}` +
    `let Tt=le||"bash";if(Xe.push("--",Ie,"-c"),s)Xe.push(Qe);`;
  const hook = withHookSite
    ? `var UPe="/run/claude-hook/apply-seccomp";function hookArgs(e){return["--unshare-pid","--proc","/proc","--dev","/dev"]}`
    : "";
  const extra = o.extraProcSite ?? "";
  // The real CLI carries a second, unrelated /run/claude-hook literal far from the hook builder.
  const hookDir = withHookSite ? `var HD="/run/claude-hook";` : "";
  return Buffer.from(`${hookDir}${FILLER}${capFn}${FILLER}${builder}${FILLER}${hook}${FILLER}${extra}${FILLER}`, "latin1");
}

const SDK_LIKE = PINS["claude-agent-sdk"];
const CLI_LIKE = PINS["claude-code"];

function verify(buf: Buffer, pins: LiteralPins, label: string): void {
  const src = bufferSource(buf);
  assertBuilderTail(extractBuilderTailFrom(src), label);
  assertLiteralCensus(scanLiterals(src), pins, label, "synthetic");
}
function failureOf(fn: () => void): string {
  try {
    fn();
  } catch (e) {
    return (e as Error).message;
  }
  return "";
}

// ---------------------------------------------------------------------------------------------
// The fixture tail: from its LAST `--dev`, the proc alternation resolved to the branch the sandbox
// config selects (enableWeakerNestedSandbox: true selects the `--bind /proc /proc` branch).

function selectedProcBranch(): "proc" | "bind" {
  const code = stripComments(readFileSync(SANDBOX_CONFIG_PATH, "utf8"), "agent-runner-sandbox-config.ts");
  const m = /\benableWeakerNestedSandbox:\s*(true|false)\s*,/.exec(code);
  if (!m) throw new Error("SANDBOX_CONFIG: enableWeakerNestedSandbox property not found in the return object");
  return m[1] === "true" ? "bind" : "proc";
}
const fixtureTail = (): string[] => readFixtureTail(FIXTURE_PATH);

describe("sandbox-vendored-argv-tail: environment gate (the skip arm cannot hide a missing binary in CI)", () => {
  it("skips only off linux-x64 with CI unset; every other combination RUNS the real-binary rows", () => {
    expect(shouldSkipRealBinaryRows("darwin", "arm64", undefined)).toBe(true);
    expect(shouldSkipRealBinaryRows("linux", "arm64", "")).toBe(true);
    expect(shouldSkipRealBinaryRows("darwin", "arm64", "1")).toBe(false);
    expect(shouldSkipRealBinaryRows("linux", "x64", undefined)).toBe(false);
    expect(shouldSkipRealBinaryRows("linux", "x64", "1")).toBe(false);
  });

  it("an absent platform binary FAILS with BINARY_MISSING (never a skip, never 0 checked)", () => {
    const msg = failureOf(() => resolveVendoredBinary("claude-code", join(APP_ROOT, "no-such-node-modules")));
    expect(msg).toMatch(/BINARY_MISSING/);
    expect(msg).toMatch(/claude-code-linux-x64/);
  });
});

describe("sandbox-vendored-argv-tail: synthetic mutation rows (extractor + census contract)", () => {
  it("a compliant synthetic SDK-shaped and CLI-shaped buffer both pass (must-PASS control)", () => {
    expect(failureOf(() => verify(synth(), SDK_LIKE, "claude-agent-sdk"))).toBe("");
    expect(failureOf(() => verify(synth({ withHookSite: true }), CLI_LIKE, "claude-code"))).toBe("");
  });

  it("must-PASS non-canonical inputs: an unrelated push before `--dev /dev` and a hook site at another offset still pass", () => {
    // Harness row: only a control that differs from the canonical in a way the contract permits can show the guard does not
    // reject everything.
    expect(failureOf(() => verify(synth({ extraBeforeDev: `Xe.push("--setenv","A","b");` }), SDK_LIKE, "claude-agent-sdk"))).toBe("");
    const shifted = Buffer.concat([Buffer.from("y".repeat(9000), "latin1"), synth({ withHookSite: true })]);
    expect(failureOf(() => verify(shifted, CLI_LIKE, "claude-code"))).toBe("");
  });

  it("extractBuilderTail returns exactly the expected literal call sequence", () => {
    const tail = extractBuilderTail(synth());
    expect(tail.calls).toEqual(EXPECTED_TAIL_CALLS);
    expect(builderTailTokens(tail, "bind")).toEqual([
      "--dev", "/dev", "--unshare-pid", "--unshare-user", "<CAP_SEGMENT>", "--bind", "/proc", "/proc",
      "--unsetenv", "<UNSETENV_VAR>", "--disable-userns",
    ]);
    expect(builderTailTokens(tail, "proc")).toEqual([
      "--dev", "/dev", "--unshare-pid", "--unshare-user", "<CAP_SEGMENT>", "--proc", "/proc",
      "--unsetenv", "<UNSETENV_VAR>", "--disable-userns",
    ]);
  });

  it("a vanished `--disable-userns`, or one moved ahead of the proc branch, or a vanished `--unsetenv`, reds TAIL_LITERALS", () => {
    // A pinned security flag cannot silently vanish or reorder. These reach the DESIGN property (the mask is the last mount
    // and the userns hardening still follows it), not the current shape of the code.
    for (const [name, o] of [
      ["--disable-userns removed", { omitDisableUserns: true }],
      ["--disable-userns before the proc branch", { disableUsernsBeforeProc: true, omitDisableUserns: true }],
      ["--unsetenv removed", { omitUnsetenv: true }],
    ] as const) {
      const msg = failureOf(() => verify(synth(o), SDK_LIKE, "claude-agent-sdk"));
      expect(msg, name).toMatch(/TAIL_LITERALS/);
    }
  });

  it("a mount pushed AFTER `--disable-userns` (the end of the tail) also reds TAIL_LITERALS", () => {
    const msg = failureOf(() =>
      verify(synth({ extraAfterUnsetenv: `Xe.push("--tmpfs","/proc");` }), SDK_LIKE, "claude-agent-sdk"),
    );
    expect(msg).toMatch(/TAIL_LITERALS/);
    expect(msg).toMatch(/--tmpfs/);
  });

  it("an extra `.push(\"--tmpfs\",\"/proc\")` after the bind push reds TAIL_LITERALS", () => {
    const msg = failureOf(() =>
      verify(synth({ extraAfterBind: `Xe.push("--tmpfs","/proc");` }), SDK_LIKE, "claude-agent-sdk"),
    );
    expect(msg).toMatch(/TAIL_LITERALS/);
    expect(msg).toMatch(/--tmpfs/);
    expect(msg).toMatch(/claude-agent-sdk/);
  });

  it("the same edit on the SECOND binary only names that binary and leaves the first green", () => {
    const entries: Array<[Pkg, Buffer, LiteralPins]> = [
      ["claude-agent-sdk", synth(), SDK_LIKE],
      ["claude-code", synth({ withHookSite: true, extraAfterBind: `Xe.push("--tmpfs","/proc");` }), CLI_LIKE],
    ];
    const failures = entries
      .map(([label, buf, pins]) => [label, failureOf(() => verify(buf, pins, label))] as const)
      .filter(([, m]) => m);
    expect(failures.map(([l]) => l)).toEqual(["claude-code"]);
    expect(failures[0][1]).toMatch(/TAIL_LITERALS/);
  });

  it("anchor absent reds `TAIL_ANCHOR found 0`, anchor twice reds `TAIL_ANCHOR found 2` (never 0 checked)", () => {
    expect(failureOf(() => extractBuilderTail(synth({ anchorCopies: 0 })))).toMatch(/TAIL_ANCHOR found 0/);
    expect(failureOf(() => extractBuilderTail(synth({ anchorCopies: 2 })))).toMatch(/TAIL_ANCHOR found 2/);
    expect(failureOf(() => extractBuilderTail(Buffer.alloc(0)))).toMatch(/TAIL_ANCHOR found 0/);
  });

  it("a terminator `.push(\"--\",` beyond the 4 KiB window reds TAIL_LITERALS (bounded window)", () => {
    // The complete expected sequence is present, so an UNBOUNDED window would pass; only the 4 KiB bound can red it.
    const head = `Xe.push("--dev","/dev"),Xe.push("--unshare-pid");Xe.push("--unshare-user",...CAP({euid:1})),`;
    const rest =
      `if(!ee)Xe.push("--proc","/proc");else Xe.push("--bind","/proc","/proc");` +
      `if(Xe.push("--unsetenv",R1),1)Xe.push("--disable-userns");Xe.push("--",Ie);`;
    const unbounded = Buffer.from(`${head}${rest}`, "latin1");
    const far = Buffer.from(`${head}${"y".repeat(5000)}${rest}`, "latin1");
    expect(failureOf(() => assertBuilderTail(extractBuilderTail(unbounded), "synthetic"))).toBe("");
    expect(failureOf(() => assertBuilderTail(extractBuilderTail(far), "synthetic"))).toMatch(/TAIL_LITERALS/);
  });

  it("REMOVAL direction: a vanished root bind or a vanished hook sandbox reds its own census code, never passes", () => {
    expect(failureOf(() => verify(synth({ noRootBind: true }), SDK_LIKE, "claude-agent-sdk"))).toMatch(
      /ROOT_SITE_COUNT want 1 got 0/,
    );
    // The CLI pin names a hook sandbox; a buffer without one must red both hook codes (a respelled builder
    // would otherwise count 0 sites and read clean).
    const msg = failureOf(() => verify(synth({ withHookSite: false }), CLI_LIKE, "claude-code"));
    expect(msg).toMatch(/HOOK_SITE_COUNT want 2 got 0/);
    expect(msg).toMatch(/PROC_SITE_COUNT want 1 got 0/);
  });

  it("a THIRD `\"--proc\",\"/proc\"` site (after the compliant two) reds `PROC_SITE_COUNT want 2 got 3` naming inspect-and-update steps", () => {
    const msg = failureOf(() =>
      verify(synth({ extraProcSite: `function other(){return["--proc","/proc"]}` }), SDK_LIKE, "claude-agent-sdk"),
    );
    expect(msg).toMatch(/PROC_SITE_COUNT want 2 got 3/);
    expect(msg).toMatch(/inspect/i);
    expect(msg).toMatch(/update/i);
    expect(msg).toMatch(/PINS/);
  });

  it("a second proc site NOT inside the /run/claude-hook function does not satisfy a hook-site pin", () => {
    // CLI-shaped pin wants 2 sites with 1 inside the hook function; 2 sites with 0 inside must red.
    const msg = failureOf(() =>
      verify(
        synth({ extraProcSite: `function other(){return["--proc","/proc"]}`, withHookSite: false }),
        { ...CLI_LIKE, hookAnchors: 0 },
        "claude-code",
      ),
    );
    expect(msg).toMatch(/PROC_SITE_COUNT/);
    expect(msg).toMatch(/hook/i);
  });

  it("a second `\"--bind\",\"/proc\",\"/proc\"` site reds PROC_SITE_COUNT", () => {
    const msg = failureOf(() =>
      verify(synth({ extraProcSite: `x.push("--bind","/proc","/proc");` }), SDK_LIKE, "claude-agent-sdk"),
    );
    expect(msg).toMatch(/PROC_SITE_COUNT want 1 got 2/);
  });

  it("a second root bind or a second `--unshare-pid` literal reds SITE_COUNT", () => {
    expect(
      failureOf(() => verify(synth({ extraProcSite: `a.push("--ro-bind","/","/");` }), SDK_LIKE, "claude-agent-sdk")),
    ).toMatch(/SITE_COUNT/);
    expect(
      failureOf(() => verify(synth({ extraProcSite: `a.push("--unshare-pid");` }), SDK_LIKE, "claude-agent-sdk")),
    ).toMatch(/SITE_COUNT/);
  });

  it("the cap segment losing `--cap-drop ALL` reds CAP_BARRIER", () => {
    const msg = failureOf(() => verify(synth({ omitCapDrop: true }), SDK_LIKE, "claude-agent-sdk"));
    expect(msg).toMatch(/CAP_BARRIER/);
  });

  it("a `--cap-add` other than CAP_SETFCAP reds CAP_BARRIER", () => {
    const msg = failureOf(() => verify(synth({ capAddValue: "CAP_SYS_ADMIN" }), SDK_LIKE, "claude-agent-sdk"));
    expect(msg).toMatch(/CAP_BARRIER/);
    expect(msg).toMatch(/CAP_SETFCAP/);
  });

  it("a second, extra `--cap-add` literal elsewhere in the binary reds CAP_BARRIER", () => {
    const msg = failureOf(() =>
      verify(synth({ extraProcSite: `z.push("--cap-add","CAP_NET_ADMIN");` }), SDK_LIKE, "claude-agent-sdk"),
    );
    expect(msg).toMatch(/CAP_BARRIER/);
  });

  it("the chunked scanner counts a literal that straddles a chunk boundary exactly once", () => {
    const needle = `"--ro-bind","/","/"`;
    const buf = synth();
    const at = buf.indexOf(needle);
    expect(at).toBeGreaterThan(0);
    // Place the chunk edge in the middle of the needle, and also exactly on it, and just after it.
    for (const chunk of [at + 3, at, at + needle.length, 4096, 997]) {
      const census = scanLiterals(bufferSource(buf), { chunkSize: chunk });
      expect(census.counts.rootBind, `chunkSize=${chunk}`).toBe(1);
      expect(census.counts.procSites, `chunkSize=${chunk}`).toBe(2);
    }
  });
});

describe("sandbox-vendored-argv-tail: helper-selection pins (#10445, synthetic)", () => {
  const FULL = Buffer.from([...Object.values(HELPER_SELECTION_NEEDLES), ...Object.values(SETTINGS_MAPPING_NEEDLES)].join(" \0 "));
  const PINS_ONE: HelperSelectionPins = { skipLine: 1, applyLine: 1, missingLine: 1 };

  it("a buffer carrying every selection literal once passes (must-PASS control)", () => {
    expect(failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(FULL)), PINS_ONE, "synthetic"))).toBe("");
  });

  it("a vanished skip line reds HELPER_SELECTION skipLine naming the wrapped-command arm", () => {
    const without = Buffer.from(FULL.toString().replace(HELPER_SELECTION_NEEDLES.skipLine, "X"));
    const msg = failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(without)), PINS_ONE, "synthetic"));
    expect(msg).toMatch(/HELPER_SELECTION skipLine want 1 got 0/);
    expect(msg).toMatch(/sandbox-masked-proc-docker\.test\.sh/);
  });

  it("each vanished settings-mapping anchor reds even when all three log lines remain", () => {
    expect(Object.keys(SETTINGS_MAPPING_NEEDLES).length, "a tripwire over zero anchors cannot fire").toBeGreaterThanOrEqual(2);
    for (const [k, needle] of Object.entries(SETTINGS_MAPPING_NEEDLES)) {
      const without = Buffer.from(FULL.toString().replace(needle, "X"));
      const msg = failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(without)), PINS_ONE, "synthetic"));
      expect(msg, k).toMatch(new RegExp(`HELPER_SELECTION settingsMapping\\.${k} want >= 1 got 0`));
    }
  });

  it("the mapping anchors are CONTENT, never a minified identifier or the old optional chain", () => {
    for (const needle of Object.values(SETTINGS_MAPPING_NEEDLES)) {
      expect(needle).toMatch(/allowAllUnixSockets/);
      expect(needle).not.toMatch(/\?\./);
      expect(needle).not.toMatch(/\b[A-Za-z]\$?\b[,)]/);
    }
  });

  it("a second copy of a log literal reds (a new code path selects the helper elsewhere)", () => {
    const doubled = Buffer.concat([FULL, Buffer.from(" \0 " + HELPER_SELECTION_NEEDLES.applyLine)]);
    const msg = failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(doubled)), PINS_ONE, "synthetic"));
    expect(msg).toMatch(/HELPER_SELECTION applyLine want 1 got 2/);
  });

  it("MORE copies of a mapping anchor still pass (a short key's count is not stable across minifier runs)", () => {
    const more = Buffer.concat([FULL, Buffer.from(" \0 allowAllUnixSockets: \0 network.allowAllUnixSockets")]);
    expect(failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(more)), PINS_ONE, "synthetic"))).toBe("");
  });
});

// ---------------------------------------------------------------------------------------------
// #10455 (a): the proxy-bridge structure the AF_UNIX variant depends on. The deny is only safe for NO-EGRESS sessions because
// the builder starts `socat TCP-LISTEN:... UNIX-CONNECT:<sock>` bridges in the sandbox BEFORE the user command and
// unshares the net namespace. If a bump reorders that (or drops the bridge), the "egress sessions need AF_UNIX, no-egress
// sessions only lose a dead bridge" premise is unproven and the variant must be re-measured through the real SDK.

const BRIDGE_WRAPPER_OK =
  "function WV(e,r,n,s,h,g){let y=h||\"bash\",b=As([g??\"socat\"]),C=(D,M)=>`{ ${b} TCP6-LISTEN:${D},ipv6only=0,fork,reuseaddr,backlog=4096 UNIX-CONNECT:${M} || exec ${b} TCP4-LISTEN:${D},fork,reuseaddr,backlog=4096 UNIX-CONNECT:${M}; } >/dev/null 2>&1 &`," +
  "S=[C(3128,e),\"_srt_http=$!\",C(1080,r),\"_srt_socks=$!\",\"trap 'rc=$?; kill %1 %2 2>/dev/null; exit $rc' EXIT\",...WD];" +
  "if(s){let T=s+As([y,\"-c\",n]),w=[...S,T].join(`\n`);return`${y} -c ${As([w])}`}else{let T=[...S,`eval ${As([n])}`].join(`\n`);return`${y} -c ${As([T])}`}}";
const BRIDGE_NET_OK =
  'if(s){if(tt.push("--unshare-net"),h&&g){if(!_t.existsSync(h))throw Error(`Linux HTTP bridge socket does not exist: ${h}.`);' +
  'if(!_t.existsSync(g))throw Error(`Linux SOCKS bridge socket does not exist: ${g}.`);if(tt.push("--bind",h,h),g!==h)tt.push("--bind",g,g);';
const bridgeBuf = (wrapper = BRIDGE_WRAPPER_OK, net = BRIDGE_NET_OK) =>
  Buffer.from(`${FILLER}${wrapper}${FILLER}${net}${FILLER}`, "latin1");

describe("sandbox-vendored-argv-tail: proxy-bridge structure (#10455 a, synthetic)", () => {
  it("the literal shape passes: bridges precede the user command, --unshare-net, bridge binds", () => {
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf())), "synthetic"))).toBe("");
  });
  it("the user command ahead of the bridges (reordered array) reds BRIDGE_ORDER", () => {
    const reordered = BRIDGE_WRAPPER_OK.replace("[...S,T]", "[T,...S]");
    expect(reordered).not.toBe(BRIDGE_WRAPPER_OK);
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf(reordered))), "synthetic"))).toMatch(
      /BRIDGE_ORDER/,
    );
  });
  it("the user command ahead of the bridges in the NO-HOOK-SITE branch reds BRIDGE_ORDER too (both branches are pinned)", () => {
    const reordered = BRIDGE_WRAPPER_OK.replace("[...S,`eval ${As([n])}`]", "[`eval ${As([n])}`,...S]");
    expect(reordered).not.toBe(BRIDGE_WRAPPER_OK);
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf(reordered))), "synthetic"))).toMatch(
      /BRIDGE_ORDER/,
    );
  });
  it("the IPv4 fallback bridge missing, or a bridge no longer started in the background, reds BRIDGE_ORDER", () => {
    const noFallback = BRIDGE_WRAPPER_OK.replace(/ \|\| exec \$\{b\} TCP4-LISTEN:\$\{D\},fork,reuseaddr,backlog=4096 UNIX-CONNECT:\$\{M\}/, "");
    expect(noFallback).not.toBe(BRIDGE_WRAPPER_OK);
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf(noFallback))), "synthetic"))).toMatch(/BRIDGE_ORDER/);
    const foreground = BRIDGE_WRAPPER_OK.replace(" >/dev/null 2>&1 &`", " >/dev/null 2>&1`");
    expect(foreground).not.toBe(BRIDGE_WRAPPER_OK);
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf(foreground))), "synthetic"))).toMatch(/BRIDGE_ORDER/);
  });
  it("renamed (minified) identifiers do not matter: the same shape under other names passes (must-PASS non-canonical)", () => {
    const renamed = BRIDGE_WRAPPER_OK.replaceAll("WV", "$Q").replaceAll("As(", "z9(").replaceAll("...WD", "...$w");
    expect(renamed).not.toBe(BRIDGE_WRAPPER_OK);
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf(renamed))), "synthetic"))).toBe("");
  });
  it("the trap line moved ahead of the bridges reds BRIDGE_ORDER", () => {
    const trap = "\"trap 'rc=$?; kill %1 %2 2>/dev/null; exit $rc' EXIT\"";
    const moved = BRIDGE_WRAPPER_OK.replace(`,${trap},...WD]`, ",...WD]").replace("S=[C(3128,e)", `S=[${trap},C(3128,e)`);
    expect(moved).not.toBe(BRIDGE_WRAPPER_OK);
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf(moved))), "synthetic"))).toMatch(
      /BRIDGE_ORDER/,
    );
  });
  it("a missing --unshare-net ahead of the bridge binds reds BRIDGE_NET", () => {
    const noNet = BRIDGE_NET_OK.replace('tt.push("--unshare-net")', 'tt.push("--share-net")');
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf(BRIDGE_WRAPPER_OK, noNet))), "synthetic"))).toMatch(
      /BRIDGE_NET|anchor/,
    );
  });
  it("a missing bridge bind reds BRIDGE_NET", () => {
    const noBind = BRIDGE_NET_OK.replace('if(tt.push("--bind",h,h),g!==h)tt.push("--bind",g,g);', "");
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(bridgeBuf(BRIDGE_WRAPPER_OK, noBind))), "synthetic"))).toMatch(
      /BRIDGE_NET/,
    );
  });
  it("an absent wrapper reds the anchor count", () => {
    expect(failureOf(() => assertBridgeStructure(scanBridgeStructure(bufferSource(Buffer.from(FILLER, "latin1"))), "synthetic"))).toMatch(
      /anchor/i,
    );
  });
  it("the pins are non-empty (floor)", () => {
    expect(Object.keys(BRIDGE_PINS).length).toBeGreaterThanOrEqual(2);
  });
});

describe("sandbox-vendored-argv-tail: spawn-tail normalization (cap segment is not ignored)", () => {
  const base = ["--dev", "/dev", "--unshare-pid", "--unshare-user"];
  it("collapses `--cap-drop ALL` with and without `--cap-add CAP_SETFCAP` to the same token", () => {
    const a = normalizeSpawnTail([...base, "--cap-drop", "ALL", "--bind", "/proc", "/proc"]);
    const b = normalizeSpawnTail([...base, "--cap-drop", "ALL", "--cap-add", "CAP_SETFCAP", "--bind", "/proc", "/proc"]);
    expect(a).toEqual(b);
    expect(a).toContain("<CAP_SEGMENT>");
  });
  it("rejects a tail with no `--cap-drop ALL` and a non-CAP_SETFCAP `--cap-add` (CAP_BARRIER)", () => {
    expect(failureOf(() => normalizeSpawnTail([...base, "--bind", "/proc", "/proc"]))).toMatch(/CAP_BARRIER/);
    expect(
      failureOf(() =>
        normalizeSpawnTail([...base, "--cap-drop", "ALL", "--cap-add", "CAP_SYS_ADMIN", "--bind", "/proc", "/proc"]),
      ),
    ).toMatch(/CAP_BARRIER/);
    expect(
      failureOf(() =>
        normalizeSpawnTail([...base, "--cap-drop", "ALL", "--bind", "/proc", "/proc", "--cap-add", "CAP_SYS_ADMIN"]),
      ),
    ).toMatch(/CAP_BARRIER/);
  });
});

describe("sandbox-vendored-argv-tail: trailing flags in spawn-tail normalization (--unsetenv, --disable-userns)", () => {
  const head = ["--dev", "/dev", "--unshare-pid", "--unshare-user", "--cap-drop", "ALL", "--bind", "/proc", "/proc"];
  it("the env var NAME is collapsed on both sides, so a literal in a spawn equals the identifier marker from the builder", () => {
    expect(normalizeSpawnTail([...head, "--unsetenv", "SRT_ALLOW_NESTED_USERNS"])).toEqual(
      normalizeSpawnTail([...head, "--unsetenv", "SOME_OTHER_VAR"]),
    );
    expect(normalizeSpawnTail([...head, "--unsetenv", "SRT_ALLOW_NESTED_USERNS"]).slice(-2)).toEqual(["--unsetenv", "<UNSETENV_VAR>"]);
  });
  it("`--disable-userns` is host-conditional: a tail with it equals a tail without it", () => {
    expect(normalizeSpawnTail([...head, "--unsetenv", "A", "--disable-userns"])).toEqual(normalizeSpawnTail([...head, "--unsetenv", "A"]));
  });
  it("an `--unsetenv` with no operand, or one that swallowed a flag, reds UNSETENV_SHAPE", () => {
    expect(failureOf(() => normalizeSpawnTail([...head, "--unsetenv"]))).toMatch(/UNSETENV_SHAPE/);
    expect(failureOf(() => normalizeSpawnTail([...head, "--unsetenv", "--disable-userns"]))).toMatch(/UNSETENV_SHAPE/);
    expect(failureOf(() => normalizeSpawnTail([...head, "--unsetenv", "bad name"]))).toMatch(/UNSETENV_SHAPE/);
  });
  it("a tail that gained an extra mount after `--unsetenv` is still a different tail", () => {
    expect(normalizeSpawnTail([...head, "--unsetenv", "A", "--tmpfs", "/proc"])).not.toEqual(normalizeSpawnTail([...head, "--unsetenv", "A"]));
  });
});

describe("sandbox-vendored-argv-tail: fixture tail equality (synthetic)", () => {
  it("the committed fixture tail equals the builder tail with the selected branch resolved", () => {
    const tail = extractBuilderTail(synth());
    const branch = selectedProcBranch();
    expect(branch).toBe("bind");
    expect(failureOf(() => assertTailMatchesFixture(builderTailTokens(tail, branch), fixtureTail(), "synthetic"))).toBe("");
  });

  it("a fixture tail edited to add `--tmpfs /proc` after the bind reds TAIL_DRIFT naming the only regenerator", () => {
    const tail = extractBuilderTail(synth());
    const msg = failureOf(() =>
      assertTailMatchesFixture(builderTailTokens(tail, "bind"), [...fixtureTail(), "--tmpfs", "/proc"], "synthetic"),
    );
    expect(msg).toMatch(/TAIL_DRIFT/);
    expect(msg).toMatch(/SANDBOX_CANARY_MODE=capture/);
    expect(msg).toMatch(/Without credentials, stop and report/);
  });

  it("a fixture that lacks the `--bind /proc /proc` tail reds TAIL_DRIFT", () => {
    const tail = extractBuilderTail(synth());
    const ft = fixtureTail();
    const at = ft.findIndex((t, i) => t === "--bind" && ft[i + 1] === "/proc" && ft[i + 2] === "/proc");
    expect(at, "the fixture tail has a `--bind /proc /proc`").toBeGreaterThan(0);
    const noBind = [...ft.slice(0, at), ...ft.slice(at + 3)];
    expect(failureOf(() => assertTailMatchesFixture(builderTailTokens(tail, "bind"), noBind, "synthetic"))).toMatch(
      /TAIL_DRIFT/,
    );
  });

  it("the fixture's own tail has the expected shape (--dev first, one --bind /proc /proc last)", () => {
    const t = fixtureTail();
    expect(t.slice(0, 4)).toEqual(["--dev", "/dev", "--unshare-pid", "--unshare-user"]);
    // The mask is still the LAST mount; the only things after it are the env unset and (when bubblewrap supports it) the userns hardening.
    const bindAt = t.findIndex((x, i) => x === "--bind" && t[i + 1] === "/proc" && t[i + 2] === "/proc");
    expect(bindAt, "exactly one `--bind /proc /proc` in the fixture tail").toBe(t.lastIndexOf("--bind"));
    expect(bindAt).toBeGreaterThan(0);
    const after = t.slice(bindAt + 3);
    expect(after[0]).toBe("--unsetenv");
    expect(after.filter((x) => x === "--unsetenv")).toHaveLength(1);
    expect(after.slice(2).filter((x) => x !== "--disable-userns")).toEqual([]);
  });
});

// Measured 2026-11-04 (claude-agent-sdk 0.3.311, claude-code 2.1.311 -- the versions in PINS above) with fixed-string scans (`grep -a -o -F <literal> claude | wc -l`).
// The settings->builder mapping is a content-anchored tripwire (SETTINGS_MAPPING_NEEDLES, >= 1 hit each), not a count: the
// wrapped-command arm is the proof. (Before 0.3.311 only the SDK package carried the optional-chain mapping, count 2; the CLI 0.)
const HELPER_PINS: Record<"claude-agent-sdk" | "claude-code", HelperSelectionPins> = {
  "claude-agent-sdk": { skipLine: 2, applyLine: 2, missingLine: 2 },
  "claude-code": { skipLine: 2, applyLine: 2, missingLine: 2 },
};

describe.skipIf(SKIP_REAL)("sandbox-vendored-argv-tail: real vendored binaries", () => {
  for (const pkg of PKGS) {
    const pins = PINS[pkg];
    describe(`@anthropic-ai/${pkg}-linux-x64 (measured ${pins.measuredVersion})`, () => {
      it(
        "the platform binary resolves (BINARY_MISSING under CI and on linux-x64, never a silent skip)",
        () => {
          const bin = resolveVendoredBinary(pkg, join(APP_ROOT, "node_modules"));
          expect(bin.path).toMatch(new RegExp(`${pkg}-linux-x64`));
          expect(bin.size).toBeGreaterThan(1_000_000);
        },
        REAL_BINARY_TIMEOUT_MS,
      );

      // One read of the ~250 MB binary per package: the tail and the census are computed once and every row
      // below asserts on them (each row used to reopen and rescan the file).
      let scanned: {
        version: string;
        tail: ReturnType<typeof extractBuilderTailFrom>;
        census: ReturnType<typeof scanLiterals>;
        helper: ReturnType<typeof scanHelperSelection>;
        bridge: ReturnType<typeof scanBridgeStructure>;
      };
      beforeAll(() => {
        const bin = resolveVendoredBinary(pkg, join(APP_ROOT, "node_modules"));
        const fs = fileSource(bin.path);
        try {
          scanned = {
            version: bin.version,
            tail: extractBuilderTailFrom(fs.source),
            census: scanLiterals(fs.source),
            helper: scanHelperSelection(fs.source),
            bridge: scanBridgeStructure(fs.source),
          };
        } finally {
          fs.close();
        }
      }, REAL_BINARY_TIMEOUT_MS);

      it("the builder tail is exactly the expected literal call sequence (TAIL_ANCHOR / TAIL_LITERALS)", () => {
        expect(failureOf(() => assertBuilderTail(scanned.tail, `${pkg}@${scanned.version}`))).toBe("");
      });

      it("the procfs-mount, root-bind, cap-drop and cap-add literal census equals the measured pin", () => {
        const msg = failureOf(() =>
          assertLiteralCensus(scanned.census, pins, `${pkg}@${scanned.version}`, `measured on ${pins.measuredVersion}`),
        );
        expect(msg).toBe("");
      });

      it("the unix-socket helper selection (skip/apply/missing lines exact, settings-mapping anchors >= 1) equals the measured pin (#10445)", () => {
        expect(failureOf(() => assertHelperSelection(scanned.helper, HELPER_PINS[pkg], `${pkg}@${scanned.version}`))).toBe("");
      });

      it("the bridge wrapper starts both socat bridges before the user command and the net namespace is unshared with the bridge binds (#10455 a)", () => {
        expect(failureOf(() => assertBridgeStructure(scanned.bridge, `${pkg}@${scanned.version}`))).toBe("");
        expect(scanned.bridge.wrapperHits).toBe(BRIDGE_PINS.wrapperHits);
        expect(scanned.bridge.netHits).toBe(BRIDGE_PINS.netHits);
      });

      it("the builder tail equals the committed fixture tail (infra/sandbox-canary-argv.json), cap segment normalized", () => {
        const msg = failureOf(() =>
          assertTailMatchesFixture(
            builderTailTokens(scanned.tail, selectedProcBranch()),
            fixtureTail(),
            `${pkg}@${scanned.version}`,
          ),
        );
        expect(msg).toBe("");
      });
    });
  }
});

describe("sandbox-vendored-argv-tail: the scanned x64 binary stands for every platform package", () => {
  it("package-lock.json pins every linux variant (x64, x64-musl, arm64, arm64-musl) of each package to the measured version", () => {
    const lock = JSON.parse(readFileSync(join(APP_ROOT, "package-lock.json"), "utf8")) as {
      packages: Record<string, { version?: string }>;
    };
    for (const pkg of PKGS) {
      const variants = ["linux-x64", "linux-x64-musl", "linux-arm64", "linux-arm64-musl"];
      for (const v of variants) {
        const entry = lock.packages[`node_modules/@anthropic-ai/${pkg}-${v}`];
        expect(entry, `${pkg}-${v} is missing from package-lock.json (a platform variant that is no longer pinned)`).toBeDefined();
        expect(
          entry?.version,
          `${pkg}-${v} is pinned to ${entry?.version}, the scan measured ${PINS[pkg].measuredVersion}: the builder in another platform package may differ`,
        ).toBe(PINS[pkg].measuredVersion);
      }
    }
  });
});

describe("sandbox-vendored-argv-tail: independence from the ack trailer and git state", () => {
  it("neither this test nor its helper names the sdk-bump ack trailer, imports a process spawner, or reads git state", () => {
    // Needles are assembled from fragments so this file does not contain them contiguously.
    const forbidden = [
      ["sdk", "bump", "verified"].join("-"),
      ["child", "process"].join("_"),
      ["git", "log"].join(" "),
      ["git", "show"].join(" "),
      ["git", "diff"].join(" "),
      ["git", "rev-parse"].join(" "),
      ["GIT", "DIR"].join("_"),
      ["GIT", "WORK", "TREE"].join("_"),
      [".g", "it/"].join(""),
    ];
    for (const path of [THIS_FILE, HELPER_PATH]) {
      const code = stripComments(readFileSync(path, "utf8"), "x.ts");
      for (const needle of forbidden) {
        expect(code.includes(needle), `${path} contains ${JSON.stringify(needle)}`).toBe(false);
      }
    }
  });
});
