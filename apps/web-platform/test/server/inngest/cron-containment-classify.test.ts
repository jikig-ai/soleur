import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE ES-module imports — sets NEXT_PHASE so importing the
// cron substrate (which transitively touches the inngest client in some paths)
// does not throw on the missing INNGEST_SIGNING_KEY in the test env. Mirrors
// function-registry-count.test.ts:9-11.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { CRON_BASH_ALLOWLISTS } from "@/server/inngest/functions/_cron-claude-eval-substrate";
import { TIER2_DEFERRED_CRONS } from "@/server/inngest/functions/_cron-shared";

// The containment gate (#5072). When a new `cron-*.ts` Inngest function lands,
// it must declare its containment class so it cannot ship with an unbounded
// shell/network surface. The three observable classes (verified against the
// live tree 2026-06-12, NOT the issue's binary framing):
//
//   1. substrate-contained — the cron CALLS spawnClaudeEval()/runClaudeEval()
//      (the `_cron-claude-eval-substrate` wrapper that installs the
//      cron-bash-allowlist PreToolUse hook + reads CRON_BASH_ALLOWLISTS). Such a
//      cron MUST be declared in exactly one of CRON_BASH_ALLOWLISTS (Tier-1,
//      finite gh/git verbs) or TIER2_DEFERRED_CRONS (Tier-2, firewall-deferred).
//      Detection is by CALL SITE, not import: cron-daily-triage imports helpers
//      (resolveClaudeBin, KILL_ESCALATION_MS) from the substrate yet spawns
//      claude on its own path — it is NOT substrate-contained.
//
//   2. direct-spawn — a real `spawn(` call (claude with its own flags, or
//      git/bash) that does NOT route through the contained wrapper. Contained by
//      the #5046 container egress firewall (and, where applicable, fixed argv).
//      Must be enumerated in KNOWN_DIRECT_SPAWN_CRONS below so a NEW spawn site
//      fails closed and forces an explicit containment decision.
//
//   3. pure-TS — no spawn at all. Must carry NO containment entry; a stray entry
//      signals a copy-paste error.
//
// This is the source-scan sibling of function-registry-count.test.ts — a sixth
// "new-cron lockstep" dimension, same directory, same readdirSync + readFileSync
// + import-the-canonical-symbol idiom.

const FUNCTIONS_DIR = resolve(__dirname, "../../../server/inngest/functions");

// Grandfather set: every cron that direct-spawns today (comments stripped,
// 2026-06-12 live enumeration — NOT the plan's stale 6; cron-daily-triage and
// cron-follow-through-monitor spawn claude directly while importing substrate
// HELPERS, so an import-exclusion enumeration wrongly drops them). A NEW
// direct-spawn cron absent from this set FAILS the gate — add it here with a
// one-line containment justification, or move it to an ephemeral GitHub Actions
// runner per the #5073 pattern. `cron-content-publisher` stays here (NOT
// force-fixed) — it is the deferred #5073 target.
const KNOWN_DIRECT_SPAWN_CRONS: ReadonlySet<string> = new Set([
  "cron-compound-promote", // spawns git/bash for promote-to-learning commits
  "cron-content-publisher", // 12 social secrets; firewall-contained — #5073 re-homes to GHA
  "cron-content-vendor-drift", // spawns to diff vendor docs
  "cron-daily-triage", // spawns claude directly (own CLAUDE_CODE_FLAGS), not via wrapper
  "cron-follow-through-monitor", // spawns claude directly, not via wrapper
  "cron-github-cidr-refresh", // spawns git clone + the /meta CIDR generator; firewall-contained (it maintains that very allowlist, #5284)
  "cron-rule-prune", // spawns git/bash for rule-file pruning
  "cron-strategy-review", // spawns for strategy doc review
  "cron-weekly-analytics", // spawns for analytics aggregation
]);

type ContainmentClass = "substrate-contained" | "direct-spawn" | "pure-TS";

