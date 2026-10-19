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
// Counts below were MEASURED on 2026-10-12 against the installed binaries (python3 -I mmap
// reads, then re-derived by the helper); each pin names the version it was measured on. A new
// procfs-mount site in a bump reds `PROC_SITE_COUNT`; a changed tail reds `TAIL_LITERALS`.

import { beforeAll, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { stripComments } from "./helpers/strip-comments";
import {
  EXPECTED_TAIL_CALLS,
  HELPER_SELECTION_NEEDLES,
  assertBuilderTail,
  assertHelperSelection,
  scanHelperSelection,
  assertLiteralCensus,
  assertTailMatchesFixture,
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

// Measured 2026-10-12. `measuredVersion` is the installed package version the numbers were taken
// on; a different installed version is reported in every failure message, never silently accepted.
const PINS: Record<"claude-agent-sdk" | "claude-code", LiteralPins & { measuredVersion: string }> = {
  "claude-agent-sdk": {
    measuredVersion: "0.3.284",
    procSites: 1,
    hookProcSites: 0,
    bindProcSites: 1,
    unsharePid: 1,
    rootBind: 1,
    capDropAll: 1,
    capDropTotal: 1,
    capAddSetfcap: 1,
    capAddTotal: 1,
    hookAnchors: 0,
  },
  "claude-code": {
    measuredVersion: "2.1.293",
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
  },
};
type Pkg = keyof typeof PINS;
const PKGS = Object.keys(PINS) as Pkg[];

// ---------------------------------------------------------------------------------------------
// Synthetic builder buffers (written for this test; shaped like the minified builder, never a
// copy of vendor bytes). Variants isolate one mutation each.

interface SynthOpts {
  extraAfterBind?: string;
  extraProcSite?: string;
  omitCapDrop?: boolean;
  capAddValue?: string | null;
  withHookSite?: boolean;
  anchorCopies?: number;
  noRootBind?: boolean;
}
const FILLER = "x".repeat(6000);
function synth(o: SynthOpts = {}): Buffer {
  const anchor = `Xe.push("--dev","/dev"),Xe.push("--unshare-pid");`;
  const capFn = o.omitCapDrop
    ? `function CAP({euid:e}){let s=[];return s}`
    : `function CAP({euid:e,n}){let s=["--cap-drop","ALL"];if(e!==0)return s;${
        o.capAddValue === null ? "" : `if(n)s.push("--cap-add","${o.capAddValue ?? "CAP_SETFCAP"}");`
      }return s}`;
  const builder =
    `${o.noRootBind ? "" : `Xe.push("--ro-bind","/","/");`}let kr={start:1,end:2};` +
    `${anchor.repeat(o.anchorCopies ?? 1)}let br=process.geteuid?.();` +
    `if(Xe.push("--unshare-user",...CAP({euid:br,n:1})),!ee)Xe.push("--proc","/proc");` +
    `else Xe.push("--bind","/proc","/proc");${o.extraAfterBind ?? ""}` +
    `let Tt=le||"bash";if(Xe.push("--",Ie,"-c"),s)Xe.push(Qe);`;
  const hook = o.withHookSite
    ? `var UPe="/run/claude-hook/apply-seccomp";function hookArgs(e){return["--unshare-pid","--proc","/proc","--dev","/dev"]}`
    : "";
  const extra = o.extraProcSite ?? "";
  // The real CLI carries a second, unrelated /run/claude-hook literal far from the hook builder.
  const hookDir = o.withHookSite ? `var HD="/run/claude-hook";` : "";
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

  it("extractBuilderTail returns exactly the expected literal call sequence", () => {
    const tail = extractBuilderTail(synth());
    expect(tail.calls).toEqual(EXPECTED_TAIL_CALLS);
    expect(builderTailTokens(tail, "bind")).toEqual([
      "--dev", "/dev", "--unshare-pid", "--unshare-user", "<CAP_SEGMENT>", "--bind", "/proc", "/proc",
    ]);
    expect(builderTailTokens(tail, "proc")).toEqual([
      "--dev", "/dev", "--unshare-pid", "--unshare-user", "<CAP_SEGMENT>", "--proc", "/proc",
    ]);
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
    const rest = `if(!ee)Xe.push("--proc","/proc");else Xe.push("--bind","/proc","/proc");Xe.push("--",Ie);`;
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

  it("a second `\"--proc\",\"/proc\"` site reds `PROC_SITE_COUNT want 1 got 2` naming inspect-and-update steps", () => {
    const msg = failureOf(() =>
      verify(synth({ extraProcSite: `function other(){return["--proc","/proc"]}` }), SDK_LIKE, "claude-agent-sdk"),
    );
    expect(msg).toMatch(/PROC_SITE_COUNT want 1 got 2/);
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
      expect(census.counts.procSites, `chunkSize=${chunk}`).toBe(1);
    }
  });
});

describe("sandbox-vendored-argv-tail: helper-selection pins (#10445, synthetic)", () => {
  const FULL = Buffer.from(Object.values(HELPER_SELECTION_NEEDLES).join(" \0 "));
  const PINS_ONE: HelperSelectionPins = { skipLine: 1, applyLine: 1, missingLine: 1, settingsMapping: 1 };

  it("a buffer carrying every selection literal once passes (must-PASS control)", () => {
    expect(failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(FULL)), PINS_ONE, "synthetic"))).toBe("");
  });

  it("a vanished skip line reds HELPER_SELECTION skipLine naming the wrapped-command arm", () => {
    const without = Buffer.from(FULL.toString().replace(HELPER_SELECTION_NEEDLES.skipLine, "X"));
    const msg = failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(without)), PINS_ONE, "synthetic"));
    expect(msg).toMatch(/HELPER_SELECTION skipLine want 1 got 0/);
    expect(msg).toMatch(/sandbox-masked-proc-docker\.test\.sh/);
  });

  it("a vanished settings->builder mapping reds even when all three log lines remain", () => {
    const without = Buffer.from(FULL.toString().replace(HELPER_SELECTION_NEEDLES.settingsMapping, "X"));
    const msg = failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(without)), PINS_ONE, "synthetic"));
    expect(msg).toMatch(/HELPER_SELECTION settingsMapping want 1 got 0/);
  });

  it("a second copy of a literal reds (a new code path selects the helper elsewhere)", () => {
    const doubled = Buffer.concat([FULL, Buffer.from(" \0 " + HELPER_SELECTION_NEEDLES.applyLine)]);
    const msg = failureOf(() => assertHelperSelection(scanHelperSelection(bufferSource(doubled)), PINS_ONE, "synthetic"));
    expect(msg).toMatch(/HELPER_SELECTION applyLine want 1 got 2/);
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
    const noBind = fixtureTail().slice(0, -3);
    expect(failureOf(() => assertTailMatchesFixture(builderTailTokens(tail, "bind"), noBind, "synthetic"))).toMatch(
      /TAIL_DRIFT/,
    );
  });

  it("the fixture's own tail has the expected shape (--dev first, one --bind /proc /proc last)", () => {
    const t = fixtureTail();
    expect(t.slice(0, 4)).toEqual(["--dev", "/dev", "--unshare-pid", "--unshare-user"]);
    expect(t.slice(-3)).toEqual(["--bind", "/proc", "/proc"]);
  });
});

// Measured 2026-10-16 (claude-agent-sdk 0.3.284, claude-code 2.1.293 -- the versions in PINS above) with fixed-string scans (`grep -a -o -F <literal> claude | wc -l`).
// Only the agent-sdk package reads the programmatic `sandbox` option; the CLI package never maps it.
const HELPER_PINS: Record<"claude-agent-sdk" | "claude-code", HelperSelectionPins> = {
  "claude-agent-sdk": { skipLine: 2, applyLine: 2, missingLine: 2, settingsMapping: 2 },
  "claude-code": { skipLine: 2, applyLine: 2, missingLine: 2, settingsMapping: 0 },
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

      it("the unix-socket helper selection (skip/apply/missing lines, settings mapping) equals the measured pin (#10445)", () => {
        expect(failureOf(() => assertHelperSelection(scanned.helper, HELPER_PINS[pkg], `${pkg}@${scanned.version}`))).toBe("");
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
