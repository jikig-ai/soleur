import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// feat-operator-cc-oauth FR6 — CWE-526 single-injection-site guard.
//
// `CLAUDE_CODE_OAUTH_TOKEN` is a subprocess auth env var. It must be set in
// EXACTLY ONE place — `server/agent-env.ts buildAgentEnv` — so the
// deny-by-default subprocess env allowlist has a single auditable injection
// point. Any other module naming the literal is a potential 2nd injection
// site (a direct `process.env` write that bypasses the allowlist), the bug
// class this test exists to catch. Negative-space source grep, kept in a
// standalone file (no `node:fs` mock) per
// `2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space`.

const ROOT = path.join(__dirname, "..");
const SCAN_DIRS = ["server", "lib", "app"];
const LITERAL = "CLAUDE_CODE_OAUTH_TOKEN";
const ALLOWED = new Set([path.join("server", "agent-env.ts")]);

function* walkTsFiles(dir: string): Generator<string> {
  let entries: import("node:fs").Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return; // dir absent — nothing to scan
  }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === "node_modules" || e.name === ".next") continue;
      yield* walkTsFiles(full);
    } else if (/\.tsx?$/.test(e.name) && !/\.(test|spec)\.tsx?$/.test(e.name)) {
      yield full;
    }
  }
}

describe("CLAUDE_CODE_OAUTH_TOKEN single injection site (CWE-526)", () => {
  it("is referenced only by server/agent-env.ts", () => {
    const offenders: string[] = [];
    for (const base of SCAN_DIRS) {
      for (const file of walkTsFiles(path.join(ROOT, base))) {
        const rel = path.relative(ROOT, file);
        if (ALLOWED.has(rel)) continue;
        if (readFileSync(file, "utf8").includes(LITERAL)) offenders.push(rel);
      }
    }
    expect(offenders).toEqual([]);
  });
});