/**
 * Return `src` with all comments and string/template-literal CONTENTS blanked,
 * so only executable code remains for the class regexes to scan. A regex-only
 * stripper is unsound here: a block-comment matcher anchored on bare
 * open/close tokens will treat a block-open token inside a line comment as a
 * real OPEN and lazily consume through to a block-close token inside a
 * cron-schedule string like "0 (slash)4 * * *" (the asterisk-slash sequence),
 * swallowing real code in between (observed collapsing ~96% of
 * cron-inngest-cron-watchdog.ts). A single-pass char scanner that tracks
 * string/template/comment state is the only correct way to neutralise those
 * tokens without bridging across string literals. Line numbers are preserved
 * (newlines kept) so a future move to line-reporting stays cheap.
 *
 * Fail direction: blanking string/template contents can only REMOVE a `spawn(`
 * token that lived inside a literal (a false-positive source), never hide one
 * that lived in real code — so the scanner fails CLOSED for the gate's purpose.
 * The one residual is a spawn/exec call placed entirely inside a template
 * interpolation (contents are blanked); no cron does this and it is a contrived
 * shape, noted here for completeness.
 */
function stripComments(src: string, blankStrings: boolean): string {
  let out = "";
  let state:
    | "code"
    | "line"
    | "block"
    | "single"
    | "double"
    | "template" = "code";
  for (let i = 0; i < src.length; i += 1) {
    const c = src[i];
    const c2 = src[i + 1];
    if (state === "code") {
      if (c === "/" && c2 === "/") {
        state = "line";
        i += 1;
      } else if (c === "/" && c2 === "*") {
        state = "block";
        i += 1;
      } else if (c === "'") {
        state = "single";
        if (!blankStrings) out += c;
      } else if (c === '"') {
        state = "double";
        if (!blankStrings) out += c;
      } else if (c === "`") {
        state = "template";
        if (!blankStrings) out += c;
      } else {
        out += c;
      }
      continue;
    }
    if (state === "line") {
      if (c === "\n") {
        state = "code";
        out += c;
      }
      continue;
    }
    if (state === "block") {
      if (c === "*" && c2 === "/") {
        state = "code";
        i += 1;
      } else if (c === "\n") {
        out += c;
      }
      continue;
    }
    // string / template states — honour backslash escapes; emit contents only
    // when keeping strings (needed to see a `child_process` import specifier).
    if (c === "\\") {
      if (!blankStrings) out += c + (src[i + 1] ?? "");
      i += 1; // skip the escaped char
      continue;
    }
    const closes =
      (state === "single" && c === "'") ||
      (state === "double" && c === '"') ||
      (state === "template" && c === "`");
    if (closes) {
      state = "code";
      if (!blankStrings) out += c;
    } else if (!blankStrings || c === "\n") {
      out += c;
    }
  }
  return out;
}

