import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// feat-operator-cc-oauth FR6 — CWE-526 single-injection-site guard.
//
// `CLAUDE_CODE_OAUTH_TOKEN` is a subprocess auth env var. It must be SET in
// EXACTLY ONE place — `server/agent-env.ts buildAgentEnv` — so the
// deny-by-default subprocess env allowlist has a single auditable injection
// point. Any other module naming the literal is a potential 2nd injection
// site (a direct `process.env` write that bypasses the allowlist), the bug
// class this test exists to catch. Negative-space source grep, kept in a
// standalone file (no `node:fs` mock) per
// `2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space`.
//
// W1 (#9601, ADR-272) moved the NAME into `server/agent-auth-env-vars.ts` so the
// sandbox config can deny exactly the set `buildAgentEnv` injects. That module
// only DEFINES names. Naming the literal through an identifier would otherwise
// slip past a grep for the literal, so the identifiers are pinned too: who may
// reference the shared names, and that the definition module never writes env.

const ROOT = path.join(__dirname, "..");
const SCAN_DIRS = ["server", "lib", "app"];
const LITERAL = "CLAUDE_CODE_OAUTH_TOKEN";
const AUTH_NAMES_MODULE = path.join("server", "agent-auth-env-vars.ts");
const ALLOWED = new Set([path.join("server", "agent-env.ts"), AUTH_NAMES_MODULE]);
// Identifiers that carry the auth variable names, and the only modules that
// may reference them: the injector reads the single names; the sandbox config
// reads the full set to deny it.
const NAME_IDENTIFIER_USERS: Record<string, Set<string>> = {
  OAUTH_ENV_VAR: new Set([path.join("server", "agent-env.ts"), AUTH_NAMES_MODULE]),
  API_KEY_ENV_VAR: new Set([path.join("server", "agent-env.ts"), AUTH_NAMES_MODULE]),
  AGENT_AUTH_ENV_VARS: new Set([
    path.join("server", "agent-runner-sandbox-config.ts"),
    AUTH_NAMES_MODULE,
  ]),
};

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
  it("is named only by server/agent-env.ts and the names module", () => {
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

  it("the shared auth-name identifiers are used only by their sanctioned modules", () => {
    const offenders: string[] = [];
    for (const base of SCAN_DIRS) {
      for (const file of walkTsFiles(path.join(ROOT, base))) {
        const rel = path.relative(ROOT, file);
        const text = readFileSync(file, "utf8");
        for (const [ident, allowed] of Object.entries(NAME_IDENTIFIER_USERS)) {
          if (allowed.has(rel)) continue;
          if (new RegExp(`\\b${ident}\\b`).test(text)) offenders.push(`${rel} -> ${ident}`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });

  it("the names module only defines names: it never reads or writes the environment", () => {
    const text = readFileSync(path.join(ROOT, AUTH_NAMES_MODULE), "utf8");
    // The instrument is not empty: the module really defines the names.
    expect(text).toContain(LITERAL);
    expect(text).not.toMatch(/process\.env|\benv\s*\[|\.env\b/);
  });
});
