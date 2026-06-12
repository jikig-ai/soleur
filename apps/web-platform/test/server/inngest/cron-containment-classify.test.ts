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
  "cron-rule-prune", // spawns git/bash for rule-file pruning
  "cron-strategy-review", // spawns for strategy doc review
  "cron-weekly-analytics", // spawns for analytics aggregation
]);

type ContainmentClass = "substrate-contained" | "direct-spawn" | "pure-TS";

/**
 * Strip JS/TS comments so a prose mention of `spawn(` /
 * `_cron-claude-eval-substrate` (e.g. cron-workspace-gc:5) cannot be mistaken
 * for executable code. Block comments first, then line comments — guarding `//`
 * preceded by `:` so `https://` inside a string literal is not truncated.
 */
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/([^:])\/\/.*$/gm, "$1");
}

function classify(src: string): ContainmentClass {
  const code = stripComments(src);
  if (/\b(?:spawnClaudeEval|runClaudeEval)\s*\(/.test(code)) {
    return "substrate-contained";
  }
  if (/\bspawn\s*\(/.test(code)) {
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