// A cron reaches an unbounded shell/network surface through ANY of these, not
// just `spawn(`: the exec family (real CALL tokens), and any acquisition of
// `child_process` (static `import … from "node:child_process"` or dynamic
// `await import("node:child_process")`). Bare `exec(`/`fork(` are deliberately
// EXCLUDED — `RegExp.prototype.exec` and stray `.fork(` would false-positive a
// pure-TS cron into a (failing) gate.
//
// Two scan surfaces, because the two signals live in different lexical places:
//   • CALL tokens (`spawn(`, `execSync(`, …) are CODE → scan strings-blanked,
//     so a `spawn(` inside a STRING literal does not false-trigger.
//   • the `child_process` module specifier is intrinsically a STRING → scan
//     comments-stripped-but-strings-kept, so the dynamic/aliased-import and
//     exec-only shapes (which a `spawn(`-only regex misses — e.g. the substrate's
//     own `_cron-safe-commit` git path uses dynamic-import + execFile) are still
//     caught, while a comment-only mention (cron-skill-freshness) is not.
//
// KNOWN LIMITATION (single-file scope): egress reached through a NEW shared
// helper that itself wraps spawn/exec (e.g. a cron whose only shell access is a
// `setupEphemeralWorkspace()` clone or a `safeCommitAndPr()` call) is NOT
// visible to this per-file scanner and classifies pure-TS. Today every such
// helper (the substrate clone, _cron-safe-commit) is shared, fixed-argv,
// already-contained infrastructure, so this is acceptable; if a future helper
// introduces unbounded per-cron egress, add its symbol to the direct-spawn
// regex or maintain a helper deny-list.
const DIRECT_CALL_RE = /\b(?:spawn|spawnSync|execFile|execFileSync|execSync)\s*\(/;

function classify(src: string): ContainmentClass {
  const codeBlankStrings = stripComments(src, true);
  if (/\bspawnClaudeEval\s*\(/.test(codeBlankStrings)) {
    return "substrate-contained";
  }
  const codeKeepStrings = stripComments(src, false);
  if (DIRECT_CALL_RE.test(codeBlankStrings) || /child_process/.test(codeKeepStrings)) {
    return "direct-spawn";
  }
  return "pure-TS";
}

interface ContainmentReport {
  klass: ContainmentClass;
  ok: boolean;
  message: string;
}

/**
 * Pure classifier + assertion builder. Membership is decided by importing the
 * actual map object / Set and calling Object.hasOwn / .has — never by grepping
 * the map files (a prose comment would false-positive). Maps are injected so the
 * fixture-mutation RED test can pass a cloned, deliberately-broken allowlist.
 */
function containmentReport(
  cronName: string,
  src: string,
  maps: {
    allowlist: Record<string, string[]>;
    tier2: ReadonlySet<string>;
    directSpawn: ReadonlySet<string>;
  },
): ContainmentReport {
  const klass = classify(src);
  const inAllow = Object.hasOwn(maps.allowlist, cronName);
  const inTier2 = maps.tier2.has(cronName);
  const inDirect = maps.directSpawn.has(cronName);

  if (klass === "substrate-contained") {
    // Exactly one of allowlist / tier2, and never direct-spawn.
    const ok = inAllow !== inTier2 && !inDirect;
    const where = inAllow && inTier2
      ? "is in BOTH CRON_BASH_ALLOWLISTS and TIER2_DEFERRED_CRONS"
      : inDirect
        ? "is wrongly listed in KNOWN_DIRECT_SPAWN_CRONS"
        : "is in NEITHER map (uncontained)";
    return {
      klass,
      ok,
      message: ok
        ? ""
        : `[cron-containment] ${cronName} is class=substrate-contained ` +
          `(calls spawnClaudeEval) but ${where}. Remediation: declare it in ` +
          `EXACTLY ONE of — CRON_BASH_ALLOWLISTS["${cronName}"] = [/* finite ` +
          `gh/git verbs */]  (Tier-1, hook-allowlisted)  OR  ` +
          `TIER2_DEFERRED_CRONS.add("${cronName}")  (Tier-2, container-egress-` +
          `firewall deferred).`,
    };
  }

  if (klass === "direct-spawn") {
    const ok = inDirect && !inAllow && !inTier2;
    return {
      klass,
      ok,
      message: ok
        ? ""
        : `[cron-containment] ${cronName} is class=direct-spawn (real spawn() ` +
          `call, not via the contained wrapper) but is not grandfathered. ` +
          `Remediation: add KNOWN_DIRECT_SPAWN_CRONS entry "${cronName}" (with ` +
          `a one-line containment justification — the #5046 container egress ` +
          `firewall must cover its egress)  OR  move it to an ephemeral GitHub ` +
          `Actions runner per the #5073 ephemeral-runner pattern. A direct-` +
          `spawn cron must NOT appear in CRON_BASH_ALLOWLISTS/TIER2_DEFERRED_CRONS.`,
    };
  }

  // pure-TS
  const ok = !inAllow && !inTier2 && !inDirect;
  return {
    klass,
    ok,
    message: ok
      ? ""
      : `[cron-containment] ${cronName} is class=pure-TS (no spawn) yet carries ` +
        `a stray containment entry (in ${[
          inAllow && "CRON_BASH_ALLOWLISTS",
          inTier2 && "TIER2_DEFERRED_CRONS",
          inDirect && "KNOWN_DIRECT_SPAWN_CRONS",
        ]
          .filter(Boolean)
          .join(" + ")}). Remediation: remove the entry — a pure-TS cron needs ` +
        `no containment declaration (likely a copy-paste from a spawning cron).`,
  };
}

function cronFiles(): string[] {
  return readdirSync(FUNCTIONS_DIR)
    .filter(
      (f) =>
        f.startsWith("cron-") &&
        f.endsWith(".ts") &&
        !f.endsWith(".test.ts") &&
        !f.startsWith("_"),
    )
    .sort();
}

const MAPS = {
  allowlist: CRON_BASH_ALLOWLISTS,
  tier2: TIER2_DEFERRED_CRONS,
  directSpawn: KNOWN_DIRECT_SPAWN_CRONS,
};

describe("cron containment classification gate (#5072)", () => {
  it("discovers cron files dynamically via readdirSync (not a hardcoded list)", () => {
    const files = cronFiles();
    expect(files.length).toBeGreaterThan(20);
    // _-prefixed shared modules and *.test.ts must be excluded.
    expect(files.some((f) => f.startsWith("_"))).toBe(false);
    expect(files.some((f) => f.endsWith(".test.ts"))).toBe(false);
  });

  it("every cron is correctly contained for its class (clean-tree GREEN gate)", () => {
    for (const file of cronFiles()) {
      const cronName = file.replace(/\.ts$/, "");
      const src = readFileSync(resolve(FUNCTIONS_DIR, file), "utf8");
      const report = containmentReport(cronName, src, MAPS);
      expect(report.ok, report.message).toBe(true);
    }
  });

  // Non-degenerate-distribution guard: if stripNonCode ever collapsed every file
  // to "" (the failure mode the regex stripper had), every cron would classify
  // pure-TS and the GREEN gate above would pass VACUOUSLY for any future
  // uncontained cron. Pin that the live tree still produces a real mix.
  it("the live tree yields a non-degenerate class distribution (guards vacuous pass)", () => {
    const counts = { "substrate-contained": 0, "direct-spawn": 0, "pure-TS": 0 };
    for (const file of cronFiles()) {
      counts[classify(readFileSync(resolve(FUNCTIONS_DIR, file), "utf8"))] += 1;
    }
    expect(counts["substrate-contained"]).toBeGreaterThan(0);
    expect(counts["direct-spawn"]).toBeGreaterThan(0);
    expect(counts["pure-TS"]).toBeGreaterThan(0);
  });

  // Grandfather-integrity: every KNOWN_DIRECT_SPAWN_CRONS entry must map to a
  // file that still classifies direct-spawn. Catches an orphaned entry left
  // behind when a grandfathered cron is deleted or refactored to pure-TS (the
  // per-file stray-entry check cannot see a deleted file).
  it("every KNOWN_DIRECT_SPAWN_CRONS entry maps to a still-direct-spawn file", () => {
    const live = new Set(cronFiles().map((f) => f.replace(/\.ts$/, "")));
    for (const cron of KNOWN_DIRECT_SPAWN_CRONS) {
      expect(live.has(cron), `${cron} is grandfathered but no longer exists`).toBe(
        true,
      );
      expect(
        classify(readFileSync(resolve(FUNCTIONS_DIR, `${cron}.ts`), "utf8")),
        `${cron} is grandfathered but no longer classifies direct-spawn`,
      ).toBe("direct-spawn");
    }
  });

  it("classifies the canonical members of each class as expected", () => {
    const read = (name: string) =>
      readFileSync(resolve(FUNCTIONS_DIR, `${name}.ts`), "utf8");
    expect(classify(read("cron-roadmap-review"))).toBe("substrate-contained");
    expect(classify(read("cron-bug-fixer"))).toBe("substrate-contained");
    expect(classify(read("cron-daily-triage"))).toBe("direct-spawn");
    expect(classify(read("cron-content-publisher"))).toBe("direct-spawn");
    // cron-workspace-gc mentions the substrate only in a comment → pure-TS.
    expect(classify(read("cron-workspace-gc"))).toBe("pure-TS");
  });

  // Adversarial stripper coverage — the one function with real fail-open risk.
  // Each case is RED against a naive regex stripper and GREEN with stripNonCode.
  it("stripNonCode does not let comments/strings hide or fake a spawn", () => {
    // A `/*` in a comment + a `*/` inside a cron-schedule string must NOT bridge
    // into a block comment that swallows the real spawn between them (the
    // cron-inngest-cron-watchdog.ts collapse). A naive regex returns pure-TS.
    expect(classify('const s = "/*"; const c = spawn("git"); const e = "*/";')).toBe(
      "direct-spawn",
    );
    // A real spawn after a `"...*/..."` cron literal on a later line stays visible.
    expect(
      classify('const cron = "0 */4 * * *";\nconst c = spawn("bash", []);'),
    ).toBe("direct-spawn");
    // A `spawn(` that lives ONLY inside a string literal is not real egress →
    // must NOT force a (failing) direct-spawn classification.
    expect(classify('const doc = "call spawn(x) somewhere"; export const y = 1;')).toBe(
      "pure-TS",
    );
    // Exec-family + dynamic child_process acquisition are direct-spawn, not pure-TS.
    expect(
      classify('const { execFile } = await import("node:child_process");'),
    ).toBe("direct-spawn");
    expect(classify('execSync("git status");')).toBe("direct-spawn");
    // `.exec(` (RegExp) and `spawnCwd` (identifier) must NOT trip detection.
    expect(classify("const m = /x/.exec(s); let spawnCwd = null;")).toBe("pure-TS");
  });

  // Failure-message contract (the #5072 deliverable): each message must name the
  // detected class AND the literal remediation map line. Self-test the builder
  // with synthetic crons so the contract itself is regression-guarded.
  it("failure messages emit the class + the literal remediation map line", () => {
    const emptyMaps = {
      allowlist: {} as Record<string, string[]>,
      tier2: new Set<string>(),
      directSpawn: new Set<string>(),
    };

    const hook = containmentReport(
      "cron-synthetic-hook",
      "await spawnClaudeEval({ cronName });",
      emptyMaps,
    );
    expect(hook.klass).toBe("substrate-contained");
    expect(hook.ok).toBe(false);
    expect(hook.message).toContain("substrate-contained");
    expect(hook.message).toContain('CRON_BASH_ALLOWLISTS["cron-synthetic-hook"]');
    expect(hook.message).toContain("TIER2_DEFERRED_CRONS");

    const direct = containmentReport(
      "cron-synthetic-direct",
      'const child = spawn("git", ["status"]);',
      emptyMaps,
    );
    expect(direct.klass).toBe("direct-spawn");
    expect(direct.ok).toBe(false);
    expect(direct.message).toContain("direct-spawn");
    expect(direct.message).toContain("KNOWN_DIRECT_SPAWN_CRONS");
    expect(direct.message).toContain("#5073");

    const stray = containmentReport(
      "cron-synthetic-pure",
      "export const x = 1; // no spawn here",
      { ...emptyMaps, directSpawn: new Set(["cron-synthetic-pure"]) },
    );
    expect(stray.klass).toBe("pure-TS");
    expect(stray.ok).toBe(false);
    expect(stray.message).toContain("pure-TS");
    expect(stray.message).toContain("stray containment entry");
  });

  // RED proof: the clean tree is already GREEN, so to prove the gate BITES we
  // mutate a cloned allowlist (delete cron-roadmap-review) and confirm the real
  // hook-contained cron is flagged uncontained with its remediation line. No
  // source is edited — the mutation lives only in this cloned object.
  it("BITES: a hook-contained cron removed from the allowlist is flagged uncontained", () => {
    const mutatedAllowlist = { ...CRON_BASH_ALLOWLISTS };
    delete mutatedAllowlist["cron-roadmap-review"];

    const src = readFileSync(
      resolve(FUNCTIONS_DIR, "cron-roadmap-review.ts"),
      "utf8",
    );
    const report = containmentReport("cron-roadmap-review", src, {
      allowlist: mutatedAllowlist,
      tier2: TIER2_DEFERRED_CRONS,
      directSpawn: KNOWN_DIRECT_SPAWN_CRONS,
    });

    expect(report.klass).toBe("substrate-contained");
    expect(report.ok).toBe(false);
    expect(report.message).toContain("NEITHER map (uncontained)");
    expect(report.message).toContain(
      'CRON_BASH_ALLOWLISTS["cron-roadmap-review"]',
    );
  });
});
